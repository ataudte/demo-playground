# terminal_size.sh

## Description

An interactive Bash script that resizes the front Apple Terminal window to a selected aspect ratio. Choose a preset or enter a custom ratio; the script calculates the height from the configured width and keeps the menu open for further changes.

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
| `w` | — | Change the width used for the next resize. |
| `q` | — | Quit. |

The initial width is **1024 logical points**. Selecting a ratio resizes the window immediately and returns to the menu.

To request a **4:3 window at 800 × 600**:

1. Enter `w`.
2. Enter `800` at the width prompt.
3. Enter `3` to select 4:3.

For a custom ratio such as **5:4**, select `8`, enter `5` for the ratio width, then enter `4` for the ratio height. These numbers define proportions; the configured window width determines the requested size.

Press Enter at the window-width prompt to keep its current value. Enter `q` at the menu or any numeric prompt to quit. Uppercase `W` and `Q` also work, and end of input exits the script.

---

## Requirements

- macOS with an open Apple Terminal window outside full screen.
- Bash 3.2 or later.
- `osascript`, included with macOS, to run the AppleScript resize command.
- No additional packages or external modules.

---

## Input / Output

**Input:** Interactive menu choices and positive whole numbers without leading zeros.

| Setting | Accepted values |
| --- | --- |
| Window width | 320–16384 logical points; defaults to 1024 at startup. |
| Custom ratio width component | 1–16384. |
| Custom ratio height component | 1–16384. |
| Calculated window height | Must be 200–16384 logical points for a resize to proceed. |

Invalid numeric entries are rejected and prompted again. If a ratio produces a height outside the allowed range, the script returns to the menu so you can change the width or choose another ratio.

**Output:** The front Terminal window is resized and positioned at `{50, 50}` in screen coordinates. The selected ratio, requested size, and actual resulting size are printed to the terminal. No output files are created.

Example output for a 4:3 request when the requested size is available:

```text
Selected ratio: 4:3
Requested: 1024 x 768
Window now: 1024 x 768 logical points.
```

---

## Notes

- Dimensions use **macOS logical points**, which can differ from physical pixels on scaled or Retina displays.
- The aspect ratio applies to the **whole window, including its title bar**.
- Height is calculated from the selected ratio and rounded to the nearest whole point. Some widths therefore produce an approximate ratio.
- Available screen space and Terminal's character grid may constrain the actual size. Compare the `Requested` and `Window now` values after resizing.
- The configured width is retained while the script runs and resets to 1024 on the next launch. Changing the width with `w` takes effect when you next select a ratio.
- If resizing fails, ensure a Terminal window is open and outside full screen, then select a ratio again. The menu remains open after a resize error.

---

## License

This script is covered under the repository’s main [MIT License](../LICENSE).
