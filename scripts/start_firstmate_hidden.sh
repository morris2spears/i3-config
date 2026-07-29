#!/usr/bin/env bash
# Autostart FirstMate at login, already hidden in the scratchpad, so the first
# $mod+Shift+i of the day pops instantly instead of sitting there waiting on an
# SSH attach to mirage.
#
# WHY THIS IS A SCRIPT AND NOT "move scratchpad" IN THE for_window RULE
#   bluebubbles hides itself at login purely via `move scratchpad` in its
#   for_window rule. That works for it because bluebubbles runs from login to
#   logout -- the "launch it" branch of its toggle script realistically never
#   fires, so nobody notices that the rule would hide a freshly launched window
#   too.
#
#   FirstMate is different: it is a terminal session the user quits regularly
#   (herdr exits -> alacritty exits -> window gone). toggle_firstmate.sh's
#   "not running" branch therefore fires often, and that branch must LAUNCH AND
#   SHOW. A `move scratchpad` in the for_window rule fires on EVERY window
#   creation, including that one, so the keypress would spawn an invisible
#   window and look like nothing happened at all.
#
#   So: the for_window rule sizes and centres but does NOT hide, and the hiding
#   happens here instead -- once, at login, after the window appears. Both paths
#   then behave correctly. This is the same launch-then-hide-when-ready trick
#   start_hidden.sh already uses for whatsapp.
#
# CONNECTIVITY, AND WHY WE PREFLIGHT INSTEAD OF JUST LAUNCHING
#   Unlike bluebubbles and whatsapp, this window's command opens an SSH
#   connection to mirage over tailscale. At login that can easily fail: tailscale
#   is often not up yet, the network may not be ready, mirage may be down.
#
#   Chosen behaviour -- poll a cheap bounded `ssh mirage true` until it works,
#   and if it never does, exit 0 having created NO WINDOW AT ALL.
#
#   Rationale (the simplest option that fails cleanly): the failure mode that
#   actually hurts is a dead or half-attached terminal parked in the scratchpad,
#   because toggle_firstmate.sh would then see state "scratchpad" and cheerfully
#   show that broken window instead of launching a fresh one -- the user gets a
#   corpse and no way to fix it short of $mod+Shift+q. Creating no window leaves
#   state "none", so the first keypress just launches FirstMate normally. The
#   pre-warm is a bonus, never a prerequisite, and that is the whole point.
#
#   Nothing here can hang login: i3's `exec` forks this script, every probe is
#   bounded by ConnectTimeout, and the whole retry window is capped (see below).

set -uo pipefail

CRITERIA='[class="(?i)^firstmate$"]'
SSH_TARGET="mirage"

# Retry budget for the connectivity preflight: TRIES probes, GAP seconds apart,
# each probe itself capped at 5s by ConnectTimeout. 30 x 5s gives tailscale
# roughly two and a half minutes to come up after login, which is far more than
# it has ever needed, and then we stop. We are not a supervisor -- if mirage is
# genuinely down, the keybind is the retry.
TRIES=30
GAP=5

# Which terminal to launch. i3 passes its own $term as $1 so this script never
# has to know which machine it is running on: on main $term is plain `alacritty`,
# on carbon it is ~/.config/alacritty/term-launch.sh, a wrapper that sets a
# per-monitor DPI scale factor and ends in `exec alacritty "$@"`. The fallback
# only exists so the script still works when run by hand from a shell.
TERM_CMD="${1:-}"
if [ -z "$TERM_CMD" ]; then
    if [ -x "$HOME/.config/alacritty/term-launch.sh" ]; then
        TERM_CMD="$HOME/.config/alacritty/term-launch.sh"
    else
        TERM_CMD="alacritty"
    fi
fi

# Same alacritty profile override as toggle_firstmate.sh -- see the long comment
# there. Short version: this window must NOT get the tmux key bindings, or
# alacritty rewrites Super+h/l before herdr can see them. Guarded on existence
# so a host without herdr.toml behaves exactly as it did before.
CFG_ARGS=()
HERDR_CFG="$HOME/.config/alacritty/herdr.toml"
[ -f "$HERDR_CFG" ] && CFG_ARGS=(--config-file "$HERDR_CFG")

# Never double-launch. This is an `exec` (not `exec_always`) in the i3 config so
# a reload will not re-run it, but running this script by hand while FirstMate is
# already up would otherwise stack a second window that the toggle cannot see
# past -- find() returns the first match only.
if xdotool search --class '^firstmate$' >/dev/null 2>&1; then
    exit 0
fi

# Preflight: wait for mirage to actually be reachable before opening any window.
# BatchMode=yes so a missing key or a password prompt fails immediately instead
# of blocking forever on stdin that nothing is attached to.
ready=0
for _ in $(seq 1 "$TRIES"); do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" true >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep "$GAP"
done

# Never came up -- leave no window behind, so the state stays "none" and the
# first $mod+Shift+i launches FirstMate the normal way.
[ "$ready" -eq 1 ] || exit 0

# Re-check the guard now that the preflight is done. The wait above can last
# minutes, which is ample time for the user to have got bored and pressed
# $mod+Shift+i themselves -- and toggle_firstmate.sh would have launched
# FirstMate for real. Without this second look we would launch a duplicate on
# top of it, and the toggle's find() only ever returns the first match, so the
# spare would be unreachable: invisible to the keybind and unkillable by $mod+q.
if xdotool search --class '^firstmate$' >/dev/null 2>&1; then
    exit 0
fi

"$TERM_CMD" "${CFG_ARGS[@]}" --class firstmate -e herdr --remote mirage &

# Hide it as soon as it exists. Poll instead of sleeping a fixed amount: window
# creation races with the herdr attach and neither has a predictable duration.
# `move scratchpad` only reports success:true once a window actually matched,
# which makes that the readiness signal.
#
# If the terminal died on us anyway (herdr failed after the preflight passed,
# mirage dropped mid-attach), no window ever matches, this loop simply expires
# and we exit having hidden nothing -- again leaving state "none" rather than a
# corpse in the scratchpad.
for _ in $(seq 1 30); do
    sleep 1
    if i3-msg "$CRITERIA move scratchpad" 2>/dev/null | grep -q '"success":true'; then
        exit 0
    fi
done

exit 0
