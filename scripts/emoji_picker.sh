#!/usr/bin/env bash
# System-wide emoji picker: rofi opens straight into its filter line, so you can
# type to search immediately, and the chosen emoji is typed into whatever window
# was focused before the picker opened.
#
# Why this is not a BlueBubbles-specific shortcut: the BlueBubbles Linux client
# (v2.0.0+89) exposes no configurable keybindings at all -- its prefs contain no
# shortcut/hotkey keys -- so there is nothing in the app to bind. This works in
# BlueBubbles and in every other window (WhatsApp, Discord, browser, terminal).
#
# SEARCH RANKING
# --------------
# Emoji data still comes from python's unicodedata (nothing to install), but raw
# Unicode names are formal and useless for mood search: no emoji is literally
# named "heart" (the red one is HEAVY BLACK HEART), and "sad", "happy", "love"
# and "haha" barely appear in Unicode names at all. CLDR annotations would be
# the right source, but no CLDR/emoji-annotation data exists on these machines
# -- checked /usr/share/unicode/{cldr,emoji}, /usr/share/ibus/dicts,
# gnome-characters, rofimoji and the python `emoji` package, all absent. So a
# curated keyword layer is baked in below.
#
# rofi's dmenu mode filters but does NOT reorder: matching lines are displayed
# in the order they appear in the input. That is the entire ranking mechanism
# here, which makes results fully deterministic and testable. The cache is
# written in deliberate priority order:
#
#   1. the curated block -- mood/concept groups and everyday emoji, each line
#      carrying its search keywords, in hand-picked order
#   2. everything else from unicodedata, sorted by name length then alphabetically
#      so short plain names outrank long qualified ones
#
# Net effect: "heart" yields the real hearts first and only reaches oddities
# like "heart with tip on the left" far down the list, and "sad" / "happy" /
# "love" / "haha" resolve to the obvious groups.
#
# HEARTS ARE NOT "LOVE"
# ---------------------
# Deliberate exception: anything that mentions "heart" must never come up for
# the query "love". Hearts are still found by typing "heart"; "love" is left
# for love letter / love hotel / kisses / rose. rofi matches plain substrings
# over the whole cache line, so this is enforced at cache-build time by
# scrubbing every "love"-bearing word out of heart lines (see drop_love below).
#
# The cache filename is version-stamped; bump CACHE_VERSION to force a rebuild.
#
# RECENTLY USED
# -------------
# Whatever you reached for last is overwhelmingly what you reach for next, so
# recently picked emoji are moved to the very top of the list. Because rofi
# only filters and never reorders, PREPENDING THE LINES IS THE ENTIRE RANKING
# MECHANISM: a recent emoji is first on the unfiltered list, and it is also
# first among the survivors of any query it happens to match. Nothing else has
# to know about recency, and the curated block still outranks the unicodedata
# tail for everything below the recents.
#
# The recents file stores BARE EMOJI CHARACTERS, one per line, most recent
# first -- deliberately not the full display line. Display lines are owned by
# CACHE_VERSION: bumping it rewrites names and keywords, and a store of stale
# display lines would then show text that no longer matches the cache (or worse,
# duplicate an entry whose wording changed). A bare character is the stable
# identity; it is re-resolved against the current cache on every launch, and a
# character that no longer appears in the cache is simply skipped.

set -uo pipefail

CACHE_VERSION=5
CACHE="$HOME/.cache/emoji-list.v${CACHE_VERSION}.txt"

# Recents are versioned independently of the cache: the format here is "one
# bare emoji per line", and only a change to THAT would need a bump.
RECENTS="$HOME/.cache/emoji-recents.v1.txt"
RECENTS_MAX=24

if [ ! -s "$CACHE" ]; then
    mkdir -p "$(dirname "$CACHE")"
    python3 - "$CACHE" <<'PY'
import sys, unicodedata

