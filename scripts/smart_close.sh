#!/bin/bash
# If the focused window is a scratchpad app, hide it instead of killing it.
# Otherwise, kill it normally.

# Bluebubbles is here on purpose: closeToTray is off, so a real kill would end
# the process and silently stop all iMessage notifications. Hide it instead.
# firstmate is here for the same shape of reason: it is a terminal running the
# herdr client, so killing the window kills the terminal and tears down the SSH
# connection to mirage along with the attached session. Hide it instead.
# ("firstmate" is the WM_CLASS override passed at launch, not alacritty's own
# class -- see toggle_firstmate.sh. Plain terminals stay killable.)
# spotify is here so $mod+q hides the overlay instead of ending playback.
# The match below is grep -qiE, so the case spotify actually sets on WM_CLASS
# does not matter.
SCRATCHPAD_CLASSES="TelegramDesktop|Bluebubbles|firstmate|spotify"
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
