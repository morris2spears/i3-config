#!/usr/bin/env bash
set -euo pipefail

# Usage: toggle_app.sh <match_type> <match_value> <launch_cmd>
# match_type: "class" or "title"
#
# If the app is in the scratchpad → pull it out
# If the app is visible → flash its border urgent (red highlight)
# If not running → launch it

MATCH_TYPE="$1"
MATCH_VALUE="$2"
LAUNCH_CMD="$3"

TREE=$(i3-msg -t get_tree)

if [ "$MATCH_TYPE" = "class" ]; then
    I3_CRITERIA="[class=\"$MATCH_VALUE\"]"
else
    I3_CRITERIA="[title=\"$MATCH_VALUE\"]"
fi

FOUND=$(echo "$TREE" | python3 -c "
import sys, json
tree = json.load(sys.stdin)
match_type = '$MATCH_TYPE'
match_value = '$MATCH_VALUE'

def find(node):
    if match_type == 'class':
        wp = node.get('window_properties') or {}
        if wp.get('class') == match_value:
            return node
    else:
        name = node.get('name') or ''
        if match_value in name:
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
    if in_scratchpad(tree, n['id']):
        print('scratchpad')
    else:
        print('visible')
else:
    print('none')
")

case "$FOUND" in
    scratchpad)
        i3-msg "$I3_CRITERIA scratchpad show; $I3_CRITERIA floating disable" >/dev/null
        ;;
    visible)
        i3-msg "$I3_CRITERIA focus" >/dev/null
        ;;
    none)
        $LAUNCH_CMD &
        ;;
esac