# ---------------------------------------------------------------------------
# Curated block: (emoji, display name, extra search keywords).
# Order matters -- it is literally the result order for any matching query.
# An emoji listed twice keeps its first position and merges keywords.
# ---------------------------------------------------------------------------
CURATED = [
    # --- hearts -----------------------------------------------------------
    ("❤️",  "red heart",          "heart love red"),
    ("\U0001F9E1",    "orange heart",       "heart love orange"),
    ("\U0001F49B",    "yellow heart",       "heart love yellow"),
    ("\U0001F49A",    "green heart",        "heart love green"),
    ("\U0001F499",    "blue heart",         "heart love blue"),
    ("\U0001F49C",    "purple heart",       "heart love purple"),
    ("\U0001F5A4",    "black heart",        "heart love black"),
    ("\U0001F90D",    "white heart",        "heart love white"),
    ("\U0001F90E",    "brown heart",        "heart love brown"),
    ("\U0001F495",    "two hearts",         "heart love"),
    ("\U0001F496",    "sparkling heart",    "heart love"),
    ("\U0001F497",    "growing heart",      "heart love"),
    ("\U0001F493",    "beating heart",      "heart love"),
    ("\U0001F49E",    "revolving hearts",   "heart love"),
    ("\U0001F498",    "heart with arrow",   "heart love cupid"),
    ("\U0001F49D",    "heart with ribbon",  "heart love gift"),
    ("❣️",  "heart exclamation",  "heart love"),
    ("\U0001F494",    "broken heart",       "heart sad breakup hurt"),
    ("\U0001F49F",    "heart decoration",   "heart love"),
    ("♥️",  "heart suit",         "heart love cards"),

    # --- love -------------------------------------------------------------
    ("\U0001F60D",    "smiling face with heart eyes",   "love heart happy adore"),
    ("\U0001F970",    "smiling face with hearts",       "love heart happy adore"),
    ("\U0001F618",    "face blowing a kiss",            "love kiss heart"),
    ("\U0001F617",    "kissing face",                   "love kiss"),
    ("\U0001F619",    "kissing face with smiling eyes", "love kiss"),
    ("\U0001F61A",    "kissing face with closed eyes",  "love kiss"),
    ("\U0001F63B",    "smiling cat with heart eyes",    "love heart cat"),
    ("\U0001F48F",    "kiss",                           "love kiss couple"),
    ("\U0001F491",    "couple with heart",              "love heart couple"),
    ("\U0001F339",    "rose",                           "love flower romance"),

    # --- happy ------------------------------------------------------------
    ("\U0001F600", "grinning face",                    "happy smile grin"),
    ("\U0001F603", "grinning face with big eyes",      "happy smile grin"),
    ("\U0001F604", "grinning face with smiling eyes",  "happy smile grin"),
    ("\U0001F601", "beaming face with smiling eyes",   "happy smile grin"),
    ("\U0001F642", "slightly smiling face",            "happy smile"),
    ("\U0001F60A", "smiling face with smiling eyes",   "happy smile"),
    ("☺️", "smiling face",                   "happy smile"),
    ("\U0001F607", "smiling face with halo",           "happy smile angel innocent"),
    ("\U0001F60C", "relieved face",                    "happy smile calm content"),
    ("\U0001F917", "hugging face",                     "happy hug smile"),
    ("\U0001F973", "partying face",                    "happy party celebrate"),
    ("\U0001F643", "upside down face",                 "happy smile silly"),
    ("\U0001F63A", "grinning cat",                     "happy smile cat"),
    ("\U0001F638", "grinning cat with smiling eyes",   "happy smile cat"),

    # --- laughing / haha --------------------------------------------------
    ("\U0001F602", "face with tears of joy",           "haha laugh lol funny joke"),
    ("\U0001F923", "rolling on the floor laughing",    "haha laugh lol rofl funny joke"),
    ("\U0001F606", "grinning squinting face",          "haha laugh lol funny"),
    ("\U0001F605", "grinning face with sweat",         "haha laugh nervous"),
    ("\U0001F61B", "face with tongue",                 "haha laugh tongue silly"),
    ("\U0001F92A", "zany face",                        "haha laugh crazy silly"),
    ("\U0001F61C", "winking face with tongue",         "haha silly joke tongue"),
    ("\U0001F61D", "squinting face with tongue",       "haha laugh tongue silly"),
    ("\U0001F60B", "face savoring food",               "yum tongue delicious tasty"),

    # --- sad --------------------------------------------------------------
    ("\U0001F622", "crying face",                      "sad cry tears upset"),
    ("\U0001F62D", "loudly crying face",               "sad cry sobbing tears bawling"),
    ("\U0001F61E", "disappointed face",                "sad upset unhappy"),
    ("\U0001F614", "pensive face",                     "sad upset thoughtful"),
    ("\U0001F641", "slightly frowning face",           "sad frown unhappy"),
    ("☹️", "frowning face",                  "sad frown unhappy"),
    ("\U0001F63F", "crying cat",                       "sad cry cat"),
    ("\U0001F97A", "pleading face",                    "sad puppy eyes beg please"),
    ("\U0001F625", "sad but relieved face",            "sad disappointed"),
    ("\U0001F613", "downcast face with sweat",         "sad tired"),
    ("\U0001F629", "weary face",                       "sad tired distraught"),
    ("\U0001F62B", "tired face",                       "sad tired exhausted"),
    ("\U0001F616", "confounded face",                  "sad frustrated"),
    ("\U0001F623", "persevering face",                 "sad struggling"),
    ("\U0001F62A", "sleepy face",                      "sad sleepy tired"),
    ("\U0001F972", "smiling face with tear",           "sad tear touched"),

    # --- angry ------------------------------------------------------------
    ("\U0001F620", "angry face",                       "angry mad annoyed"),
    ("\U0001F621", "enraged face",                     "angry mad furious rage"),
    ("\U0001F92C", "face with symbols on mouth",       "angry mad swearing cursing"),
    ("\U0001F624", "face with steam from nose",        "angry mad triumph"),
    ("\U0001F47F", "angry face with horns",            "angry devil imp evil"),
    ("\U0001F4A2", "anger symbol",                     "angry mad rage"),
    ("\U0001F63E", "pouting cat",                      "angry mad cat"),

    # --- hands / reactions ------------------------------------------------
    ("\U0001F44D", "thumbs up",                        "thumbs up yes like approve ok"),
    ("\U0001F44E", "thumbs down",                      "thumbs down no dislike"),
    ("\U0001F44C", "ok hand",                          "ok perfect nice hand"),
    ("\U0001F64F", "folded hands",                     "pray thanks please hands"),
    ("\U0001F44F", "clapping hands",                   "clap applause hands bravo"),
    ("\U0001F64C", "raising hands",                    "hands celebrate praise hooray"),
    ("\U0001F4AA", "flexed biceps",                    "muscle strong arm gym"),
    ("\U0001F91D", "handshake",                        "deal agree hands"),
    ("✌️", "victory hand",                   "peace hand fingers"),
    ("\U0001F91E", "crossed fingers",                  "luck hope hand"),
    ("\U0001F919", "call me hand",                     "cool shaka hand"),
    ("\U0001F44B", "waving hand",                      "wave hello hi bye hand"),

    # --- fire / hot -------------------------------------------------------
    ("\U0001F525", "fire",                             "fire lit hot flame burn"),
    ("\U0001F4AF", "hundred points",                   "fire 100 perfect score"),
    ("✨",     "sparkles",                         "fire shiny stars magic"),
    ("⭐",     "star",                             "star favourite"),
    ("\U0001F975", "hot face",                         "fire hot heat sweating"),
    ("\U0001F976", "cold face",                        "cold freezing"),

    # --- cool / think / eyes ---------------------------------------------
    ("\U0001F60E", "smiling face with sunglasses",     "cool sunglasses awesome"),
    ("\U0001F914", "thinking face",                    "think hmm consider"),
    ("\U0001F9D0", "face with monocle",                "think inspect suspicious"),
    ("\U0001F928", "face with raised eyebrow",         "think skeptical suspicious"),
    ("\U0001F4AD", "thought balloon",                  "think thought bubble"),
    ("\U0001F644", "face with rolling eyes",           "eyes annoyed whatever"),
    ("\U0001F440", "eyes",                             "eyes look watching"),
    ("\U0001F441️", "eye",                        "eyes look"),
    ("\U0001F633", "flushed face",                     "eyes embarrassed blush shocked"),
    ("\U0001F631", "face screaming in fear",           "scared shock scream"),
    ("\U0001F92F", "exploding head",                   "shock mind blown"),
    ("\U0001F610", "neutral face",                     "meh blank"),
    ("\U0001F611", "expressionless face",              "meh blank"),
    ("\U0001F636", "face without mouth",               "meh blank speechless"),
    ("\U0001F634", "sleeping face",                    "sleep tired zzz"),
    ("\U0001F92E", "face vomiting",                    "sick gross vomit"),
    ("\U0001F922", "nauseated face",                   "sick gross"),
    ("\U0001F62C", "grimacing face",                   "awkward yikes"),
    ("\U0001F60F", "smirking face",                    "smirk smug"),
    ("\U0001F609", "winking face",                     "wink joke"),

    # --- skull / party / staples -----------------------------------------
    ("\U0001F480", "skull",                            "skull dead dying"),
    ("☠️", "skull and crossbones",           "skull dead poison"),
    ("\U0001F921", "clown face",                       "clown joke"),
    ("\U0001F389", "party popper",                     "party celebrate congrats hooray"),
    ("\U0001F38A", "confetti ball",                    "party celebrate congrats"),
    ("\U0001F388", "balloon",                          "party celebrate birthday"),
    ("\U0001F381", "wrapped gift",                     "party gift present birthday"),
    ("\U0001F382", "birthday cake",                    "party birthday cake"),
    ("\U0001F37E", "bottle with popping cork",         "party champagne celebrate"),
    ("\U0001F942", "clinking glasses",                 "party cheers celebrate drink"),
    ("✅",     "check mark button",                "ok yes done check tick"),
    ("❌",     "cross mark",                       "no wrong cancel x"),
    ("⚠️", "warning",                        "warning caution alert"),
    ("❓",     "question mark",                    "question ask"),
    ("❗",     "exclamation mark",                 "exclamation alert"),
    ("\U0001F30A", "water wave",                       "wave water sea ocean"),
]

