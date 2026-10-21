# terminal_size.sh

## Description

An interactive Bash script that makes the front Apple Terminal window as large as possible at a selected aspect ratio within its screen's usable area. Choose a preset or enter a custom ratio; the script fits and centers the window while accounting for the menu bar and Dock, and keeps the menu open for further changes.

---

## Usage

Open a Terminal window, exit full screen, and run the script from the directory containing it:

```bash
bash terminal_size.sh
```

Alternatively, make the script executable and run it directly:

```bash
chmod +x terminal_size.sh
./terminal_size.sh
```

Choose an option from the menu:

| Option | Aspect ratio | Name / action |
| --- | --- | --- |
| `1` | 16:9 | Widescreen |
| `2` | 16:10 | Workspace |
| `3` | 4:3 | Classic |
| `4` | 3:2 | Photo |
| `5` | 21:9 | Ultrawide |
| `6` | 1:1 | Square |
| `7` | 9:16 | Portrait |
| `8` | Custom | Enter the ratio's width and height components separately. |
| `a` | — | Use the maximum available screen area; this is the default. |
| `w` | — | Set an optional maximum width for subsequent resizes. |
| `q` | — | Quit. |

**Automatic maximum sizing is enabled at startup.** Selecting a ratio fits the largest rectangle of that ratio inside the usable screen area, centers the window, and returns to the menu. Both width and height are taken into account, including for square and portrait ratios.

With multiple displays, the script uses the screen containing the largest portion of the Terminal window. Move the window to another display and select a ratio again to fit that display.

To limit a **4:3 window to a maximum width of 800 points**:

1. Enter `w`.
2. Enter `800` at the width prompt.
3. Enter `3` to select 4:3. This targets 800 × 600 if that size fits; otherwise it scales down to fit the screen.

Enter `a`, then select a ratio, to remove the width limit and return to automatic maximum sizing. Changing modes or the width limit takes effect on the next ratio selection.

For a custom ratio such as **5:4**, select `8`, enter `5` for the ratio width, then enter `4` for the ratio height. These numbers define proportions; the available screen area and optional width limit determine the requested size.

When a width limit is already configured, press Enter at its prompt to keep it. Enter `q` at the menu or any numeric prompt to quit. Uppercase `A`, `W`, and `Q` also work, and end of input exits the script.

---

## Requirements

- macOS with an open Apple Terminal window outside full screen.
- Bash 3.2 or later.
- `osascript` with JavaScript for Automation and the AppKit framework, included with macOS, to read display information and resize Terminal.
- No additional packages or external modules.

---

## Input / Output

**Input:** Interactive menu choices and positive whole numbers without leading zeros.

| Setting | Accepted values |
| --- | --- |
| Sizing mode | Automatic maximum size by default; `w` sets a width limit and `a` removes it. |
| Optional maximum width | 320–16384 logical points. |
| Custom ratio width component | 1–16384. |
| Custom ratio height component | 1–16384. |
| Calculated window size | Must be at least 320 points wide and 200 points high for a resize to proceed. |

Invalid numeric entries are rejected and prompted again. Extremely narrow or wide ratios are rejected if their largest fitting rectangle would fall below the minimum usable size. Choose another ratio, increase or remove the width limit, or use a larger display.

**Output:** The front Terminal window is resized and centered within the selected display's usable area. The selected ratio, display number, available area, requested size, and actual resulting size are printed to the terminal. No output files are created.

Example output for a 4:3 request on a display with a usable area of 1920 × 1080 points, when Terminal accepts the requested dimensions:

```text
Selected ratio: 4:3
Display: 1
Available: 1920 x 1080 logical points.
Requested: 1440 x 1080
Window now: 1440 x 1080 logical points.
```

---

## Notes

- Dimensions use **macOS logical points**, which can differ from physical pixels on scaled or Retina displays.
- The aspect ratio applies to the **whole window, including its title bar**.
- Screen geometry is read again for every resize, so changes to the display arrangement, Dock, or menu bar are taken into account. The usable area comes from macOS's [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe).
- Displays positioned to the left of or above the primary display are supported. If the window is entirely off screen, the nearest display center is used as a fallback.
- Calculated dimensions are rounded down to whole points. Terminal may also snap the window to its character grid, so the final ratio can be approximate. Compare `Requested` and `Window now` after resizing.
- If grid snapping would exceed the usable area or width limit, the target size is reduced and the accepted size is centered again. If resizing cannot keep the window inside the usable area, the script attempts to restore its previous bounds and reports an error.
- Automatic sizing is restored at each launch. An optional width limit is retained only while the script runs.
- If resizing fails, ensure a Terminal window is open and outside full screen, then select a ratio again. The menu remains open after a resize error.

---

## License

This script is covered under the repository’s main [MIT License](../LICENSE).
