#!/bin/bash
# If the focused window is a scratchpad app, hide it instead of killing it.
# Otherwise, kill it normally.

SCRATCHPAD_CLASSES="TelegramDesktop"
SCRATCHPAD_TITLES="WhatsApp"

WID=$(xdotool getactivewindow 2>/dev/null) || { i3-msg 'kill'; exit; }
FOCUSED_CLASS=$(xdotool getwindowclassname "$WID" 2>/dev/null)
FOCUSED_TITLE=$(xdotool getwindowname "$WID" 2>/dev/null)

if echo "$FOCUSED_CLASS" | grep -qiE "^($SCRATCHPAD_CLASSES)$"; then
    i3-msg 'move scratchpad'
elif echo "$FOCUSED_TITLE" | grep -qiE "$SCRATCHPAD_TITLES"; then
    i3-msg 'move scratchpad'
else
    i3-msg 'kill'
fi