seen, order = {}, []
for ch, name, kw in CURATED:
    if ch in seen:
        cur_name, cur_kw = seen[ch]
        extra = [w for w in kw.split() if w not in cur_kw.split()]
        if extra:
            seen[ch] = (cur_name, cur_kw + " " + " ".join(extra))
        continue
    seen[ch] = (name, kw)
    order.append(ch)

lines = [f"{ch} {seen[ch][0]} · {seen[ch][1]}" for ch in order]

# ---------------------------------------------------------------------------
# Long tail straight from unicodedata, minus anything already curated.
# Sorted by name length then alphabetically, so plain short names come first.
# ---------------------------------------------------------------------------
ranges = [
    (0x1F300, 0x1F9FF),   # symbols, pictographs, emoticons, supplemental
    (0x1FA70, 0x1FAF8),   # extended-A (hearts, hands, misc objects)
    (0x2600,  0x27BF),    # misc symbols + dingbats
    (0x2190,  0x21FF),    # arrows
    (0x2B00,  0x2BFF),    # misc symbols and arrows
]
curated_bare = {c.replace("️", "") for c in order}
tail, tail_seen = [], set()
for lo, hi in ranges:
    for cp in range(lo, hi + 1):
        ch = chr(cp)
        if ch in tail_seen or ch in curated_bare:
            continue
        try:
            name = unicodedata.name(ch)
        except ValueError:
            continue
        tail_seen.add(ch)
        tail.append((ch, name.lower()))

