#!/usr/bin/env bash
# Toggle Spotify in and out of the i3 scratchpad.
#
# Same shape as toggle_bluebubbles.sh / toggle_whatsapp.sh / toggle_firstmate.sh:
# the scratchpad does the hiding, so the process is never touched and playback
# keeps running while the window is out of sight. Closing the window instead
# would end the client and stop the music, which is exactly what we do not want
# from a show/hide key.
#
#   in scratchpad  -> show it
#   already shown  -> hide it back
#   not running    -> launch it
#
# NOTE on the criteria: VERIFIED 2026-07-29 with xprop against the live client on
# main (read-only, on windows that were already open -- nothing was launched to
# check it): WM_CLASS is "spotify", "Spotify", i.e. instance lowercase and class
# capitalised. i3 matches [class=...] against the second field, so the anchored
# case-insensitive match below is what makes this work. Keep it case-insensitive:
# which field carries which capitalisation has moved between releases before, and
# "(?i)^spotify$" stays correct either way.

set -uo pipefail

CRITERIA='[class="(?i)^spotify$"]'
LAUNCH="spotify"

# The four overlay scratchpads (spotify, bluebubbles, whatsapp, firstmate) are
# mutually exclusive: pulling one out puts the other three away, so they never
# overlap (they all share the same centred 60ppt geometry, so otherwise one just
# hides behind another and closing the stack takes several $mod+q presses).
#
# This HIDES the other windows, it does not kill them. Every process is
# deliberately kept alive: notifications keep arriving for the messaging apps
# while hidden, firstmate's herdr connection to mirage stays up rather than being
# torn down with its terminal, and Spotify keeps playing.
#
# "move scratchpad" on a window that is already in the scratchpad is a harmless
# no-op, and it never makes a hidden window visible, so this needs no guard. If
# an app is not running at all its criteria simply matches nothing.
OTHERS=('[class="(?i)^bluebubbles$"]' '[instance="(?i)^web\.whatsapp\.com$"]' '[class="(?i)^firstmate$"]')
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
    if (wp.get('class') or '').lower() == 'spotify':
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
        # Nothing to do about the other three here -- we are hiding, not revealing.
        i3-msg "$CRITERIA move scratchpad" >/dev/null
        ;;
    none)
        # No Spotify window exists at all, so the app is not running.
        #
        # This branch must LAUNCH AND SHOW, which is why Spotify's for_window rule
        # sizes and centres but deliberately does NOT end in "move scratchpad" the
        # way bluebubbles' and whatsapp's rules do -- same reasoning as firstmate.
        # The keypress would look dead if the rule swallowed the new window.
        #
        # start_spotify_hidden.sh pre-warms Spotify hidden at login, so in normal
        # use this branch is the fallback: it fires when that did not run (or
        # found nothing to launch) or when Spotify has since been quit.
        hide_other
        exec $LAUNCH
        ;;
esac
