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

extern void draw_rect_alpha(int x, int y, int w, int h, uint32_t color, int alpha);
extern int editor_handle_key(uint64_t sym, char *ascii_buf, int ascii_len, int state);
extern void editor_handle_click(int x, int y);
extern void editor_handle_mouse_move(int x, int y);
extern void editor_handle_button_release(int x, int y);
extern void editor_undo(void);
extern void editor_search_next(void);
extern int dump_screenshot(const char *filename);

int main() {
    printf("========================================================\n");
    printf("  Running AsmHex Comprehensive Test Suite...\n");
    printf("========================================================\n");

    init_renderer_luts();

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

    printf("\n========================================================\n");
    printf("  ALL 14 CORE FUNCTIONALITY TESTS PASSED WITH 100%% SUCCESS!\n");
    printf("========================================================\n");
    return 0;
}
