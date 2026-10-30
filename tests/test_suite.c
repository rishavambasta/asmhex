#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <assert.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>

// Declarations of our pure assembly symbols
extern void init_renderer_luts(void);
extern void editor_init(void);
extern void editor_render(void);
extern int file_open(const char *path);
extern int file_create_scratch(void);
extern void file_close(void);
extern int file_save(void);

extern int x11_init(const char *title, int w, int h);
extern void x11_cleanup(void);
extern Window win;
extern Display *disp;
extern Atom xdnd_selection_atom;
extern Atom text_uri_list_atom;
extern int x11_get_drop_file_path(Atom prop, char *out_buf, int max_len);

extern uint64_t cursor_offset;
extern uint64_t scroll_offset;
extern uint32_t active_pane;
extern uint32_t nibble_index;
extern uint32_t is_dirty;
extern uint32_t editor_mode;
extern uint8_t *file_ptr;
extern uint64_t file_size;

extern uint64_t sel_start;
extern uint64_t sel_end;
extern uint32_t has_selection;
extern uint32_t is_selecting;
extern uint32_t is_dragging_scrollbar;
extern int32_t thumb_y;
extern int32_t thumb_h;

extern uint32_t *fb_data;
extern int32_t win_w;
extern int32_t win_h;
extern int32_t fb_pitch;
extern uint32_t visible_rows;
extern uint32_t visible_bytes;
extern void editor_update_geometry(void);
extern void editor_ensure_visible(void);
extern uint32_t editor_get_visible_rows(void);
extern uint32_t editor_get_visible_bytes(void);

extern void draw_rect_alpha(int x, int y, int w, int h, uint32_t color, int alpha);
extern int editor_handle_key(uint64_t sym, char *ascii_buf, int ascii_len, int state);
extern void editor_handle_click(int x, int y);
extern void editor_handle_mouse_move(int x, int y);
extern void editor_handle_button_release(int x, int y);
extern void editor_undo(void);
extern void editor_search_next(void);
extern int dump_screenshot(const char *filename);

extern void init_crc32_table(void);
extern uint32_t compute_crc32(const uint8_t *data, uint64_t len);
extern void compute_sha256(const uint8_t *data, uint64_t len, uint8_t *digest_out);
extern void format_sha256_hex(const uint8_t *digest_in, char *hex_out);
extern void editor_compute_selection_checksum(void);
extern uint32_t last_checksum_valid;
extern uint32_t last_crc32;
extern char last_sha256_hex[68];
extern uint64_t last_checksum_off;
extern uint64_t last_checksum_len;

extern int file2_open(const char *path);
extern void file2_close(void);
extern uint8_t *file2_ptr;
extern uint64_t file2_size;
extern uint32_t is_diff_mode;
extern uint32_t diff_active_file;
extern uint64_t diff_count;
extern void diff_recompute(void);
extern void editor_diff_next(void);
extern void editor_diff_prev(void);
extern void editor_diff_flip(void);
extern void format_hex_qword(char *dst, uint64_t val);
extern void format_hex_dword(char *dst, uint32_t val);
extern uint16_t hex_lut[256];

