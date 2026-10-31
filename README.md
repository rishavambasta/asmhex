# AsmHex: Ultra-Fast Graphical Hexadecimal File Viewer & Editor in Pure x86_64 Assembly

**AsmHex** is a modern, high-performance, graphical hexadecimal file viewer and editor written entirely in **pure x86_64 assembly** (NASM) for Linux.

It is engineered from scratch for **blistering speed**, **zero perceptible latency**, and **minimal memory footprint**, capable of opening and editing gigabyte- or terabyte-scale binary files instantly using 64-bit kernel memory mapping.

---

## Key Architectural Highlights

1. **Pure x86_64 Assembly Core**:
   - Hand-crafted NASM routines optimized for the System V AMD64 ABI.
   - Entire application binary is only **~60 KB** statically self-contained with embedded font data.
   - Microsecond startup time (< 1 ms from launch to first rendered frame).

2. **Zero-Copy MIT-SHM Graphics Pipeline**:
   - Utilizes the X11 Shared Memory Extension (`XShm` / POSIX `shmget`/`shmat`) for zero-copy framebuffer transfer between client and X server.
   - Software backbuffer writes directly to kernel shared pages, avoiding socket serialization overhead.
   - Benchmark throughput: **> 1,500 FPS** (sub-millisecond frame render latency on low-power Intel Celeron CPUs).

3. **SIMD & Cache-Optimized Rendering Engine**:
   - Vectorized character blitting using **SSE4.2 / SSE2** SIMD instructions and branchless conditional moves (`cmov`).
   - Embedded **8x16 Terminus Bold** console font bitmap directly in `.rodata` (zero external font dependencies).
   - L1-cache resident 2-cycle **Hex Lookup Table** (converts any byte to 2 ASCII hex characters in 2 CPU cycles without `sprintf`).
   - 64-bit **Binary Lookup Table** (`bin_lut`) converts any 8-bit byte into 8 ASCII binary characters (`01001000`) in a single 64-bit load.

4. **Visual Scrollbar, Multi-Row Selection & Keyboard Arrow Selection**:
   - **Proportional Scrollbar**: Sleek vertical scrollbar with dynamically computed proportional thumb (`th_h = (track_h * vis_bytes) / file_size`). Clicking track pages up/down; dragging the thumb smoothly scrolls across gigabyte-scale files.
   - **Keyboard Text/Range Selection**: Hold **`Shift` + Arrow Keys** (`Left`, `Right`, `Up`, `Down`), `Page Up`, `Page Down`, `Home`, `End` to select arbitrary byte ranges using the keyboard. `Ctrl + A` selects the entire file; `Esc` clears active selection.
   - **Multi-Row Drag Selection**: Click and drag across the Hex or ASCII pane to select arbitrary byte ranges across columns and rows, with automatic edge scrolling.
   - **Bright Translucent Polygon**: Selected ranges are enclosed in a custom alpha-blended **translucent luminous polygon** (`0x0089B4FA` @ 38% opacity) bounded by a bright cyan enclosing perimeter border (`0x0089DCEB`). Text within the selection is blitted transparently in pure white (`COLOR_SEL_TEXT = #FFFFFF`).
   - **Live Selection Inspector**: Inspector dynamically displays selection start offset, end offset, total byte length in decimal and hex (`Length: 37 B (0x0025)`).

