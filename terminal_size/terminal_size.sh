#!/bin/bash
# Fit the front Apple Terminal window to its screen at a selected aspect ratio.
# Compatible with macOS Bash 3.2. No additional packages are required.

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
            input_number=$value
            return 0
        fi
        printf 'Enter a whole number from %s to %s, without leading zeros.\n' "$minimum" "$maximum" >&2
    done
}

# Zero means automatic maximum size. A positive value is an optional width cap.
width_limit=0

printf 'Terminal window aspect ratio\n'
printf 'Each ratio fills the usable area of the screen containing the window.\n'
printf 'The window is centered; the menu bar and Dock are accounted for.\n'
printf 'Sizes use logical points and include the title bar. Exit full screen first.\n'

while :; do
    if (( width_limit == 0 )); then
        printf '\nSizing: maximum available screen area\n'
    else
        printf '\nSizing: fit screen, with a maximum width of %s logical points\n' "$width_limit"
    fi
    cat <<'MENU'

  1) 16:9    Widescreen
  2) 16:10   Workspace
  3)  4:3    Classic
  4)  3:2    Photo
  5) 21:9    Ultrawide
  6)  1:1    Square
  7)  9:16   Portrait
  8) Custom aspect ratio
  a) Automatic maximum size (default)
  w) Set an optional maximum width
  q) Quit

MENU
    printf 'Choose [1-8/a/w/q]: ' >&2
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
        a|A)
            width_limit=0
            continue
            ;;
        w|W)
            if (( width_limit == 0 )); then
                read_number 'Maximum width in logical points' 320 16384 || break
            else
                read_number 'Maximum width in logical points' 320 16384 "$width_limit" || break
            fi
            width_limit=$input_number
            continue
            ;;
        q|Q) break ;;
        *) printf 'Please choose 1-8, a, w, or q.\n'; continue ;;
    esac

    # JavaScript for Automation provides AppKit display information through
    # macOS's built-in osascript. The script remains one standalone Bash file.
    if resize_details=$(osascript -l JavaScript - "$ratio_width" "$ratio_height" "$width_limit" <<'JAVASCRIPT'
function desktopRect(cocoaRect, primaryTop) {
    return {
        x: Number(cocoaRect.origin.x),
        y: primaryTop - Number(cocoaRect.origin.y) - Number(cocoaRect.size.height),
        width: Number(cocoaRect.size.width),
        height: Number(cocoaRect.size.height)
    };
}

function integerRect(rect) {
    var x = Math.ceil(rect.x);
    var y = Math.ceil(rect.y);
    return {
        x: x, y: y,
        width: Math.floor(rect.x + rect.width) - x,
        height: Math.floor(rect.y + rect.height) - y
    };
}

function overlapArea(a, b) {
    return Math.max(0, Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)) *
        Math.max(0, Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y));
}

function selectScreen(screens, windowBounds) {
    var best = 0;
    var bestArea = -1;
    var bestDistance = Infinity;
    for (var i = 0; i < screens.length; i++) {
        var frame = screens[i].frame;
        var area = overlapArea(frame, windowBounds);
        var dx = frame.x + frame.width / 2 - windowBounds.x - windowBounds.width / 2;
        var dy = frame.y + frame.height / 2 - windowBounds.y - windowBounds.height / 2;
        var distance = dx * dx + dy * dy;
        if (area > bestArea || (area === bestArea && distance < bestDistance)) {
            best = i;
            bestArea = area;
            bestDistance = distance;
        }
    }
    return best;
}

function centeredRect(area, width, height) {
    return {
        x: area.x + Math.floor((area.width - width) / 2),
        y: area.y + Math.floor((area.height - height) / 2),
        width: width, height: height
    };
}

function scaledRect(area, ratioWidth, ratioHeight, scale) {
    var width = Math.floor(ratioWidth * scale + 1e-7);
    var height = Math.floor(ratioHeight * scale + 1e-7);
    if (width < 320 || height < 200) {
        throw new Error('This ratio cannot fit at a usable size. Choose another ratio, raise the width limit, or use a larger screen.');
    }
    return centeredRect(area, width, height);
}

function fittedRect(area, ratioWidth, ratioHeight, widthLimit) {
    var maximumWidth = widthLimit > 0 ? Math.min(area.width, widthLimit) : area.width;
    var scale = Math.min(maximumWidth / ratioWidth, area.height / ratioHeight);
    return scaledRect(area, ratioWidth, ratioHeight, scale);
}

function readBounds(terminalWindow) {
    var rect = terminalWindow.bounds();
    var result = {x: Number(rect.x), y: Number(rect.y), width: Number(rect.width), height: Number(rect.height)};
    if (!isFinite(result.x) || !isFinite(result.y) || !isFinite(result.width) ||
            !isFinite(result.height) || result.width <= 0 || result.height <= 0) {
        throw new Error('Terminal returned invalid window bounds.');
    }
    return result;
}

