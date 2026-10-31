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
extern int file_create_blank(void);
extern int file_ensure_capacity(uint64_t needed);
extern void file_close(void);
extern int file_save(void);
extern uint64_t file_capacity;
extern char file_path[512];
extern int file_fd;
extern uint32_t is_scratch;

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
extern void editor_next_byte(void);
extern void editor_move_down(void);
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
extern uint64_t diff_list[1024];
extern uint32_t diff_list_count;
extern int32_t current_diff_idx;
extern uint32_t diff_chip_count;
extern int32_t diff_chip_x_start[16];
extern int32_t diff_chip_x_end[16];
extern int32_t diff_chip_idx[16];
extern void diff_recompute(void);
extern void editor_diff_next(void);
extern void editor_diff_prev(void);
extern void editor_diff_flip(void);
extern void format_hex_qword(char *dst, uint64_t val);
extern void format_hex_dword(char *dst, uint32_t val);
extern uint16_t hex_lut[256];

extern int file_save_as(const char *path);
extern int32_t font_scale;
extern int32_t cur_offset_x;
extern int32_t cur_gutter_sep_x;
extern int32_t cur_hex_start_x;
extern int32_t cur_byte_spacing;
extern int32_t cur_group_gap;
extern int32_t cur_hex_end_x;
extern int32_t cur_ascii_sep_x;
extern int32_t cur_ascii_start_x;
extern int32_t cur_ascii_end_x;
extern int32_t cur_char_w;
extern int32_t row_h;
extern int32_t cur_scrollbar_x;
extern int32_t cur_scrollbar_w;
extern int32_t cur_data_pane_w;
extern int32_t cur_panel_divider_x;
extern int32_t cur_inspector_x;
extern int32_t cur_line_h;
extern int32_t cur_sec_gap;
extern int32_t cur_insp_col_val;
extern int32_t cur_header_h;
extern int32_t cur_col_hdr_h;
extern int32_t cur_separator_y;
extern int32_t cur_status_h;
extern char insp_h_save_as[];
extern void editor_zoom_in(void);
extern void editor_zoom_out(void);
extern void editor_zoom_reset(void);
extern void editor_start_save_as(void);
extern void editor_commit_save_as(void);
extern void editor_prompt_confirm_quit(void);
extern char input_buf[128];
extern uint32_t input_len;

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
    // x = HEX_START_X (100), y = SEPARATOR_Y + 10 (62)
    editor_handle_click(100, 62);
    assert(is_selecting == 1);
    assert(has_selection == 0);
    assert(sel_start == 0);
    assert(cursor_offset == 0);

    // Drag mouse to row 2, col 4:
    // row 2: y = 56 + 2 * 16 = 88. col 4: x = 100 + 4 * 24 = 196.
    // target offset = 2 * 16 + 4 = 36
    editor_handle_mouse_move(196, 88);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 36);
    assert(cursor_offset == 36);

    // Release mouse button:
    editor_handle_button_release(196, 88);
    assert(is_selecting == 0);
    assert(has_selection == 1);
    assert(sel_start == 0);
    assert(sel_end == 36);
    printf("  -> Drag selection verified: selected bytes 0x0000..0x%04X (37 bytes).\n", (int)sel_end);

    // Test single click deselects
    editor_handle_click(100 + 24, 62); // click byte 1
    editor_handle_button_release(100 + 24, 62);
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

    // High nibble glyph 'A' is at x = 100, y = 58
    // Low nibble glyph '5' is at x = 108, y = 58
    // Verify that low nibble pixel has foreground text color (not non-printable blank or control char)
    uint32_t fg_pix_count = 0;
    for (int y = 58; y < 74; y++) {
        for (int x = 108; x < 116; x++) {
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

    // 1. Initial 720p geometry (with STATUS_H = 72)
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    editor_update_geometry();
    uint32_t expected_rows_720 = (720 - (52 + 72 + 16)) / 16; // 36 rows
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
    uint32_t expected_rows_1080 = (1080 - (52 + 72 + 16)) / 16; // 58 rows
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
    uint32_t expected_rows_600 = (600 - (52 + 72 + 16)) / 16; // 28 rows
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
    cursor_offset = 800;
    editor_ensure_visible();
    assert(cursor_offset >= scroll_offset);
    assert(cursor_offset < scroll_offset + visible_bytes);
    printf("  -> editor_ensure_visible adjusted scroll_offset to 0x%lx, keeping cursor visible.\n", scroll_offset);
    file_close();

    // -------------------------------------------------------------------------
    // TEST 20: Tabbed Diff View, Bottom Diff Offsets Strip & F3 Navigation
    // -------------------------------------------------------------------------
    printf("\nTest 20: Tabbed Diff View, Bottom Diff List & F3 Navigation Engine...\n");
    const char *tab_f1 = "/tmp/asmhex_tab1.dat";
    const char *tab_f2 = "/tmp/asmhex_tab2.dat";

    FILE *tf1 = fopen(tab_f1, "wb");
    assert(tf1 != NULL);
    uint8_t d1[128];
    memset(d1, 0x11, 128);
    d1[10] = 0xAA;
    d1[35] = 0xBB;
    d1[70] = 0xCC;
    fwrite(d1, 1, 128, tf1);
    fclose(tf1);

    FILE *tf2 = fopen(tab_f2, "wb");
    assert(tf2 != NULL);
    uint8_t d2[128];
    memset(d2, 0x11, 128);
    d2[10] = 0x55;
    d2[35] = 0x66;
    d2[70] = 0x77;
    fwrite(d2, 1, 128, tf2);
    fclose(tf2);

    assert(file_open(tab_f1) == 0);
    assert(file2_open(tab_f2) == 0);
    editor_init();

    is_diff_mode = 1;
    diff_recompute();

    assert(diff_count == 3);
    assert(diff_list_count == 3);
    assert(diff_list[0] == 10);
    assert(diff_list[1] == 35);
    assert(diff_list[2] == 70);
    printf("  -> Diff cache verified: 3 differences recorded at offsets 0x000a, 0x0023, 0x0046.\n");

    // 1. Test Tab UI switching via clicks & F2
    assert(diff_active_file == 0); // Tab 1 active
    editor_handle_click(400, 15);  // Click on Tab 2
    assert(diff_active_file == 1); // Tab 2 active
    printf("  -> Click on Tab 2 successfully switched active tab to File 2.\n");

    editor_handle_click(200, 15);  // Click on Tab 1
    assert(diff_active_file == 0); // Tab 1 active
    printf("  -> Click on Tab 1 successfully switched active tab to File 1.\n");

    editor_handle_key(XK_F2, NULL, 0, 0); // Toggle tab via F2
    assert(diff_active_file == 1);
    editor_handle_key(XK_F2, NULL, 0, 0);
    assert(diff_active_file == 0);
    printf("  -> F2 key successfully toggles active tab.\n");

    // 2. Test F3 Key Navigation (Next Diff)
    cursor_offset = 0;
    editor_handle_key(XK_F3, NULL, 0, 0);
    assert(cursor_offset == 10 && current_diff_idx == 0);
    printf("  -> F3 pressed: jumped to Diff 1 at offset 0x%lx (index %d).\n", cursor_offset, current_diff_idx);

    editor_handle_key(XK_F3, NULL, 0, 0);
    assert(cursor_offset == 35 && current_diff_idx == 1);
    printf("  -> F3 pressed: jumped to Diff 2 at offset 0x%lx (index %d).\n", cursor_offset, current_diff_idx);

    editor_handle_key(XK_F3, NULL, 0, 0);
    assert(cursor_offset == 70 && current_diff_idx == 2);
    printf("  -> F3 pressed: jumped to Diff 3 at offset 0x%lx (index %d).\n", cursor_offset, current_diff_idx);

    // F3 wrap-around
    editor_handle_key(XK_F3, NULL, 0, 0);
    assert(cursor_offset == 10 && current_diff_idx == 0);
    printf("  -> F3 wrap-around verified: cycled back to Diff 1.\n");

    // 3. Test Shift+F3 and F7 (Previous Diff)
    editor_handle_key(XK_F3, NULL, 0, 1 /* ShiftMask */);
    assert(cursor_offset == 70 && current_diff_idx == 2);
    printf("  -> Shift+F3 pressed: navigated backwards to Diff 3 (offset 0x%lx).\n", cursor_offset);

    editor_handle_key(XK_F7, NULL, 0, 0);
    assert(cursor_offset == 35 && current_diff_idx == 1);
    printf("  -> F7 pressed: navigated backwards to Diff 2 (offset 0x%lx).\n", cursor_offset);

    // 4. Test Bottom Diff List rendering & interactive chip click
    uint32_t *fb_diff = malloc(1040 * 720 * 4);
    assert(fb_diff != NULL);
    fb_data = fb_diff;
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    editor_render();

    assert(diff_chip_count == 3);
    assert(diff_chip_idx[0] == 0 && diff_chip_idx[1] == 1 && diff_chip_idx[2] == 2);
    printf("  -> Bottom diff offsets rendered: %u clickable chips generated.\n", diff_chip_count);

    // Click on Chip 2 (offset 70) in bottom bar
    int chip2_x = (diff_chip_x_start[2] + diff_chip_x_end[2]) / 2;
    int chip_y = 720 - 35; // Inside Line 2 (720 - 48 to 720 - 26)
    editor_handle_click(chip2_x, chip_y);
    assert(cursor_offset == 70 && current_diff_idx == 2);
    printf("  -> Clicking bottom diff chip [0x0046] jumped cursor directly to offset 0x%lx.\n", cursor_offset);

    // Click on Chip 0 (offset 10) in bottom bar
    int chip0_x = (diff_chip_x_start[0] + diff_chip_x_end[0]) / 2;
    editor_handle_click(chip0_x, chip_y);
    assert(cursor_offset == 10 && current_diff_idx == 0);
    printf("  -> Clicking bottom diff chip [0x000a] jumped cursor directly to offset 0x%lx.\n", cursor_offset);

    free(fb_diff);
    file2_close();
    file_close();
    remove(tab_f1);
    remove(tab_f2);

    // =========================================================================
    // Test 21: Blank File Creation (Running with no arguments)
    // =========================================================================
    printf("\n[TEST 21] Testing blank file creation (untitled.bin)...\n");
    assert(file_create_blank() == 0);
    assert(file_size == 0);
    assert(file_capacity >= 65536);
    assert(file_ptr != NULL);
    assert(strcmp(file_path, "untitled.bin") == 0);
    printf("  -> Blank file created: 0 bytes, capacity %lu bytes, path '%s'.\n", file_capacity, file_path);

    // Write bytes in blank file using ASCII pane
    editor_init();
    active_pane = 1; // PANE_ASCII
    char test_msg[] = "AsmHexPureAssembly";
    for (int i = 0; i < (int)strlen(test_msg); i++) {
        char c = test_msg[i];
        editor_handle_key(0, &c, 1, 0);
    }
    assert(file_size == strlen(test_msg));
    assert(memcmp(file_ptr, test_msg, file_size) == 0);
    printf("  -> Wrote %lu bytes into blank buffer: '%s'.\n", file_size, test_msg);

    // Save blank file to disk as untitled.bin
    remove("untitled.bin");
    assert(file_save() == 0);
    printf("  -> Ctrl+S save executed successfully.\n");

    // Verify file on disk
    FILE *check_fp = fopen("untitled.bin", "rb");
    assert(check_fp != NULL);
    fseek(check_fp, 0, SEEK_END);
    long sz_disk = ftell(check_fp);
    assert(sz_disk == (long)strlen(test_msg));
    fseek(check_fp, 0, SEEK_SET);
    char disk_buf[32] = {0};
    assert(fread(disk_buf, 1, sz_disk, check_fp) == (size_t)sz_disk);
    assert(strcmp(disk_buf, test_msg) == 0);
    fclose(check_fp);
    remove("untitled.bin");
    file_close();
    printf("  -> Verified untitled.bin on disk matched bit-for-bit with written content.\n");

    // =========================================================================
    // Test 22: Appending Bytes past EOF (Dynamic File Resizing)
    // =========================================================================
    printf("\n[TEST 22] Testing appending bytes at EOF in Hex and ASCII panes...\n");
    assert(file_create_blank() == 0);
    editor_init();

    // 1. Append in Hex pane: type '4' then '2' -> byte 0x42 ('B')
    active_pane = 0; // PANE_HEX
    cursor_offset = 0;
    nibble_index = 0;
    char k4 = '4';
    editor_handle_key(0, &k4, 1, 0);
    assert(file_size == 1);
    assert(cursor_offset == 0 && nibble_index == 1);
    assert(file_ptr[0] == 0x40);

    char k2 = '2';
    editor_handle_key(0, &k2, 1, 0);
    assert(file_size == 1);
    assert(cursor_offset == 1 && nibble_index == 0); // Cursor advanced to EOF
    assert(file_ptr[0] == 0x42);
    printf("  -> Appended byte 0x42 ('B') at EOF in Hex pane: file_size = %lu, cursor = %lu.\n", file_size, cursor_offset);

    // Append second byte 'a' then 'f' -> byte 0xAF
    char ka = 'a';
    editor_handle_key(0, &ka, 1, 0);
    assert(file_size == 2);
    assert(cursor_offset == 1 && nibble_index == 1);
    assert(file_ptr[1] == 0xa0);

    char kf = 'f';
    editor_handle_key(0, &kf, 1, 0);
    assert(file_size == 2);
    assert(cursor_offset == 2 && nibble_index == 0);
    assert(file_ptr[1] == 0xaf);
    printf("  -> Appended byte 0xAF at EOF in Hex pane: file_size = %lu, cursor = %lu.\n", file_size, cursor_offset);

    // 2. Append in ASCII pane: switch to ASCII and type 'X', 'Y', 'Z'
    active_pane = 1; // PANE_ASCII
    char kx = 'X';
    editor_handle_key(0, &kx, 1, 0);
    assert(file_size == 3 && cursor_offset == 3);
    assert(file_ptr[2] == 'X');

    char ky = 'Y';
    editor_handle_key(0, &ky, 1, 0);
    assert(file_size == 4 && cursor_offset == 4);
    assert(file_ptr[3] == 'Y');

    char kz = 'Z';
    editor_handle_key(0, &kz, 1, 0);
    assert(file_size == 5 && cursor_offset == 5);
    assert(file_ptr[4] == 'Z');
    printf("  -> Appended 'XYZ' in ASCII pane: file_size = %lu, cursor = %lu.\n", file_size, cursor_offset);

    // Verify navigation does not exceed EOF
    editor_next_byte();
    assert(cursor_offset == 5); // Clamped to EOF
    editor_move_down();
    assert(cursor_offset == 5); // Clamped to EOF
    printf("  -> Verified cursor navigation clamps cleanly at EOF.\n");
    file_close();

    // =========================================================================
    // Test 23: Copy-on-Write Memory Safety (Exit without Ctrl+S leaves disk intact)
    // =========================================================================
    printf("\n[TEST 23] Testing copy-on-write unsaved exit (no disk modification without Ctrl+S)...\n");
    const char *cow_file = "/tmp/asmhex_cow_test.dat";
    FILE *cow_fp = fopen(cow_file, "wb");
    assert(cow_fp != NULL);
    uint8_t orig_bytes[32];
    memset(orig_bytes, 0x55, sizeof(orig_bytes));
    fwrite(orig_bytes, 1, sizeof(orig_bytes), cow_fp);
    fclose(cow_fp);

    // Open file, modify memory bytes, and close without file_save()
    assert(file_open(cow_file) == 0);
    assert(file_size == 32);
    file_ptr[0] = 0xAA;
    file_ptr[15] = 0xBB;
    file_ptr[31] = 0xCC;
    assert(file_ptr[0] == 0xAA && file_ptr[15] == 0xBB && file_ptr[31] == 0xCC);

    // Close application (simulates Ctrl+Q without saving)
    file_close();

    // Verify disk file is 100% UNTOUCHED
    cow_fp = fopen(cow_file, "rb");
    assert(cow_fp != NULL);
    uint8_t disk_verify[32] = {0};
    assert(fread(disk_verify, 1, 32, cow_fp) == 32);
    fclose(cow_fp);
    assert(memcmp(disk_verify, orig_bytes, 32) == 0);
    remove(cow_file);
    printf("  -> Verified disk file remained 100%% untouched after unsaved edits.\n");

    // =========================================================================
    // Test 24: Command-Line Diff Invocation & editor_init Protection
    // =========================================================================
    printf("\n[TEST 24] Testing Command-Line Diff Mode invocation (Method 1 & 2)...\n");
    const char *diff_f1 = "/tmp/asmhex_cli_diff1.dat";
    const char *diff_f2 = "/tmp/asmhex_cli_diff2.dat";
    FILE *df1 = fopen(diff_f1, "wb");
    FILE *df2 = fopen(diff_f2, "wb");
    assert(df1 && df2);
    uint8_t buf1[64], buf2[64];
    memset(buf1, 0x10, 64);
    memset(buf2, 0x10, 64);
    buf2[5] = 0x99;
    buf2[20] = 0x88;
    fwrite(buf1, 1, 64, df1);
    fwrite(buf2, 1, 64, df2);
    fclose(df1);
    fclose(df2);

    // Method 1: ./asmhex file1 file2
    editor_init();
    assert(file_open(diff_f1) == 0);
    assert(file2_open(diff_f2) == 0);
    is_diff_mode = 1;
    diff_recompute();

    // Crucial check: verify calling editor_init() does not wipe is_diff_mode
    editor_init();
    assert(is_diff_mode == 1);
    assert(diff_count == 2);
    printf("  -> Verified editor_init() preserved is_diff_mode = 1 (Method 1 & 2 protected).\n");

    file2_close();
    file_close();
    remove(diff_f1);
    remove(diff_f2);

    // =========================================================================
    // Test 25: Drag-Drop Blank Buffer Replacement & Empty File diff_recompute (Segfault Prevention)
    // =========================================================================
    printf("\n[TEST 25] Testing Drag & Drop blank buffer replacement & empty file diff_recompute...\n");
    const char *drop_test_file = "/tmp/asmhex_drop_target.dat";
    FILE *dtfp = fopen(drop_test_file, "wb");
    assert(dtfp != NULL);
    uint8_t drop_bytes[16];
    for (int i = 0; i < 16; i++) drop_bytes[i] = (uint8_t)(0x10 + i);
    fwrite(drop_bytes, 1, 16, dtfp);
    fclose(dtfp);

    // 1. Start with blank file (file_create_blank)
    assert(file_create_blank() == 0);
    assert(file_size == 0);
    assert(file_fd == -1);
    assert(is_dirty == 0);
    assert(is_scratch == 0);

    // 2. Direct verification of diff_recompute() with 0-byte file1 vs 16-byte file2 (Segfault regression test)
    assert(file2_open(drop_test_file) == 0);
    is_diff_mode = 1;
    diff_recompute(); // This previously crashed with SIGSEGV due to uninitialized r10 in .dr_tail_loop
    assert(diff_count == 16);
    assert(diff_list_count == 16);
    assert(diff_list[0] == 0);
    assert(diff_list[15] == 15);
    printf("  -> Verified diff_recompute() handles 0-byte buffer vs loaded file2 with 0 crashes (diff_count = %lu).\n", diff_count);
    file2_close();
    is_diff_mode = 0;

    // 3. Test reverse: 16-byte file1 vs 0-byte file2
    assert(file_open(drop_test_file) == 0);
    assert(file_size == 16);
    assert(file_create_blank() == 0); // resets file1 to 0 bytes
    // Test diff_recompute with both files 0-byte
    is_diff_mode = 1;
    diff_recompute();
    assert(diff_count == 0);
    printf("  -> Verified diff_recompute() handles 0-byte vs 0-byte cleanly (diff_count = 0).\n");
    is_diff_mode = 0;

    // 4. Simulate XDnD drop dispatch onto blank buffer:
    // When file_fd == -1 && is_dirty == 0 && file_size == 0, dropping a file replaces blank buffer as File 1
    int should_replace = (is_diff_mode == 0) && (is_scratch == 1 || (file_fd == -1 && is_dirty == 0 && file_size == 0));
    assert(should_replace == 1);
    file2_close();
    is_diff_mode = 0;
    file_close();
    assert(file_open(drop_test_file) == 0);
    assert(file_size == 16);
    assert(file_fd >= 0);
    editor_init();
    assert(cursor_offset == 0);
    assert(is_diff_mode == 0);
    printf("  -> Verified dropping file onto blank buffer cleanly opens file as primary File 1 (size = %lu).\n", file_size);

    file_close();
    remove(drop_test_file);

    // =========================================================================
    // Test 26: Save As Functionality (file_save_as & MODE_SAVE_AS)
    // =========================================================================
    printf("\n[TEST 26] Testing Save As functionality (file_save_as & MODE_SAVE_AS)...\n");
    const char *save_as_path = "/tmp/asmhex_save_as_target.bin";
    remove(save_as_path);

    // 1. Create a blank file and write data into it
    assert(file_create_blank() == 0);
    const char *sa_test_msg = "AsmHexSaveAsTestContent";
    int sa_msg_len = (int)strlen(sa_test_msg);
    memcpy(file_ptr, sa_test_msg, sa_msg_len);
    file_size = sa_msg_len;
    is_dirty = 1;

    // 2. Invoke Save As modal
    editor_start_save_as();
    assert(editor_mode == 3); // MODE_SAVE_AS
    assert(input_len > 0); // prefilled with untitled.bin

    // 3. User types new file path into input_buf
    strncpy(input_buf, save_as_path, sizeof(input_buf) - 1);
    input_buf[sizeof(input_buf) - 1] = '\0';
    input_len = (uint32_t)strlen(input_buf);

    // 4. Commit Save As
    editor_commit_save_as();
    assert(editor_mode == 0); // MODE_NORMAL
    assert(is_dirty == 0);
    assert(is_scratch == 0);
    assert(strcmp(file_path, save_as_path) == 0);

    // 5. Verify saved file on disk
    FILE *safp = fopen(save_as_path, "rb");
    assert(safp != NULL);
    char sa_read_back[64] = {0};
    size_t nread = fread(sa_read_back, 1, sizeof(sa_read_back) - 1, safp);
    fclose(safp);
    assert((int)nread == sa_msg_len);
    assert(memcmp(sa_read_back, sa_test_msg, sa_msg_len) == 0);
    printf("  -> Verified Save As successfully wrote %d bytes to '%s' with exact matching content.\n", sa_msg_len, save_as_path);

    file_close();
    remove(save_as_path);

    // =========================================================================
    // Test 27: 32-bit (4-byte) Addresses & 4 GiB Limit Enforcement
    // =========================================================================
    printf("\n[TEST 27] Testing 32-bit (4-byte) addresses and 4 GiB size enforcement...\n");
    char hex_dword_buf[16] = {0};
    format_hex_dword(hex_dword_buf, 0x12345678);
    assert(strcmp(hex_dword_buf, "12345678") == 0);
    assert(strlen(hex_dword_buf) == 8);
    printf("  -> Verified format_hex_dword produced 8 hex characters: '%s'.\n", hex_dword_buf);

    // Verify 32-bit offset layout geometry
    editor_init();
    assert(cur_offset_x == 16);
    assert(cur_gutter_sep_x == 88);
    assert(cur_hex_start_x == 100);

    // Verify 4 GiB limit rejection in file_ensure_capacity
    file_create_scratch();
    int cap_err = file_ensure_capacity(0x100000001ULL); // 4 GiB + 1
    assert(cap_err < 0);
    file_close();
    printf("  -> Verified 4 GiB capacity ceiling rejects allocations > 4 GiB (code %d).\n", cap_err);

    // =========================================================================
    // Test 28: Text Scaling (Ctrl + / Ctrl -) & Dynamic Layout Engine
    // =========================================================================
    printf("\n[TEST 28] Testing Text Scaling (Ctrl + / Ctrl -) & Dynamic Layout...\n");
    editor_init();
    assert(font_scale == 1);
    assert(cur_char_w == 8 && row_h == 16);
    assert(cur_hex_start_x == 100 && cur_byte_spacing == 24);

    // Zoom In
    editor_zoom_in();
    assert(font_scale == 2);
    assert(cur_char_w == 16 && row_h == 32);
    assert(cur_offset_x == 32);
    assert(cur_gutter_sep_x == 176);
    assert(cur_hex_start_x == 200);
    assert(cur_byte_spacing == 48);
    assert(cur_group_gap == 24);
    assert(cur_hex_end_x == 976);
    assert(cur_ascii_sep_x == 1000);
    assert(cur_ascii_start_x == 1032);
    assert(cur_ascii_end_x == 1288);
    printf("  -> Verified editor_zoom_in() scaled font to 2x (16x32) and updated all layout coordinates.\n");

    // Zoom In again (must clamp at max scale 2)
    editor_zoom_in();
    assert(font_scale == 2);

    // Test 2x Rendering with Double-Scanline SSE2 Blitter
    file_create_scratch();
    file_ptr[0] = 0x55;
    uint32_t *scale_fb = malloc(1920 * 1080 * 4);
    assert(scale_fb != NULL);
    fb_data = scale_fb;
    win_w = 1920;
    win_h = 1080;
    fb_pitch = 1920 * 4;
    editor_render();
    // Verify that at row 0 (y = 56 + 6 = 62), glyph spans 32 scanlines (up to y = 93)
    uint32_t scale_pix_count = 0;
    for (int y = 62; y < 94; y++) {
        for (int x = 200; x < 232; x++) {
            if (scale_fb[y * 1920 + x] != 0x001E1E2E) {
                scale_pix_count++;
            }
        }
    }
    assert(scale_pix_count > 60);
    printf("  -> Verified 2x rendering: 16x32 double-scanline blit verified (%u active pixels).\n", scale_pix_count);
    free(scale_fb);
    file_close();

    // Zoom Out
    editor_zoom_out();
    assert(font_scale == 1);
    assert(cur_char_w == 8 && row_h == 16);
    assert(cur_hex_start_x == 100 && cur_byte_spacing == 24);
    printf("  -> Verified editor_zoom_out() scaled font back to 1x (8x16).\n");

    // Zoom Out again (must clamp at min scale 1)
    editor_zoom_out();
    assert(font_scale == 1);

    // Verify keyboard hotkey dispatch for text zoom:
    // Ctrl + (XK_plus with state 4) -> font_scale 2
    editor_handle_key(XK_plus, "+", 1, 4);
    assert(font_scale == 2);
    // Ctrl - (XK_minus with state 4) -> font_scale 1
    editor_handle_key(XK_minus, "-", 1, 4);
    assert(font_scale == 1);
    // Ctrl = (XK_equal with state 4) -> font_scale 2
    editor_handle_key(XK_equal, "=", 1, 4);
    assert(font_scale == 2);
    // Ctrl 0 (reset) -> font_scale 1
    editor_handle_key('0', "0", 1, 4);
    assert(font_scale == 1);
    printf("  -> Verified Ctrl+ / Ctrl- / Ctrl= / Ctrl 0 keyboard shortcuts.\n");

    // =========================================================================
    // Test 29: Unsaved Changes Quit Warning Modal (Ctrl+Q & Window Close)
    // =========================================================================
    printf("\n[TEST 29] Testing Unsaved Changes Quit Warning Modal...\n");
    assert(file_create_blank() == 0);
    editor_init();
    assert(is_dirty == 0);

    // Case 1: When file is clean, Ctrl+Q quits immediately (returns 1)
    int q_ret = editor_handle_key('q', "q", 1, 4); // Ctrl+Q
    assert(q_ret == 1);
    assert(editor_mode == 0);
    printf("  -> Clean file: Ctrl+Q quits immediately (return code 1).\n");

    // Case 2: When file has unsaved changes (is_dirty == 1), Ctrl+Q warns (returns 0, MODE_CONFIRM_QUIT)
    is_dirty = 1;
    q_ret = editor_handle_key('q', "q", 1, 4); // Ctrl+Q
    assert(q_ret == 0);
    assert(editor_mode == 4); // MODE_CONFIRM_QUIT
    printf("  -> Unsaved changes: Ctrl+Q intercepts quit and activates MODE_CONFIRM_QUIT warning modal.\n");

    // Case 3: Cancel quit prompt with 'Esc'
    int c_ret = editor_handle_key(XK_Escape, "", 0, 0);
    assert(c_ret == 0);
    assert(editor_mode == 0); // returns to MODE_NORMAL
    assert(is_dirty == 1);    // file still dirty
    printf("  -> Pressing Esc cancels quit prompt and returns to editing.\n");

    // Case 4: Discard changes with 'n'
    editor_handle_key('q', "q", 1, 4);
    assert(editor_mode == 4);
    int n_ret = editor_handle_key('n', "n", 1, 0); // 'n' to discard
    assert(n_ret == 1); // quits discarding changes
    printf("  -> Pressing 'n' discards changes and confirms quit (return code 1).\n");

    // Case 5: Save and quit with 'y'
    file_close();
    const char *save_quit_path = "/tmp/asmhex_save_quit.dat";
    FILE *sqfp = fopen(save_quit_path, "wb");
    assert(sqfp != NULL);
    fputs("InitialData", sqfp);
    fclose(sqfp);

    assert(file_open(save_quit_path) == 0);
    editor_init();
    file_ptr[0] = 'X'; // modify
    is_dirty = 1;

    editor_handle_key('q', "q", 1, 4); // Ctrl+Q
    assert(editor_mode == 4);
    int y_ret = editor_handle_key('y', "y", 1, 0); // 'y' to save & quit
    assert(y_ret == 1); // saved & quit
    assert(is_dirty == 0);

    // Verify on disk
    sqfp = fopen(save_quit_path, "rb");
    assert(sqfp != NULL);
    char sq_buf[16] = {0};
    size_t sq_n = fread(sq_buf, 1, sizeof(sq_buf) - 1, sqfp);
    assert(sq_n > 0);
    fclose(sqfp);
    assert(sq_buf[0] == 'X');
    printf("  -> Pressing 'y' saved changes to disk and confirmed quit (return code 1).\n");

    file_close();
    remove(save_quit_path);

    // Test 30: 2x Scale Spacing, Non-Overlapping Panels & Save As Shortcuts Display
    printf("\n[TEST 30] Testing 2x Scale Spacing & Non-Overlapping Inspector Layout...\n");
    editor_init();
    assert(font_scale == 1);
    assert(cur_scrollbar_x == 722);
    assert(cur_scrollbar_w == 10);
    assert(cur_data_pane_w == 734);
    assert(cur_panel_divider_x == 736);
    assert(cur_inspector_x == 744);
    assert(cur_line_h == 18);
    assert(cur_insp_col_val == 144);
    assert(cur_header_h == 32);
    assert(cur_col_hdr_h == 20);
    assert(cur_separator_y == 52);
    assert(cur_status_h == 72);

    // Zoom to 2x
    editor_zoom_in();
    assert(font_scale == 2);
    assert(cur_scrollbar_x == 1444);
    assert(cur_scrollbar_w == 20);
    assert(cur_data_pane_w == 1468);
    assert(cur_panel_divider_x == 1472);
    assert(cur_inspector_x == 1488);
    assert(cur_line_h == 36);
    assert(cur_insp_col_val == 288);
    assert(cur_header_h == 64);
    assert(cur_col_hdr_h == 40);
    assert(cur_separator_y == 104);
    assert(cur_status_h == 144);

    // 1. Verify editor pane and right pane have zero overlap
    assert(cur_ascii_end_x < cur_scrollbar_x);
    assert(cur_scrollbar_x + cur_scrollbar_w < cur_panel_divider_x);
    assert(cur_panel_divider_x < cur_inspector_x);
    printf("  -> Verified 2x panel separation: ASCII end (%d) < Scrollbar (%d) < Divider (%d) < Inspector (%d).\n",
           cur_ascii_end_x, cur_scrollbar_x, cur_panel_divider_x, cur_inspector_x);

    // 2. Verify vertical line spacing: line height (36) > 2x font height (32)
    assert(cur_line_h > 32);
    printf("  -> Verified 2x line spacing: line_h = %d px > 32 px font height (clean 4 px vertical line gap).\n", cur_line_h);

    // 3. Verify horizontal column gap: inspector value offset (288) > longest label (224)
    assert(cur_insp_col_val >= 288);
    printf("  -> Verified 2x column spacing: label-value offset = %d px (fits 14-char labels with >64 px padding).\n", cur_insp_col_val);

    // 4. Verify shortcut string contains Ctrl+Shift+S for Save As
    assert(strcmp(insp_h_save_as, "Ctrl+Shift+S : Save As...") == 0);
    printf("  -> Verified shortcut string: '%s'.\n", insp_h_save_as);

    // 5. Test rendering frame at 2x scale
    file_create_scratch();
    file_ptr[0] = 0x7E;
    uint32_t *test_fb30 = malloc(1920 * 1080 * 4);
    assert(test_fb30 != NULL);
    fb_data = test_fb30;
    win_w = 1920;
    win_h = 1080;
    fb_pitch = 1920 * 4;
    editor_render();

    // Verify Inspector Title is rendered at cur_inspector_x (1488)
    int insp_pix = 0;
    for (int y = 64; y < 104; y++) {
        for (int x = 1488; x < 1800; x++) {
            if (test_fb30[y * 1920 + x] != 0x00181825) insp_pix++;
        }
    }
    assert(insp_pix > 200);
    printf("  -> Verified 2x Inspector Title rendered at x = %d (%d active pixels).\n", cur_inspector_x, insp_pix);

    free(test_fb30);
    file_close();

    // Zoom back out to 1x
    editor_zoom_out();
    assert(font_scale == 1);
    assert(cur_scrollbar_x == 722);
    assert(cur_panel_divider_x == 736);
    assert(cur_inspector_x == 744);
    assert(cur_line_h == 18);
    printf("  -> Verified zoom out restored 1x geometry cleanly.\n");

    printf("\n========================================================\n");
    printf("  ALL 30 CORE FUNCTIONALITY TESTS PASSED WITH 100%% SUCCESS!\n");
    printf("========================================================\n");
    return 0;
}