tail.sort(key=lambda t: (len(t[1]), t[1]))
lines.extend(f"{ch} {name}" for ch, name in tail)

# ---------------------------------------------------------------------------
# "love" must not surface hearts.
# rofi -matching normal is a plain substring test over the whole line, so the
# only reliable way to keep a heart out of the "love" results is for its line
# to contain no "love" substring at all. Any word carrying "love" is therefore
# dropped from every line that mentions "heart" -- the curated keywords above
# stay readable, and the rule is stated once, here, for the curated block and
# the unicodedata tail alike.
#
# Hearts stay findable by typing "heart" (their name and keywords are intact).
# Non-heart emoji keep "love": love letter, love hotel, kiss faces, rose, and
# incidental matches like clover / gloves.
# ---------------------------------------------------------------------------
def drop_love(line):
    low = line.lower()
    # Only plain heart symbols get scrubbed. Faces, cats and couples that
    # mention "heart" in their name are exactly what "love" should find.
    if "heart" not in low or "face" in low or "cat" in low or "couple" in low:
        return line
    kept = [w for w in line.split(" ") if "love" not in w.lower()]
    return " ".join(kept).rstrip(" ·")

lines = [drop_love(line) for line in lines]

with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
fi

# Emit the rofi input: recents resolved against the cache, then the rest of the
# cache in its original priority order. One awk pass so the cache is read once
# and recents are matched on an exact field comparison -- an emoji is not a safe
# regex, and some of them genuinely contain metacharacters.
build_list() {
    awk -v recents="$RECENTS" '
        BEGIN {
            # Read the recents store first; a missing or empty file just leaves
            # the wanted[] set empty and the cache is emitted verbatim.
            while ((getline ch < recents) > 0) {
                if (ch == "" || (ch in wanted)) continue
                wanted[ch] = 1
                order[++nrecent] = ch
            }
            close(recents)
        }
        {
            # Field 1 is the emoji, which is exactly what the picker stores.
            if ($1 in wanted) {
                if (!($1 in line)) line[$1] = $0   # first hit wins, as in the cache
                next                               # and it is NOT re-emitted below
            }
            rest[++nrest] = $0
        }
        END {
            # Skip recents that no longer resolve (e.g. after a CACHE_VERSION bump
            # dropped an emoji) rather than printing a bare, unsearchable char.
            for (i = 1; i <= nrecent; i++)
                if (order[i] in line) print line[order[i]]
            for (i = 1; i <= nrest; i++) print rest[i]
        }
    ' "$CACHE"
}

