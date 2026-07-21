#!/usr/bin/env bash
# Bound to $mod+Shift+r: re-apply the display layout, then restart i3 in place.
#
# Deliberately sequential. In i3 a binding like
#     exec --no-startup-id /usr/local/bin/display-hotplug.sh; restart
# fires the exec asynchronously, so xrandr can reshape the X screen *while* i3
# is restarting and i3 may miss the RandR change. Doing the xrandr work first
# and only then asking i3 to restart guarantees i3 comes back up already seeing
# the corrected outputs. i3 double-forks exec'd children, so this script is
# detached from i3 and survives the restart.
set -u

/usr/local/bin/display-hotplug.sh

# Let X settle before i3 re-enumerates outputs.
sleep 0.3

command -v i3-msg >/dev/null 2>&1 && i3-msg -q restart

exit 0
