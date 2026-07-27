#!/bin/bash

STATIC=/home/morris/Wallpapers/black-hole-in-nebula-2-static.png
VIDEO=/home/morris/Wallpapers/black-hole-in-nebula-2-optimized.mp4

# Geometry ("WxH+X+Y") of the active output to paint: primary if it has an
# active mode, otherwise the first active output. Empty if nothing is active.
target_geometry() {
    xrandr --query | awk '
        / connected/ {
            geom=""
            for (i=1; i<=NF; i++)
                if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) geom=$i
            if (geom == "") next
            if ($0 ~ / connected primary /) { print geom; exit }
            if (first == "") first=geom
        }
        END { if (first != "") print first }
    '
}

# Fingerprint of outputs + their active mode/position. Includes geometry so a
# panel turning off (e.g. eDP off on HDMI+AC) triggers a wallpaper restart even
# though its connected/disconnected status is unchanged.
layout_fingerprint() {
    xrandr --query | awk '/ connected| disconnected/ {
        geom="off"
        for (i=1; i<=NF; i++)
            if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) geom=$i
        print $1, geom
    }'
}

paint_static() {
    feh --bg-scale "$STATIC"
}

start_live() {
    local geom
    geom=$(target_geometry)
    [ -z "$geom" ] && return
    pkill -f 'xwinwrap.*black-hole' 2>/dev/null
    sleep 0.3
    xwinwrap -g "$geom" -ni -fdt -un -b -nf -ov -- \
        mpv --wid=%WID --no-audio --loop --no-osc --no-osd-bar \
            --panscan=1.0 --hwdec=auto --gpu-context=x11egl \
            --video-sync=display-resample --interpolation --tscale=mitchell \
            "$VIDEO" &
}

stop_live() {
    pkill -f 'xwinwrap.*black-hole'
}

LAST_AC=""
LAST_LAYOUT=""

paint_static

while true; do
    AC_ONLINE=$(cat /sys/class/power_supply/AC/online 2>/dev/null)
    LAYOUT=$(layout_fingerprint)

    if [ "$LAYOUT" != "$LAST_LAYOUT" ]; then
        paint_static
        if [ "$AC_ONLINE" = "1" ]; then
            start_live
        else
            stop_live
        fi
    elif [ "$AC_ONLINE" != "$LAST_AC" ]; then
        if [ "$AC_ONLINE" = "1" ]; then
            start_live
        else
            stop_live
        fi
    fi

    LAST_LAYOUT="$LAYOUT"
    LAST_AC="$AC_ONLINE"

    sleep 5
done