function isInside(rect, area) {
    return rect.x >= area.x && rect.y >= area.y &&
        rect.x + rect.width <= area.x + area.width &&
        rect.y + rect.height <= area.y + area.height;
}

function run(argv) {
    var ratioWidth = Number(argv[0]);
    var ratioHeight = Number(argv[1]);
    var widthLimit = Number(argv[2]);
    if (!isFinite(ratioWidth) || !isFinite(ratioHeight) || !isFinite(widthLimit) ||
            ratioWidth < 1 || ratioHeight < 1 || ratioWidth > 16384 || ratioHeight > 16384 ||
            widthLimit < 0 || widthLimit > 16384 || (widthLimit > 0 && widthLimit < 320) ||
            Math.floor(ratioWidth) !== ratioWidth || Math.floor(ratioHeight) !== ratioHeight ||
            Math.floor(widthLimit) !== widthLimit) {
        throw new Error('Invalid ratio or width limit.');
    }

    var terminal = Application('Terminal');
    if (!terminal.running()) {
        throw new Error('Open an Apple Terminal window first.');
    }
    var windowList = terminal.windows();
    if (windowList.length === 0) {
        throw new Error('Open an Apple Terminal window first.');
    }
    var terminalWindow = terminal.windows.byId(windowList[0].id());
    var originalBounds = readBounds(terminalWindow);

    ObjC.import('AppKit');
    var cocoaApplication = $.NSApplication.sharedApplication;
    var nativeScreens = $.NSScreen.screens;
    var screenCount = Number(nativeScreens.count);
    if (!isFinite(screenCount) || screenCount < 1) {
        throw new Error('macOS did not report an available screen.');
    }
    var primaryFrame = nativeScreens.objectAtIndex(0).frame;
    var primaryTop = Number(primaryFrame.origin.y) + Number(primaryFrame.size.height);
    var screens = [];
    for (var i = 0; i < screenCount; i++) {
        var screen = nativeScreens.objectAtIndex(i);
        screens.push({
            frame: desktopRect(screen.frame, primaryTop),
            visible: integerRect(desktopRect(screen.visibleFrame, primaryTop))
        });
    }

    var selected = selectScreen(screens, originalBounds);
    var available = screens[selected].visible;
    var requested = fittedRect(available, ratioWidth, ratioHeight, widthLimit);
    var candidate = requested;
    var maximumWidth = widthLimit > 0 ? Math.min(available.width, widthLimit) : available.width;
    var actual;
    var fits = false;

    try {
        // Terminal can snap upward to its text grid. Reduce the target only
        // when that would exceed the usable screen area or optional width cap.
        for (var attempt = 0; attempt < 8; attempt++) {
            terminalWindow.bounds = candidate;
            actual = readBounds(terminalWindow);
            var excessWidth = Math.max(0, actual.width - maximumWidth);
            var excessHeight = Math.max(0, actual.height - available.height);
            if (excessWidth === 0 && excessHeight === 0) {
                fits = true;
                break;
            }
            var nextWidth = candidate.width - (excessWidth > 0 ? excessWidth + 1 : 0);
            var nextHeight = candidate.height - (excessHeight > 0 ? excessHeight + 1 : 0);
            candidate = scaledRect(available, ratioWidth, ratioHeight,
                Math.min(nextWidth / ratioWidth, nextHeight / ratioHeight));
        }
        if (!fits) {
            throw new Error('Terminal could not fit this ratio within the available screen area.');
        }

        // Recenter using the size Terminal actually accepted.
        terminalWindow.bounds = centeredRect(available, actual.width, actual.height);
        actual = readBounds(terminalWindow);
        if (!isInside(actual, available) || actual.width > maximumWidth) {
            throw new Error('Terminal could not keep the window inside the available screen area.');
        }
    } catch (error) {
        try { terminalWindow.bounds = originalBounds; } catch (restoreError) {}
        throw error;
    }

    var output = [
        'Display: ' + (selected + 1),
        'Available: ' + available.width + ' x ' + available.height + ' logical points.',
        'Requested: ' + requested.width + ' x ' + requested.height,
        'Window now: ' + actual.width + ' x ' + actual.height + ' logical points.'
    ];
    if (actual.width !== requested.width || actual.height !== requested.height) {
        output.push('Note: Terminal adjusted the requested size to its text grid.');
    }
    return output.join('\n');
}
JAVASCRIPT
    ); then
        printf '\nSelected ratio: %s:%s\n%s\n' "$ratio_width" "$ratio_height" "$resize_details"
    else
        printf '\nCould not resize Terminal. Check the error above, then choose another option.\n' >&2
    fi
done

exit 0