# Move an emoji to the front of the recents store, deduped and capped. Written
# to a temp file and renamed, so a kill mid-write can never leave a half file.
record_recent() {
    local ch=$1 tmp
    [ -n "$ch" ] || return 0
    mkdir -p "$(dirname "$RECENTS")" 2>/dev/null
    tmp=$(mktemp "${RECENTS}.XXXXXX" 2>/dev/null) || return 0
    {
        printf '%s\n' "$ch"
        # Drop the previous occurrence so re-picking promotes instead of duplicating.
        [ -s "$RECENTS" ] && grep -vxF -e "$ch" -- "$RECENTS"
    } | grep -v '^[[:space:]]*$' | head -n "$RECENTS_MAX" > "$tmp"
    mv -f "$tmp" "$RECENTS" 2>/dev/null || rm -f "$tmp"
}

# Remember the window that was focused before rofi steals focus.
TARGET=$(xdotool getactivewindow 2>/dev/null)

CHOICE=$(build_list | rofi -dmenu -i -matching normal -no-custom -p "emoji") || exit 0
[ -n "${CHOICE:-}" ] || exit 0
EMOJI=${CHOICE%% *}

# Every successful pick counts, including one made from the recents section
# itself (where it just re-confirms position 1).
record_recent "$EMOJI"

# Clipboard copy as a fallback for anything that refuses synthetic typing.
printf '%s' "$EMOJI" | xclip -selection clipboard 2>/dev/null

if [ -n "${TARGET:-}" ]; then
    xdotool windowactivate --sync "$TARGET" 2>/dev/null
fi
xdotool type --clearmodifiers --delay 12 -- "$EMOJI"
