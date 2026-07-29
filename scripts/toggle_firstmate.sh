#!/usr/bin/env bash
# Toggle FirstMate (a terminal running the herdr client against mirage) in and
# out of the i3 scratchpad.
#
# Why the scratchpad instead of just closing the window:
#   FirstMate is not an app with its own tray or background service -- it is a
#   terminal process. Closing the window kills that terminal, which tears down
#   the herdr client connection to mirage and loses the attached session. Hiding
#   it in the scratchpad never touches the process, so pulling it back resumes
#   exactly where it left off. Same reasoning as toggle_bluebubbles.sh, just a
#   different thing being protected: a live connection rather than notifications.
#
#   in scratchpad  -> show it
#   already shown  -> hide it back
#   not running    -> launch it
#
# NOTE: the window is identified by a class override handed to alacritty at
# launch (--class firstmate), never by anything alacritty picks on its own --
# every other terminal on the box is WM_CLASS "Alacritty", so matching that
# would grab whichever terminal happened to be open.
#
# On the `--class` flag: alacritty's help advertises
# `--class <general> | <general>,<instance>`, which reads like a bare value sets
# only one of the two fields. It does not. Verified with xprop on alacritty
# 0.16.1 (main) and 0.17.0 (carbon) -- a bare `--class firstmate` yields
# WM_CLASS(STRING) = "firstmate", "firstmate", i.e. instance AND general are both
# set. So matching on class below is safe, and matching on instance would behave
# identically. Do not "fix" this to the two-value form; it produces the same
# result and only adds noise.

set -uo pipefail

CRITERIA='[class="(?i)^firstmate$"]'

# Which terminal to launch. i3 passes its own $term as $1 so this script never
# has to know which machine it is running on: on main $term is plain `alacritty`,
# on carbon it is ~/.config/alacritty/term-launch.sh, a wrapper that sets a
# per-monitor DPI scale factor and ends in `exec alacritty "$@"` (so it forwards
# the arguments below verbatim). Bypassing it on carbon would render FirstMate at
# the wrong physical font size on the high-DPI laptop panel.
#
# The fallback only exists so the script still works when run by hand from a
# shell, where there is no $1. It prefers the wrapper when one is installed.
TERM_CMD="${1:-}"
if [ -z "$TERM_CMD" ]; then
    if [ -x "$HOME/.config/alacritty/term-launch.sh" ]; then
        TERM_CMD="$HOME/.config/alacritty/term-launch.sh"
    else
        TERM_CMD="alacritty"
    fi
fi

# FirstMate needs a DIFFERENT alacritty profile from every other terminal here.
# alacritty.toml rewrites Super+h/l into the escape sequences tmux reads as
# user-keys, but this window runs herdr directly with no tmux in between, and
# herdr matches a real Super+h/l itself (previous_tab/next_tab in
# ~/.config/herdr/config.toml) via the kitty keyboard protocol. With the tmux
# profile applied, alacritty would eat the chord first and herdr's tab bindings
# could never fire. herdr.toml is the same config minus those bindings.
#
# Guarded on existence so this script is still correct on a host that has no
# herdr.toml -- there it just launches with the default profile as before.
CFG_ARGS=()
HERDR_CFG="$HOME/.config/alacritty/herdr.toml"
[ -f "$HERDR_CFG" ] && CFG_ARGS=(--config-file "$HERDR_CFG")

# The four overlay scratchpads (firstmate, bluebubbles, whatsapp, spotify) are
# mutually exclusive: pulling one out puts the other three away, so they never
# overlap. They all share the same centred 60ppt geometry, so without this one
# simply sits on top of another and closing the stack takes several $mod+q
# presses.
#
# This HIDES the other windows, it does not kill them. Every process is
# deliberately kept alive: notifications keep arriving for the two messaging
# apps, spotify keeps playing, and the herdr connection stays up for this one.
#
# "move scratchpad" on a window that is already in the scratchpad is a harmless
# no-op, and it never makes a hidden window visible, so this needs no guard. If
# an app is not running at all its criteria simply matches nothing.
OTHERS=('[class="(?i)^bluebubbles$"]' '[instance="(?i)^web\.whatsapp\.com$"]' '[class="(?i)^spotify$"]')
hide_other() {
    local o
    for o in "${OTHERS[@]}"; do
        i3-msg "$o move scratchpad" >/dev/null 2>&1 || true
    done
}

STATE=$(i3-msg -t get_tree | python3 -c "
import sys, json
tree = json.load(sys.stdin)

def find(node):
    wp = node.get('window_properties') or {}
    if (wp.get('class') or '').lower() == 'firstmate':
        return node
    for n in node.get('nodes', []) + node.get('floating_nodes', []):
        r = find(n)
        if r: return r
    return None

def in_scratchpad(node, target_id):
    if (node.get('name') or '') == '__i3_scratch':
        def has(n):
            if n.get('id') == target_id: return True
            return any(has(c) for c in n.get('nodes', []) + n.get('floating_nodes', []))
        return has(node)
    return any(in_scratchpad(c, target_id) for c in node.get('nodes', []) + node.get('floating_nodes', []))

n = find(tree)
if n:
    print('scratchpad' if in_scratchpad(tree, n['id']) else 'visible')
else:
    print('none')
")

case "$STATE" in
    scratchpad)
        # Hidden in the scratchpad -- show it, then re-apply size and centring.
        #
        # The for_window rule only fires once, at window creation, so the
        # floating geometry i3 remembers can drift afterwards (a stray resize, a
        # move while the window was hidden, an output/resolution change). Worse,
        # "resize set N ppt" and "move position center" are silent no-ops while a
        # window sits in __i3_scratch -- i3 returns success but resolves the
        # percentage against the scratchpad pseudo-output, which stores garbage
        # top-left coords that every later show then reuses.
        #
        # Re-centring here, in the same command chain and strictly AFTER
        # "scratchpad show" has put the window back on the real output, makes the
        # position self-healing on every pull instead of a one-shot at creation.
        hide_other
        i3-msg "$CRITERIA scratchpad show, floating enable, resize set 60 ppt 60 ppt, move position center" >/dev/null
        ;;
    visible)
        # Sitting on a normal workspace (e.g. dragged out by hand): put it away.
        # Nothing to do about the others here -- we are hiding, not revealing.
        i3-msg "$CRITERIA move scratchpad" >/dev/null
        ;;
    none)
        # No FirstMate window exists at all, so herdr is not running: either the
        # user quit the session, or the login pre-warm in
        # start_firstmate_hidden.sh gave up because mirage was unreachable.
        #
        # This branch must LAUNCH AND SHOW, which is exactly why this window's
        # for_window rule sizes and centres but deliberately does NOT end in
        # "move scratchpad" the way bluebubbles' and whatsapp's rules do. That
        # rule fires on every window creation, so it would swallow this launch
        # and the keypress would appear to do nothing. Hiding at login is done
        # once, explicitly, by start_firstmate_hidden.sh instead -- see the long
        # comment at the top of that script.
        hide_other
        exec "$TERM_CMD" "${CFG_ARGS[@]}" --class firstmate -e herdr --remote mirage
        ;;
esac
