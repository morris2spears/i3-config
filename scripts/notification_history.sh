#!/usr/bin/env bash
# notification history viewer: dunstctl history -> rofi
set -uo pipefail

# his global rofi theme is a 480px wide sliver at font 12, unreadable here, so
# both views are fully restyled below via -theme-str.
# nothing outside this script is touched.
# carbon runs 2560x1440, not the laptop's 3840x2160, so these are scaled down
# from the laptop values by the same ratios his carbon dunstrc already uses.
LIST_FONT="Cantarell 15"
BODY_FONT="Cantarell 17"
LIST_W=1800
BODY_W=1580

palette='
* {
    bg0:  #0B0E14;
    bg1:  #161B26;
    fg0:  #E8E4F2;
    dim:  #9A93B0;
    acc:  #9B7EC7;
    background-color: transparent;
    text-color: @fg0;
    margin: 0; padding: 0; spacing: 0;
}
window {
    location: center;
    background-color: @bg0;
    border: 3px;
    border-color: @acc;
    border-radius: 18px;
    padding: 30px;
}
prompt, entry, element-text, textbox { vertical-align: 0.5; }
scrollbar { handle-color: @acc; handle-width: 10px; }
'

list_theme="$palette"'
* { font: "'"$LIST_FONT"'"; }
window { width: '"$LIST_W"'px; }
mainbox { children: [ inputbar, message, listview ]; spacing: 18px; }
inputbar {
    padding: 16px 20px; spacing: 14px;
    background-color: @bg1; border-radius: 12px;
}
prompt { text-color: @acc; }
entry { text-color: @fg0; placeholder: "type to filter"; placeholder-color: @dim; }
message { padding: 0 4px; }
textbox { text-color: @dim; }
listview { lines: 12; spacing: 4px; scrollbar: true; fixed-height: false; }
element { padding: 10px 18px; spacing: 14px; border-radius: 10px; }
element normal normal { text-color: @fg0; }
element selected normal { background-color: @acc; text-color: @bg0; }
element-text { text-color: inherit; horizontal-align: 0.0; }
element-icon { size: 1.4em; vertical-align: 0.5; background-color: transparent; }
'

# reading pane: a plain text view, no search bar and no menu rows. pango wraps
# the body itself at the window width, so nothing is hard wrapped here.
body_theme="$palette"'
* { font: "'"$BODY_FONT"'"; }
window { width: '"$BODY_W"'px; padding: 34px; }
error-message { padding: 0px; background-color: transparent; expand: true; }
error-message textbox { expand: true; vertical-align: 0.0; }
textbox {
    text-color: @fg0; background-color: transparent;
    expand: true; vertical-align: 0.0;
}
'

# dunst timestamps are CLOCK_MONOTONIC microseconds, so we need the wall-clock
# offset of that clock to render real times
mono_base() {
    python3 -c 'import time; print(time.time()-time.clock_gettime(time.CLOCK_MONOTONIC))' 2>/dev/null \
        || awk -v n="$(date +%s)" '{printf "%f\n", n-$1}' /proc/uptime
}

pango_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

hist=$(dunstctl history 2>/dev/null) || hist=""
if [ -z "$hist" ]; then
    rofi -e "dunst is not running" -theme-str "$body_theme"
    exit 1
fi

count=$(jq '.data[0] | length' <<<"$hist" 2>/dev/null)
if [ "${count:-0}" -eq 0 ]; then
    rofi -e "no notifications in history" -theme-str "$body_theme"
    exit 0
fi

base=$(mono_base)

# clean drops pango/html tags and unescapes entities, flat also folds newlines
read -r -d '' jq_defs <<'JQ'
def clean:
    (. // "")
    | gsub("<[^>]*>"; "")
    | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"")
    | gsub("&#39;"; "'") | gsub("&apos;"; "'") | gsub("&amp;"; "&")
    | gsub("^\\s+|\\s+$"; "");
def flat: clean | gsub("[\n\r\t]+"; " ");
# bluebubbles bodies are rolling digests of the last few messages in a chat,
# newest last, so the row shows the final line rather than the whole blob
def lastline:
    clean | split("\n") | map(select(test("\\S")))
    | (.[-1] // "") | gsub("[\r\t]+"; " ") | gsub("^\\s+|\\s+$"; "");
def entries:
    [ .data[0][]
      | { t:    ($base + (.timestamp.data / 1000000)),
          app:  (.appname.data | flat),
          sum:  (.summary.data | flat),
          icon: (.icon_path.data // "" | flat),
          snip: (.body.data | lastline),
          body: (.body.data | clean) } ]
    | sort_by(.t) | reverse;
JQ

jqh() { jq -r --argjson base "$base" --argjson now "$(date +%s)" "$jq_defs $1" <<<"$hist"; }

# rofi takes a per row icon as "text<NUL>icon<US>/path". a NUL cannot survive a
# shell variable, so rows are streamed straight into rofi instead.
list_rows() {
    jqh '
        entries[]
        | (.t | strflocaltime("%-I:%M") + (strflocaltime("%p") | ascii_downcase)) as $clock
        | (if ($now - .t) < 43200 then $clock
           else (.t | strflocaltime("%b%d ")) + $clock end) as $time
        | (if .snip == "" then "" else "   " + .snip end) as $s
        | "\($time)   \(.sum)   [\(.app)]\($s)\t\(.icon)"' \
    | while IFS=$'\t' read -r text icon; do
        if [ -n "$icon" ] && [ -f "$icon" ]; then
            printf '%s\000icon\x1f%s\n' "$text" "$icon"
        else
            printf '%s\n' "$text"
        fi
    done
}

while true; do
    idx=$(list_rows | rofi -dmenu -i -no-custom -format i -show-icons \
        -p "notifications" -theme-str "$list_theme" \
        -mesg "$count in history - Enter reads the full message, Esc closes") || exit 0
    [ -z "$idx" ] && exit 0

    meta=$(jqh "entries[$idx] | \"\(.t)\t\(.app)\t\(.sum)\"")
    body=$(jqh "entries[$idx] | .body")

    ts=${meta%%$'\t'*}; rest=${meta#*$'\t'}
    app=${rest%%$'\t'*}; sum=${rest#*$'\t'}

    when="$(date -d "@${ts%.*}" '+%a %d %b, %-I:%M')$(date -d "@${ts%.*}" '+%p' | tr 'A-Z' 'a-z')"
    [ -z "$body" ] && body="(no body)"

    # shrink the font for very long texts so they still fit without scrolling
    len=${#body}
    font="$BODY_FONT"
    [ "$len" -gt 900 ] && font="Cantarell 14"
    [ "$len" -gt 2200 ] && font="Cantarell 11"

    pane="<b>$(printf '%s' "$sum" | pango_escape)</b>
<span size='small' foreground='#9A93B0'>$(printf '%s' "$app" | pango_escape) - $when</span>

$(printf '%s' "$body" | pango_escape)"

    rofi -e "$pane" -markup -theme-str "$body_theme" \
        -theme-str '* { font: "'"$font"'"; }' >/dev/null
done