5. **Tabbed Diff View, Binary Diff Engine & Bottom Diff Offsets Strip**:
   - **Modern Header Tabs**: When two files are opened or compared (`./asmhex file1 file2` or `--diff`), the header displays elevated interactive tabs for **[1] file1** and **[2] file2** with cyan active accent stripes and perimeter borders.
   - **Clickable Tab Switching**: Click directly on either header tab or press **`F2`** to toggle active viewing between File 1 and File 2 instantly, keeping exact cursor alignment.
   - **Bottom Diff Offsets Strip**: In Diff Mode, the bottom status area expands into a dedicated 3-line dock:
     - **Line 1 (Status Summary)**: Displays active diff navigation status (`[DIFF] Difference 1 of N at offset 0x...`).
     - **Line 2 (Diff Offsets List)**: Displays all mismatching byte offsets as interactive chips (`Diffs (N): 0x000a [0x0020] 0x0032 ...`). The currently active diff is highlighted with `[0x%04lx]` and elevated background. Click any offset chip to jump straight to that difference!
     - **Line 3 (Shortcuts Bar)**: Navigation cheat sheet (`F3: Next Diff | Shift+F3/F7: Prev Diff | F2: Switch File Tab | Esc: Deselect | F12: Checksums`).
   - **`F3` Diff Navigation**: Press **`F3`** in Diff Mode to step forward to the next difference with automatic page scrolling and wrap-around. Press **`Shift + F3`** or **`F7`** to step backward. (Outside Diff Mode, `F3` continues to find next search occurrence).
   - **Visual Diff Highlighting**: Mismatching bytes between File 1 and File 2 glow in dark wine background (`COLOR_DIFF_BG = #451525`) and bright coral red foreground (`COLOR_DIFF_FG = #F38BA8`) across both Hex and ASCII panes.
   - **XDnD Drag-and-Drop Diffing**: Dragging a second file into an already open file window immediately enables **Diff Mode** with full tabbed view and diff offsets listing.
   - **Live Diff Inspector**: Shows total mismatch count (`Diffs: N`), active file badge (`Active: File 1/2`), File 1 vs File 2 values at cursor (`File 1: 0xaa ('*') <=> File 2: 0xbb ('+')`), and match status (`IDENTICAL [==]` or `MISMATCH [!=]`).

6. **Dynamic Window Resizing & Responsive Layout**:
   - **Seamless X11 Resizing**: Maximizing, tiling (e.g. i3, Sway), or dragging window edges immediately reallocates MIT-SHM shared memory backbuffers and redraws the UI without restarting.
   - **Adaptive Data Rows**: Grid dynamically computes visible rows based on window height (29 rows at 800x600, 37 rows at 1040x720, 59 rows at 1080p Full HD, and scales cleanly to 4K).
   - **Proportional Geometry**: Track height, thumb geometry, and panel backgrounds stretch dynamically across resized bounds.
   - **Cursor Visibility Retention**: Shrinking the window automatically clamps and scrolls so the cursor never gets lost off-screen.
   - **WM Size Hints**: Advertises `PMinSize` (760x360) via `XSetWMNormalHints` to ensure window managers prevent invalid shrinking.

7. **Lowercase Hexadecimal Formatting**:
   - All hexadecimal values throughout the application are rendered in elegant lowercase (`0123456789abcdef`):
     - Hex data grid bytes (`00..ff`)
     - Column headers (`00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f`)
     - 64-bit row offsets (`0000000000000000..ffffffffffffffff`)
     - Data inspector values, integers, selection ranges, and cryptographic checksums (CRC-32 & SHA-256)

8. **Drag-and-Drop File Opening (XDnD Protocol)**:
   - Built-in support for the X Direct Save / Drag-and-Drop (XDnD version 5) protocol.
   - Drag any file from modern file managers (GNOME Files, Dolphin, Thunar, PCManFM) onto the window to open and inspect it immediately.
   - Built-in URI percent-decoding handles spaces (`%20`), special characters, and `file://` / `localhost` prefixes in pure assembly.

9. **Safe Copy-on-Write Memory Architecture & Clean Blank Files**:
   - **Zero Disk Mutation on Exit**: Edits are stored purely in private RAM buffers. Closing or quitting (`Ctrl+Q` or `Esc`) without saving leaves disk files 100% untouched.
   - **Explicit `Ctrl+S` Saving**: Commits modifications to disk via `SYS_write`, `SYS_ftruncate`, and `SYS_fsync` to guarantee data integrity.
   - **Blank File Creation**: Running `asmhex` without arguments opens `untitled.bin` (0 bytes, 64 KB capacity) ready for immediate binary writing.
   - **Dynamic EOF Appending**: Typing in Hex or ASCII pane at or past EOF automatically reallocates capacity (`SYS_mremap`) and expands `file_size` on the fly.
   - Read-only protection detection: gracefully opens write-protected files in `[READ-ONLY]` mode.

