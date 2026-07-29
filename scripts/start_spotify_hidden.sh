#!/usr/bin/env bash
# Autostart Spotify at login, already hidden in the scratchpad, so the first
# $mod+Shift+s of the day pops instantly instead of sitting there waiting on the
# client to cold-start.
#
# WHY THIS IS A SCRIPT AND NOT "move scratchpad" IN THE for_window RULE
#   Exactly the same reason as start_firstmate_hidden.sh -- see the long comment
#   in that file for the full version. Short form: spotify's for_window rule
#   deliberately ends at "move position center" with NO "move scratchpad",
#   because toggle_spotify.sh's "not running" branch has to LAUNCH AND SHOW.
#   for_window fires on EVERY window creation, including that one, so hiding
#   from the rule would make the keypress spawn an invisible window and look
#   dead. The rule sizes and centres; the hiding happens here instead, once, at
#   login, after the window actually exists. Both paths then behave correctly.
#
#   This is the same launch-then-hide-when-ready trick start_hidden.sh already
#   uses for whatsapp and start_firstmate_hidden.sh uses for firstmate.
#
# WHY NO PREFLIGHT
#   firstmate needs one because its window is an SSH attach to mirage that can
#   fail at login and leave a dead terminal parked in the scratchpad. Spotify is
#   a plain local binary with nothing to wait for: it either launches or it does
#   not. The only thing worth checking is that it is installed at all (carbon did
#   not have it until 2026-07-29), which is the guard below.
#
# FAILURE BEHAVIOUR
#   Every failure path exits 0 having created NO WINDOW, which leaves
#   toggle_spotify.sh seeing state "none" so the first $mod+Shift+s just launches
#   Spotify normally. The pre-warm is a bonus, never a prerequisite. Nothing here
#   can hang login: i3's `exec` forks this script and the retry window is capped.

set -uo pipefail

CRITERIA='[class="(?i)^spotify$"]'
LAUNCH_BIN="spotify"

# Not installed -> do nothing, silently and successfully. No error window, no
# half-started state. This is what makes the identical config safe to ship to a
# machine where spotify is missing.
command -v "$LAUNCH_BIN" >/dev/null 2>&1 || exit 0

# Never double-launch. This is an `exec` (not `exec_always`) in the i3 config so
# a reload will not re-run it, but running this script by hand while Spotify is
# already up would otherwise stack a second client that the toggle cannot see
# past -- toggle_spotify.sh's find() returns the first match only, so the spare
# would be invisible to the keybind.
if xdotool search --class '^spotify$' >/dev/null 2>&1; then
    exit 0
fi

"$LAUNCH_BIN" >/dev/null 2>&1 &

# Hide it as soon as it exists. Poll rather than sleeping a fixed amount: window
# creation races with the client's start-up and that has no predictable
# duration. `move scratchpad` only reports success:true once a window actually
# matched, which makes that the readiness signal.
#
# 60 tries, not the 30 that start_firstmate_hidden.sh uses: firstmate is a
# terminal that draws almost immediately once SSH is up, whereas Spotify is a
# large Electron-style client cold-starting off disk while everything else in
# the session is also starting. A minute is a generous ceiling, and overshooting
# costs nothing because we stop at the first success.
#
# If Spotify never draws a window, this loop simply expires and we exit having
# hidden nothing -- again leaving state "none" rather than a corpse in the
# scratchpad.
for _ in $(seq 1 60); do
    sleep 1
    if i3-msg "$CRITERIA move scratchpad" 2>/dev/null | grep -q '"success":true'; then
        exit 0
    fi
done

exit 0
