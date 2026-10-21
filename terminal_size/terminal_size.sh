#!/bin/bash
# Resize the front Apple Terminal window by aspect ratio.
# Pick ratios repeatedly; use w to change width and q to quit.
# Compatible with macOS Bash 3.2.

set -u

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'This script requires macOS and Apple Terminal.\n' >&2
    exit 1
fi

read_number() {
    local label minimum maximum default_value value
    label=$1
    minimum=$2
    maximum=$3
    default_value=${4:-}
    while :; do
        if [[ -n "$default_value" ]]; then
            printf '%s [%s] (q to quit): ' "$label" "$default_value" >&2
        else
            printf '%s (%s-%s, q to quit): ' "$label" "$minimum" "$maximum" >&2
        fi
        if ! IFS= read -r value; then
            printf '\n' >&2
            return 1
        fi
        case "$value" in q|Q) return 1 ;; esac
        value=${value:-$default_value}
        if [[ "$value" =~ ^[1-9][0-9]{0,4}$ ]] && (( value >= minimum && value <= maximum )); then
            # Read directly in the main shell so prompts remain visible.
            # A shared result avoids capturing interactive reads in $(...).
            input_number=$value
            return 0
        fi
        printf 'Enter a whole number from %s to %s, without leading zeros.\n' "$minimum" "$maximum" >&2
    done
}

window_width=1024

printf 'Terminal window aspect ratio\n'
printf 'Sizes use macOS logical points. Exit full screen before continuing.\n'
printf 'Pick a ratio to resize immediately, then pick another or q to quit.\n'
printf 'Use w to change the width; height is calculated automatically.\n'
printf 'The ratio applies to the whole window, including its title bar.\n'
printf 'Large sizes may be limited by your screen or the terminal text grid.\n'

while :; do
    printf '\nWindow width: %s logical points\n' "$window_width"
    cat <<'MENU'

  1) 16:9    Widescreen
  2) 16:10   Workspace
  3)  4:3    Classic
  4)  3:2    Photo
  5) 21:9    Ultrawide
  6)  1:1    Square
  7)  9:16   Portrait
  8) Custom aspect ratio
  w) Change width for the next resize
  q) Quit

MENU
    printf 'Choose [1-8/w/q]: ' >&2
    if ! IFS= read -r choice; then
        printf '\n'
        break
    fi

    case "$choice" in
        1) ratio_width=16; ratio_height=9 ;;
        2) ratio_width=16; ratio_height=10 ;;
        3) ratio_width=4;  ratio_height=3 ;;
        4) ratio_width=3;  ratio_height=2 ;;
        5) ratio_width=21; ratio_height=9 ;;
        6) ratio_width=1;  ratio_height=1 ;;
        7) ratio_width=9;  ratio_height=16 ;;
        8)
            printf 'For a ratio such as 4:3, enter 4 and then 3.\n'
            read_number 'Ratio width' 1 16384 || break
            ratio_width=$input_number
            read_number 'Ratio height' 1 16384 || break
            ratio_height=$input_number
            ;;
        w|W)
            read_number 'Window width in logical points' 320 16384 "$window_width" || break
            window_width=$input_number
            continue
            ;;
        q|Q) break ;;
        *) printf 'Please choose 1-8, w, or q.\n'; continue ;;
    esac

    # Round to the nearest whole point; arbitrary widths may approximate the ratio.
    window_height=$(( (window_width * ratio_height + ratio_width / 2) / ratio_width ))
    if (( window_height < 200 || window_height > 16384 )); then
        printf '\nThat ratio at width %s gives height %s.\n' "$window_width" "$window_height" >&2
        printf 'Height must be 200-16384 points. Use w to change the width, or choose another ratio.\n' >&2
        continue
    fi

    # Pass dimensions as arguments, rather than inserting user input into code.
    # Bounds are {left, top, right, bottom}; use the original 50-point offset.
    if actual_size=$(osascript - "$window_width" "$window_height" <<'APPLESCRIPT'
on run argv
    set targetWidth to (item 1 of argv) as integer
    set targetHeight to (item 2 of argv) as integer
    tell application "Terminal"
        if (count of windows) is 0 then error "Open a Terminal window first."
        set bounds of front window to {50, 50, (50 + targetWidth), (50 + targetHeight)}
        set actualBounds to bounds of front window
    end tell
    set actualWidth to (item 3 of actualBounds) - (item 1 of actualBounds)
    set actualHeight to (item 4 of actualBounds) - (item 2 of actualBounds)
    return (actualWidth as text) & " x " & (actualHeight as text)
end run
APPLESCRIPT
    ); then
        printf '\nSelected ratio: %s:%s\nRequested: %s x %s\nWindow now: %s logical points.\n' "$ratio_width" "$ratio_height" "$window_width" "$window_height" "$actual_size"
    else
        printf '\nCould not resize Terminal. Open a Terminal window, exit full screen, and try again.\n' >&2
    fi
done

exit 0