10. **Live Data Inspector**:
   - Real-time side inspector panel decodes the byte(s) at current cursor offset into:
     - **Offset**: 64-bit Hex & Decimal
     - **Values**: Hex, 8-bit Binary, ASCII char
     - **Integers (Little-Endian)**: `uint8`, `int8`, `uint16`, `int16`, `uint32`, `int32`, `uint64`
     - **File Statistics**: File size (human readable), cursor percentage, mode

11. **Selection Cryptographic Checksums (CRC-32 & SHA-256)**:
    - Pure assembly implementations of standard **IEEE 802.3 CRC-32** and **FIPS 180-4 SHA-256**.
    - Press **`F12`** on any highlighted range to instantaneously compute both checksums.
    - Displayed simultaneously in the bottom status line (`CRC32: 0xXXXXXXXX | SHA256: <64-hex>`), inside the side Inspector panel, and logged cleanly to stdout.
    - If no selection is active, `F12` falls back to calculating checksums across the entire file.

12. **Interactive Editing & Multi-Level Undo**:
    - Dual-pane editing: switch effortlessly between **HEX** and **ASCII** panes with `Tab` or `Space`.
    - In-place nibble editing (upper nibble followed by lower nibble, with automatic advance).
    - Multi-level **Undo Stack (`Ctrl+Z`)** (up to 4,096 modification levels).
    - **Modified Byte Highlighting**: every edited byte glows in vivid Coral Red (`#F38BA8`).
    - `Ctrl+S` commits modifications directly to disk via `msync`.
    - In Diff Mode, byte edits immediately recompute the diff count in real time!

13. **Modal Command Navigation**:
    - **Goto Offset (`Ctrl+G`)**: Instant jump to any hex (`0x...`) or decimal file offset.
    - **Find Pattern (`Ctrl+F` / `F3`)**: Sub-millisecond forward and wrapped search for ASCII strings or byte sequences.
    - **Diff Navigation (`F7` / `F8`)**: Step through file differences forward and backward.
    - **Range Checksums (`F12`)**: Immediate CRC-32 & SHA-256 hash calculation over active selection.
    - **Instant Screenshot (`F11`)**: Saves lossless 24-bit PPM screenshots directly from framebuffer.

---

## Keyboard & Mouse Shortcuts

| Shortcut | Description |
|---|---|
| `Arrow Keys` | Move cursor left / right / up / down |
| `Shift + Arrow Keys` | **Select text/range** using keyboard (anchors and extends selection polygon) |
| `Shift + PgUp / PgDn` | Extend selection upward / downward by screenful (576 bytes) |
| `Shift + Home / End` | Extend selection to beginning / end of current row |
| `Ctrl + A` | **Select All** bytes in active file |
| `Page Up` / `Page Down` | Scroll by screenful (576 bytes per page) |
| `Home` / `End` | Jump to beginning / end of current row |
| `Ctrl+Home` / `Ctrl+End` | Jump to start (`0x0`) or end of file |
| `F3` | **Jump to Next Difference** in Diff Mode / Find next pattern in Normal Mode |
| `Shift + F3` / `F7` | **Jump to Previous Difference** in Diff Mode |
| `F8` | Alternate Jump to Next Difference |
| `F2` | **Switch Active File Tab** in Diff Mode (`[1] file1 <-> [2] file2`) |
| `Header Tab Click` | Click on Tab 1 or Tab 2 to switch active file display |
| `Bottom Diff Offset Click` | Click directly on any diff offset chip in bottom strip to jump to that diff |
| `Mouse Left Click` | Position cursor on any byte in Hex or ASCII pane |
| `Mouse Drag Selection` | Drag across Hex or ASCII pane to enclose bytes in bright translucent polygon |
| `Scrollbar Click / Drag` | Click track to Page Up/Down; drag thumb to scroll smoothly |
| `Drag-and-Drop (XDnD)` | Drag file to open; drag second file onto open window to **enable Diff Mode** |
| `Mouse Scroll Wheel` | Smooth vertical scrolling (3 rows per notch) |
| `Tab` / `Space` | Toggle active focus between **HEX** and **ASCII** panes |
| `0-9`, `a-f` | Edit nibble in Hex pane |
| Printable Characters | Write character directly in ASCII pane |
| `Backspace` | Move back or revert edited nibble |
| `Ctrl + S` | Save file modifications (`msync` sync to disk) |
| `Ctrl + Z` | Undo last byte modification |
| `Ctrl + G` | Open **Goto Offset** modal input bar |
| `Ctrl + F` | Open **Find Pattern** search bar |
| `F11` | Capture instant framebuffer screenshot (`asmhex_screenshot.ppm`) |
| `F12` | Calculate and display CRC-32 & SHA-256 for active selection |
| `Esc` | Clear active selection or cancel modal input |
| `Ctrl + Q` | Quit application |