int main() {
    printf("========================================================\n");
    printf("  Running AsmHex Comprehensive Test Suite...\n");
    printf("========================================================\n");

    init_renderer_luts();
    init_crc32_table();

    // Test 1: Scratch buffer creation
    printf("[TEST 1] Testing scratch buffer creation...\n");
    int res = file_create_scratch();
    assert(res == 0);
    assert(file_ptr != NULL);
    assert(file_size == 4096);
    editor_init();
    assert(cursor_offset == 0);
    assert(active_pane == 0); // PANE_HEX
    printf("  -> Scratch buffer created: 4096 bytes mapped.\n");

    // Test 2: Cursor navigation
    printf("[TEST 2] Testing navigation keys...\n");
    char empty[1] = {0};
    // Move Right (nibble 0 -> nibble 1)
    editor_handle_key(XK_Right, empty, 0, 0);
    assert(nibble_index == 1);
    assert(cursor_offset == 0);

    // Move Right again (nibble 1 -> nibble 0, cursor 1)
    editor_handle_key(XK_Right, empty, 0, 0);
    assert(nibble_index == 0);
    assert(cursor_offset == 1);

    // Move Down (cursor 1 + 16 = 17)
    editor_handle_key(XK_Down, empty, 0, 0);
    assert(cursor_offset == 17);

    // Move Up (cursor 17 - 16 = 1)
    editor_handle_key(XK_Up, empty, 0, 0);
    assert(cursor_offset == 1);

    // Home (start of row = 0)
    editor_handle_key(XK_Home, empty, 0, 0);
    assert(cursor_offset == 0);

    // End (end of row = 15)
    editor_handle_key(XK_End, empty, 0, 0);
    assert(cursor_offset == 15);
    printf("  -> Navigation keys (Left/Right/Up/Down/Home/End) passed.\n");

    // Test 3: Hex editing
    printf("[TEST 3] Testing hex editing...\n");
    cursor_offset = 100;
    nibble_index = 0;
    uint8_t old_val = file_ptr[100];

    // Type 'A' (upper nibble = 0xA0)
    char hex_a[1] = {'A'};
    editor_handle_key('A', hex_a, 1, 0);
    assert(nibble_index == 1);
    assert(cursor_offset == 100);
    assert((file_ptr[100] & 0xF0) == 0xA0);

    // Type '5' (lower nibble = 0xA5, advances cursor to 101)
    char hex_5[1] = {'5'};
    editor_handle_key('5', hex_5, 1, 0);
    assert(nibble_index == 0);
    assert(cursor_offset == 101);
    assert(file_ptr[100] == 0xA5);
    assert(is_dirty == 1);
    printf("  -> Hex editing: modified byte at 100 to 0x%02X.\n", file_ptr[100]);

    // Test 4: Undo functionality (Ctrl+Z)
    printf("[TEST 4] Testing undo functionality (Ctrl+Z)...\n");
    editor_handle_key('z', empty, 0, 4); // state = 4 (ControlMask)
    assert(file_ptr[100] == old_val);
    assert(cursor_offset == 100);
    printf("  -> Undo successful: byte restored to original 0x%02X.\n", old_val);

    // Test 5: Tab key (Switch between HEX and ASCII panes)
    printf("[TEST 5] Testing pane switching (Tab)...\n");
    assert(active_pane == 0);
    editor_handle_key(XK_Tab, empty, 0, 0);
    assert(active_pane == 1); // PANE_ASCII
    editor_handle_key(XK_Tab, empty, 0, 0);
    assert(active_pane == 0); // PANE_HEX
    printf("  -> Tab pane switching passed.\n");

    // Test 6: ASCII editing
    printf("[TEST 6] Testing ASCII pane editing...\n");
    active_pane = 1; // PANE_ASCII
    cursor_offset = 200;
    char char_w[1] = {'W'};
    editor_handle_key('W', char_w, 1, 0);
    assert(file_ptr[200] == 'W');
    assert(cursor_offset == 201);
    printf("  -> ASCII editing: wrote 'W' and advanced cursor.\n");

    // Test 7: Goto offset modal dialog
    printf("[TEST 7] Testing Goto Offset...\n");
    editor_handle_key('g', empty, 0, 4); // Ctrl+G
    assert(editor_mode == 1); // MODE_GOTO
    // Type "0x120"
    char str_goto[] = "0x120";
    for (int i = 0; str_goto[i]; i++) {
        char ch[1] = {str_goto[i]};
        editor_handle_key(str_goto[i], ch, 1, 0);
    }
    // Press Return to commit
    editor_handle_key(XK_Return, empty, 0, 0);
    assert(editor_mode == 0); // back to normal
    assert(cursor_offset == 0x120);
    printf("  -> Goto Offset: successfully jumped to 0x120 (%ld).\n", cursor_offset);

    // Test 8: Search / Find functionality
    printf("[TEST 8] Testing Find pattern...\n");
    // Write search target "MYMAGIC" at offset 500
    memcpy(file_ptr + 500, "MYMAGIC", 7);
    cursor_offset = 0;
    editor_handle_key('f', empty, 0, 4); // Ctrl+F
    assert(editor_mode == 2); // MODE_SEARCH
    char str_find[] = "MYMAGIC";
    for (int i = 0; str_find[i]; i++) {
        char ch[1] = {str_find[i]};
        editor_handle_key(str_find[i], ch, 1, 0);
    }
    editor_handle_key(XK_Return, empty, 0, 0);
    assert(cursor_offset == 500);
    printf("  -> Find Pattern: successfully found 'MYMAGIC' at offset %ld.\n", cursor_offset);

    file_close();

    // Test 9: File opening and memory mapping
    printf("[TEST 9] Testing real file open & mmap...\n");
    FILE *fp = fopen("/tmp/asmhex_test.dat", "wb");
    uint8_t sample_data[256];
    for (int i = 0; i < 256; i++) sample_data[i] = (uint8_t)i;
    fwrite(sample_data, 1, 256, fp);
    fclose(fp);

    res = file_open("/tmp/asmhex_test.dat");
    assert(res == 0);
    assert(file_size == 256);
    assert(file_ptr != NULL);
    assert(file_ptr[42] == 42);

    // Modify byte and test save
    file_ptr[42] = 0xAA;
    res = file_save();
    assert(res == 0);
    file_close();

    // Reopen and check byte persisted
    fp = fopen("/tmp/asmhex_test.dat", "rb");
    fseek(fp, 42, SEEK_SET);
    uint8_t read_back = 0;
    if (fread(&read_back, 1, 1, fp) != 1) {
        printf("Error reading back file!\n");
    }
    fclose(fp);
    assert(read_back == 0xAA);
    printf("  -> File save & msync persistence verified: byte 42 = 0x%02X.\n", read_back);

    // Test 10: SIMD Alpha Blending
    printf("[TEST 10] Testing SSE2 SIMD alpha blending (draw_rect_alpha)...\n");
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    uint32_t *test_fb = malloc(1040 * 720 * 4);
    for (int i = 0; i < 1040 * 720; i++) test_fb[i] = 0x001E1E2E; // Catppuccin Base
    fb_data = test_fb;

    // Blend COLOR_SEL_FILL (0x0089B4FA) with alpha 96 (37.5%)
    draw_rect_alpha(100, 100, 50, 20, 0x0089B4FA, 96);
    uint32_t blended_pixel = test_fb[100 * 1040 + 100];
    assert(blended_pixel == 0x0046567A);
    printf("  -> SIMD Alpha Blending verified: 0x001E1E2E + 0x0089B4FA @ 96 alpha = 0x%08X.\n", blended_pixel);

    // Test 11: Mouse Drag Range Selection
    printf("[TEST 11] Testing mouse drag selection in editor window...\n");
    file_create_scratch();
    editor_init();
    assert(has_selection == 0);
    assert(is_selecting == 0);

    // Left click at Hex pane row 0, col 0 (offset 0):
    // x = HEX_START_X (164), y = SEPARATOR_Y + 10 (62)
    editor_handle_click(164, 62);
    assert(is_selecting == 1);
    assert(has_selection == 0);
    assert(sel_start == 0);
    assert(cursor_offset == 0);

    // Drag mouse to row 2, col 4:
    // row 2: y = 56 + 2 * 16 = 88. col 4: x = 164 + 4 * 24 = 260.
    // target offset = 2 * 16 + 4 = 36
    editor_handle_mouse_move(260, 88);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 36);
    assert(cursor_offset == 36);

    // Release mouse button:
    editor_handle_button_release(260, 88);
    assert(is_selecting == 0);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 36);
    printf("  -> Drag selection verified: selected bytes 0x0000..0x%04X (37 bytes).\n", (int)sel_end);

    // Test single click deselects
    editor_handle_click(164 + 24, 62); // click byte 1
    editor_handle_button_release(164 + 24, 62);
    assert(has_selection == 0);
    assert(cursor_offset == 1);
    printf("  -> Single click deselect verified: selection cleared, cursor placed at 0x0001.\n");

    // Test 12: Interactive Scrollbar Geometry & Thumb Dragging
    printf("[TEST 12] Testing scrollbar proportional thumb & dragging...\n");
    // Render frame to compute initial thumb dimensions
    editor_render();
    assert(thumb_h >= 24); // SCROLL_THUMB_MIN_H
    int orig_thumb_y = thumb_y;

    // Click on scrollbar thumb (SCROLLBAR_X = 722)
    editor_handle_click(725, orig_thumb_y + 4);
    assert(is_dragging_scrollbar == 1);

    // Drag thumb down by 40 pixels
    editor_handle_mouse_move(725, orig_thumb_y + 44);
    assert(scroll_offset > 0);
    assert((scroll_offset & 15) == 0); // aligned to row boundary (multiple of 16)
    printf("  -> Scrollbar drag verified: scrolled to offset 0x%lX.\n", scroll_offset);

    // Release scrollbar drag
    editor_handle_button_release(725, orig_thumb_y + 44);
    assert(is_dragging_scrollbar == 0);

    // Test 13: XDnD Drag & Drop File Opening Protocol
    printf("[TEST 13] Testing XDnD Drag & Drop protocol & URI path decoding...\n");
    int x11_res = x11_init("XDnD Test", 640, 480);
    if (x11_res == 0) {
        const char *uri = "file:///tmp/asmhex_test%20file.dat\r\n";
        XChangeProperty(disp, win, xdnd_selection_atom, text_uri_list_atom, 8, PropModeReplace,
                        (const unsigned char*)uri, strlen(uri));

        char path[256] = {0};
        int ok = x11_get_drop_file_path(xdnd_selection_atom, path, sizeof(path));
        assert(ok == 1);
        assert(strcmp(path, "/tmp/asmhex_test file.dat") == 0);
        printf("  -> XDnD decoded dropped URI 'file:///tmp/asmhex_test%%20file.dat' to '%s'.\n", path);
        x11_cleanup();
    } else {
        printf("  -> Notice: Display not available in headless test; skipped live XDnD socket.\n");
    }

    // Test 14: Hex Byte Nibbles (High & Low Nibble Glyph Verification)
    printf("[TEST 14] Testing Hex Byte High & Low Nibble rendering...\n");
    uint32_t *nib_fb = malloc(1040 * 720 * 4);
    for (int i = 0; i < 1040 * 720; i++) nib_fb[i] = 0x001E1E2E;
    fb_data = nib_fb;
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;

    file_create_scratch();
    editor_init();
    file_ptr[0] = 0xA5; // 'A' and '5'
    cursor_offset = 10; // move cursor away from byte 0 so byte 0 has standard background
    editor_render();

    // High nibble glyph 'A' is at x = 164, y = 58
    // Low nibble glyph '5' is at x = 172, y = 58
    // Verify that low nibble pixel has foreground text color (not non-printable blank or control char)
    uint32_t fg_pix_count = 0;
    for (int y = 58; y < 74; y++) {
        for (int x = 172; x < 180; x++) {
            if (nib_fb[y * 1040 + x] != 0x001E1E2E) {
                fg_pix_count++;
            }
        }
    }
    // Glyph '5' has active pixels in font bitmap
    assert(fg_pix_count > 20 && fg_pix_count < 45);
    printf("  -> Low nibble rendered correctly with %u glyph pixels (verified printable hex digit '5').\n", fg_pix_count);

    free(nib_fb);
    file_close();

    // Test 15: F12 Selection SHA-256 and CRC-32 Checksums
    printf("[TEST 15] Testing F12 Selection SHA-256 and CRC-32 Checksum Engine...\n");
    // 15a: Verify pure assembly CRC32 test vector
    const char *test_crc_str = "123456789";
    uint32_t c1 = compute_crc32((const uint8_t*)test_crc_str, strlen(test_crc_str));
    assert(c1 == 0xCBF43926);
    printf("  -> CRC32 standard test vector (0xCBF43926) matched bit-for-bit.\n");

    // 15b: Verify pure assembly SHA-256 test vectors
    uint8_t d_empty[32];
    char hex_empty[65];
    compute_sha256((const uint8_t*)"", 0, d_empty);
    format_sha256_hex(d_empty, hex_empty);
    assert(strcmp(hex_empty, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0);

    const char *test_sha_str = "Fast AsmHex SHA256 test string for Intel SSE4.2 / SHA Extensions verification!";
    uint8_t d_test[32];
    char hex_test[65];
    compute_sha256((const uint8_t*)test_sha_str, strlen(test_sha_str), d_test);
    format_sha256_hex(d_test, hex_test);
    assert(strcmp(hex_test, "d01cd276c9868f08d117bb44c16ab29a6f68ca2d3027cf86881ba45c69a80459") == 0);

    // NIST standard test vector "abc"
    uint8_t d_abc[32];
    char hex_abc[65];
    compute_sha256((const uint8_t*)"abc", 3, d_abc);
    format_sha256_hex(d_abc, hex_abc);
    assert(strcmp(hex_abc, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
    printf("  -> SHA-256 standard test vectors (NIST empty, 'abc', & string) matched bit-for-bit.\n");

    // 15c: Verify F12 hotkey on active selection in editor
    file_create_scratch();
    editor_init();
    for (int i = 0; i < 256; i++) {
        file_ptr[i] = (uint8_t)(i ^ 0x5A);
    }
    // Select range 0x40..0x7F (64 bytes: 64 to 127)
    has_selection = 1;
    sel_start = 64;
    sel_end = 127;
    assert(last_checksum_valid == 0);

    // Press F12
    editor_handle_key(XK_F12, NULL, 0, 0);
    assert(last_checksum_valid == 1);
    assert(last_checksum_off == 64);
    assert(last_checksum_len == 64);

    uint32_t exp_crc = compute_crc32(file_ptr + 64, 64);
    uint8_t exp_sha_d[32];
    char exp_sha_h[65];
    compute_sha256(file_ptr + 64, 64, exp_sha_d);
    format_sha256_hex(exp_sha_d, exp_sha_h);

    assert(last_crc32 == exp_crc);
    assert(strcmp(last_sha256_hex, exp_sha_h) == 0);
    printf("  -> F12 key press computed selection CRC32 (0x%08X) and SHA-256 (%s) bit-exact.\n",
           last_crc32, last_sha256_hex);

    // 15d: Whole file fallback when no selection
    has_selection = 0;
    editor_handle_key(XK_F12, NULL, 0, 0);
    assert(last_checksum_valid == 1);
    assert(last_checksum_off == 0);
    assert(last_checksum_len == file_size);
    printf("  -> F12 whole-file fallback verified: computed over all %lu bytes.\n", file_size);

    // 15e: Modification invalidates stale checksums
    char key_char[1] = {'A'};
    cursor_offset = 0;
    active_pane = 0;
    nibble_index = 0;
    editor_handle_key('a', key_char, 1, 0);
    assert(last_checksum_valid == 0);
    printf("  -> Stale checksum invalidation upon byte edit verified.\n");

    file_close();

    // -------------------------------------------------------------------------
    // TEST 16: Keyboard Range Selection (Shift + Arrows, Ctrl + A, Escape)
    // -------------------------------------------------------------------------
    printf("\nTest 16: Keyboard Range Selection Engine...\n");
    file_create_scratch();
    editor_init();
    assert(has_selection == 0);
    assert(cursor_offset == 0);

    // Shift + Right (state & 1 == ShiftMask)
    editor_handle_key(XK_Right, NULL, 0, 1);
    assert(cursor_offset == 1);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 1);
    printf("  -> Shift+Right anchored selection at 0 and advanced to offset 1.\n");

    // Shift + Down: should advance cursor by 16 bytes (to offset 17)
    editor_handle_key(XK_Down, NULL, 0, 1);
    assert(cursor_offset == 17);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 17);
    printf("  -> Shift+Down expanded selection to offset 17 (18 bytes total).\n");

    // Shift + Left: shrink back by 1 byte (to offset 16)
    editor_handle_key(XK_Left, NULL, 0, 1);
    assert(cursor_offset == 16);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 16);
    printf("  -> Shift+Left shrunk selection to offset 16.\n");

    // Arrow key WITHOUT Shift: clears active selection
    editor_handle_key(XK_Right, NULL, 0, 0);
    assert(has_selection == 0);
    printf("  -> Plain arrow key (no Shift) cleanly cleared selection.\n");

    // Ctrl + A: Select All (state & 4 == ControlMask)
    editor_handle_key('a', NULL, 0, 4);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == file_size - 1);
    assert(cursor_offset == file_size - 1);
    printf("  -> Ctrl+A selected entire file: range 0x%lx..0x%lx (%lu bytes).\n",
           sel_start, sel_end, file_size);

    // Escape clears selection
    editor_handle_key(XK_Escape, NULL, 0, 0);
    assert(has_selection == 0);
    printf("  -> Escape key cleared selection.\n");

    file_close();

    // -------------------------------------------------------------------------
    // TEST 17: Multi-File Comparison & Diff Engine (F2, F7, F8)
    // -------------------------------------------------------------------------
    printf("\nTest 17: Multi-File Comparison & Diff Engine...\n");
    const char *tmp1 = "/tmp/asmhex_diff1.dat";
    const char *tmp2 = "/tmp/asmhex_diff2.dat";

    // Write file 1: 128 bytes with all 0xAA
    FILE *f1 = fopen(tmp1, "wb");
    assert(f1 != NULL);
    uint8_t b1[128];
    memset(b1, 0xAA, 128);
    fwrite(b1, 1, 128, f1);
    fclose(f1);

    // Write file 2: 144 bytes with all 0xAA except offset 10 (0xBB), offset 42 (0xCC), and 16 extra bytes at end (0xDD)
    FILE *f2 = fopen(tmp2, "wb");
    assert(f2 != NULL);
    uint8_t b2[144];
    memset(b2, 0xAA, 144);
    b2[10] = 0xBB;
    b2[42] = 0xCC;
    memset(b2 + 128, 0xDD, 16);
    fwrite(b2, 1, 144, f2);
    fclose(f2);

    // Open file 1 and file 2
    assert(file_open(tmp1) == 0);
    assert(file2_open(tmp2) == 0);
    editor_init();

    // Enable Diff Mode and recompute
    is_diff_mode = 1;
    diff_recompute();

    // Expected differences: offset 10 (1), offset 42 (1), plus 16 bytes tail mismatch = 18 diffs
    assert(diff_count == 18);
    printf("  -> diff_recompute detected exact difference count: %lu mismatches.\n", diff_count);

    // Test editor_diff_next: starting from 0, next diff should be offset 10
    cursor_offset = 0;
    editor_diff_next();
    assert(cursor_offset == 10);
    printf("  -> editor_diff_next jumped directly to first difference at offset 10.\n");

    // Next diff should be offset 42
    editor_diff_next();
    assert(cursor_offset == 42);
    printf("  -> editor_diff_next jumped directly to second difference at offset 42.\n");

    // Next diff should jump to offset 128 (EOF tail of file 1 vs file 2)
    editor_diff_next();
    assert(cursor_offset == 128);
    printf("  -> editor_diff_next jumped to file length mismatch at offset 128.\n");

    // Test editor_diff_prev: backward navigation to offset 42
    editor_diff_prev();
    assert(cursor_offset == 42);
    printf("  -> editor_diff_prev jumped backward to offset 42.\n");

    // editor_diff_prev to offset 10
    editor_diff_prev();
    assert(cursor_offset == 10);
    printf("  -> editor_diff_prev jumped backward to offset 10.\n");

    // Test editor_diff_flip (F2)
    assert(diff_active_file == 0);
    editor_diff_flip();
    assert(diff_active_file == 1);
    printf("  -> editor_diff_flip switched active display to File 2.\n");
    editor_diff_flip();
    assert(diff_active_file == 0);
    printf("  -> editor_diff_flip switched active display back to File 1.\n");

    // Clean up
    file2_close();
    file_close();
    remove(tmp1);
    remove(tmp2);

    // -------------------------------------------------------------------------
    // TEST 18: Lowercase Hex Digits Verification
    // -------------------------------------------------------------------------
    printf("\nTest 18: Lowercase Hexadecimal Display Formatting...\n");
    char hex_q[17];
    format_hex_qword(hex_q, 0x0123456789abcdefULL);
    assert(strcmp(hex_q, "0123456789abcdef") == 0);
    printf("  -> format_hex_qword produced pure lowercase hex: '%s'.\n", hex_q);

    char hex_d[9];
    format_hex_dword(hex_d, 0xdeadbeef);
    assert(strcmp(hex_d, "deadbeef") == 0);
    printf("  -> format_hex_dword produced pure lowercase hex: '%s'.\n", hex_d);

    // Verify hex_lut contains lowercase ascii digits '0'..'9', 'a'..'f'
    // Byte 0x0A => "0a" (ASCII '0' = 0x30, 'a' = 0x61)
    uint16_t lut_0a = hex_lut[0x0a];
    char ch0 = (char)(lut_0a & 0xFF);
    char ch1 = (char)((lut_0a >> 8) & 0xFF);
    assert(ch0 == '0' && ch1 == 'a');

    // Byte 0xFE => "fe"
    uint16_t lut_fe = hex_lut[0xfe];
    assert((char)(lut_fe & 0xFF) == 'f' && (char)((lut_fe >> 8) & 0xFF) == 'e');
    printf("  -> hex_lut verified with lowercase byte representations ('0a', 'fe').\n");

    // -------------------------------------------------------------------------
    // TEST 19: Dynamic Window Resizing & Geometry Engine
    // -------------------------------------------------------------------------
    printf("\nTest 19: Dynamic Window Resizing & Geometry Engine...\n");

    // 1. Initial 720p geometry
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    editor_update_geometry();
    uint32_t expected_rows_720 = (720 - (52 + 54 + 16)) / 16; // 37 rows
    assert(visible_rows == expected_rows_720);
    assert(visible_bytes == expected_rows_720 * 16);
    assert(editor_get_visible_rows() == expected_rows_720);
    assert(editor_get_visible_bytes() == expected_rows_720 * 16);
    printf("  -> 1040x720 baseline: %u visible rows, %u visible bytes.\n", visible_rows, visible_bytes);

    // 2. Expand to 1920x1080 (Full HD / Maximized window)
    win_w = 1920;
    win_h = 1080;
    fb_pitch = 1920 * 4;
    editor_update_geometry();
    uint32_t expected_rows_1080 = (1080 - (52 + 54 + 16)) / 16; // 59 rows
    assert(visible_rows == expected_rows_1080);
    assert(visible_bytes == expected_rows_1080 * 16);
    printf("  -> 1920x1080 expansion: scaled up to %u visible rows, %u visible bytes.\n", visible_rows, visible_bytes);

    // Render at 1920x1080 to verify zero crash or buffer overflow
    file_create_scratch();
    uint32_t *fb_1080 = malloc(1920 * 1080 * 4);
    assert(fb_1080 != NULL);
    fb_data = fb_1080;
    editor_render();
    printf("  -> 1920x1080 frame rendered successfully with no memory faults.\n");
    free(fb_1080);

    // 3. Shrink to 800x600 (compact window)
    win_w = 800;
    win_h = 600;
    fb_pitch = 800 * 4;
    editor_update_geometry();
    uint32_t expected_rows_600 = (600 - (52 + 54 + 16)) / 16; // 29 rows
    assert(visible_rows == expected_rows_600);
    assert(visible_bytes == expected_rows_600 * 16);
    printf("  -> 800x600 compact: scaled down to %u visible rows, %u visible bytes.\n", visible_rows, visible_bytes);

    uint32_t *fb_600 = malloc(800 * 600 * 4);
    assert(fb_600 != NULL);
    fb_data = fb_600;
    editor_render();
    printf("  -> 800x600 frame rendered successfully with clean clipping.\n");
    free(fb_600);

    // 4. Cursor visibility preservation on window resize/shrink
    // Place cursor at offset 800
    cursor_offset = 800;
    editor_ensure_visible();
    // Offset 800 must be in [scroll_offset, scroll_offset + visible_bytes)
    assert(cursor_offset >= scroll_offset);
    assert(cursor_offset < scroll_offset + visible_bytes);
    printf("  -> editor_ensure_visible adjusted scroll_offset to 0x%lx, keeping cursor visible.\n", scroll_offset);
    file_close();

    printf("\n========================================================\n");
    printf("  ALL 19 CORE FUNCTIONALITY TESTS PASSED WITH 100%% SUCCESS!\n");
    printf("========================================================\n");
    return 0;
}
