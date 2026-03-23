#!/bin/bash

# Set static wallpaper as the base layer (always present, prevents flash)
feh --bg-scale /home/morris/Wallpapers/black-hole-in-nebula-2-static.png

LAST_STATE=""

while true; do
    AC_ONLINE=$(cat /sys/class/power_supply/AC/online)

    if [ "$AC_ONLINE" != "$LAST_STATE" ]; then
        if [ "$AC_ONLINE" = "1" ]; then
            # Plugged in: start live wallpaper
            if ! pgrep -f 'xwinwrap.*black-hole' > /dev/null; then
                xwinwrap -fs -ni -fdt -un -b -nf -ov -- mpv --wid=%WID --no-audio --loop --no-osc --no-osd-bar --panscan=1.0 --hwdec=auto --gpu-context=x11egl --video-sync=display-resample --interpolation --tscale=mitchell /home/morris/Wallpapers/black-hole-in-nebula-2-optimized.mp4 &
            fi
        else
            # On battery: kill live wallpaper, static image is already underneath
            pkill -f 'xwinwrap.*black-hole'
        fi
        LAST_STATE="$AC_ONLINE"
    fi

    sleep 5
done
