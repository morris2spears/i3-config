#!/usr/bin/env bash
# Toggle BlueBubbles in and out of the i3 scratchpad.
#
# Why the scratchpad instead of BlueBubbles' own tray:
#   With closeToTray/minimizeToTray enabled the app unmaps its own window, which
#   makes it "Withdrawn" and completely invisible to i3 -- no criteria can match
#   it, so no keybind could bring it back and only a tray click worked. Both tray
#   prefs are now off, so the window always stays a real, i3-managed window and
#   the scratchpad does the hiding. The process is never touched, so desktop
#   notifications keep working while it is hidden.
#
#   in scratchpad  -> show it
#   already shown  -> hide it back
#   not running    -> launch it
#
# NOTE: BlueBubbles' Flutter build also creates helper windows whose WM_CLASS is
# a random string (e.g. "zBGqqegECb"), regenerated every launch and different on
# every machine. The stable, real toplevel is WM_CLASS = "bluebubbles",
# "Bluebubbles" -- always match that, never the random one.

set -uo pipefail

CRITERIA='[class="(?i)^bluebubbles$"]'
LAUNCH="$HOME/.local/bin/bluebubbles"

# The two messaging scratchpads are mutually exclusive: pulling one out puts the
# other away, so they never overlap (they share the same centred 60ppt geometry,
# so otherwise one just hides behind the other).
#
# This HIDES the other window, it does not kill it. Both processes are
# deliberately kept alive so notifications keep arriving while hidden -- that is
# the whole reason this setup uses the scratchpad instead of closing windows.
#
# "move scratchpad" on a window that is already in the scratchpad is a harmless
# no-op, and it never makes a hidden window visible, so this needs no guard. If
# WhatsApp is not running at all the criteria simply matches nothing.
OTHER='[instance="(?i)^web\.whatsapp\.com$"]'
hide_other() { i3-msg "$OTHER move scratchpad" >/dev/null 2>&1 || true; }

STATE=$(i3-msg -t get_tree | python3 -c "
import sys, json
tree = json.load(sys.stdin)

def find(node):
    wp = node.get('window_properties') or {}
    if (wp.get('class') or '').lower() == 'bluebubbles':
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
        # Nothing to do about WhatsApp here -- we are hiding, not revealing.
        i3-msg "$CRITERIA move scratchpad" >/dev/null
        ;;
    none)
        # No BlueBubbles window exists at all, so the app is not running.
        hide_other
        exec "$LAUNCH"
        ;;
esac