---

## Directory Structure

```
asmhex/
├── .github/
│   └── workflows/
│       └── build-and-release.yml # GitHub Actions CI/CD (Build, Test, Release on push)
├── LICENSE                 # MIT License
├── Makefile                # Build system (nasm + gcc linker driver)
├── README.md               # Documentation & benchmark analysis
├── font.bin                # 8x16 Terminus bold font bitmap (4,096 bytes)
├── src/
│   ├── main.asm            # Application entry, CLI argument parser, X11 event loop
│   ├── renderer.asm        # SSE SIMD pixel blitter, font renderer, LUTs, PPM screenshot
│   ├── editor.asm          # Navigation, hex/ascii editing, tabbed diff engine, undo, search, inspector
│   ├── hash.asm            # Pure assembly IEEE 802.3 CRC-32 & FIPS 180-4 SHA-256 algorithms
│   ├── file_io.asm         # Direct Linux 64-bit syscalls (mmap, munmap, msync, open, close)
│   ├── x11_shm.asm         # X11 display, window management, dynamic resize, zero-copy MIT-SHM pipeline
│   └── include/
│       ├── constants.inc   # Colors, KeySyms, struct layouts, layout dimensions
│       └── macros.inc      # Fast assembly macros & syscall helpers
└── tests/
    ├── test_suite.c        # Automated 20-point unit & integration test runner
    ├── test_benchmark.c    # Render throughput & CPU cycle benchmark
    ├── test_resize_live.c  # Live X11 window resizing verification test
    └── generate_demo_shots.c # Automated demonstration screenshot generator
```

---

## Building and Running

### Prerequisites
- Linux x86_64
- `nasm` (>= 2.15)
- `gcc` and `make`
- `libX11` and `libXext` development libraries

### Compile
```bash
make
```

### Run
```bash
# Open blank file ready for writing (untitled.bin)
./asmhex

# Open and view/edit an existing file (e.g. ELF executable, ROM, raw image)
./asmhex /path/to/binary_file

# Compare / Diff two binary files side-by-side (Method 1)
./asmhex file1.bin file2.bin

# Explicit Diff Mode invocation (Method 2)
./asmhex --diff file1.bin file2.bin
# or short flag:
./asmhex -d file1.bin file2.bin

# Headless screenshot generation
./asmhex --screenshot output.ppm /path/to/binary_file
./asmhex --screenshot diff_output.ppm file1.bin file2.bin
```

### Run Automated Tests (30 Core Functionality Tests)
```bash
make test
```

### Windows 64-bit Port (Windows 10 / 11)
AsmHex provides a native Windows 64-bit binary (`asmhex.exe`) powered by the same pure x86_64 assembly core, SIMD renderer, and cryptographic engines, backed by a top-down GDI `CreateDIBSection` zero-copy presentation host.

```bash
# Build Windows 64-bit binary (asmhex.exe) using MinGW-w64:
make win64

# Run automated Windows 64-bit test suite under Wine:
make test-win64
```

### Run Throughput Benchmark
```bash
make benchmark
```

---

## Performance Benchmark Results

Tested on Intel Celeron N4020 CPU (GeminiLake UHD Graphics 600, 1.10 GHz):

```
========================================================
  AsmHex Performance & Throughput Benchmark
========================================================
  Frames rendered:     1000
  Elapsed time:        0.6722 seconds
  Average frame time:  0.672 ms
  Cycles per frame:    735,660 CPU cycles
  Rendering Speed:     1,487.7 FPS
========================================================
```

Rendering an entire 1040x720 canvas with syntax-colored hex data, ASCII preview, and live data inspector takes **under 0.7 milliseconds** per frame, providing true 1,000+ FPS fluid navigation even on budget hardware.
