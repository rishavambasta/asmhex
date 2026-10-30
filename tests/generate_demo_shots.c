#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <X11/keysym.h>

extern void init_renderer_luts(void);
extern void init_crc32_table(void);
extern void editor_init(void);
extern void editor_render(void);
extern int file_open(const char *path);
extern int file2_open(const char *path);
extern void file_close(void);
extern void file2_close(void);
extern int dump_screenshot(const char *filename);
extern int editor_handle_key(uint64_t sym, char *ascii_buf, int ascii_len, int state);

extern uint32_t win_w;
extern uint32_t win_h;
extern void *fb_data;
extern uint32_t fb_pitch;
extern uint32_t is_diff_mode;
extern uint64_t diff_count;
extern void diff_recompute(void);

int main() {
    init_renderer_luts();
    init_crc32_table();

    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;
    fb_data = malloc(1040 * 720 * 4);

    // 1. Generate Tabbed Diff View Shot
    file_open("test_data/firmware_v1.bin");
    file2_open("test_data/firmware_v2.bin");
    editor_init();
    is_diff_mode = 1;
    diff_recompute();

    // Jump to first difference using F3 key
    editor_handle_key(XK_F3, NULL, 0, 0);

    editor_render();
    dump_screenshot("diff_shot.ppm");
    dump_screenshot("asmhex_tabbed_diff_demo.ppm");

    // 2. Generate Tab 2 Active Shot (press F2)
    editor_handle_key(XK_F2, NULL, 0, 0);
    editor_render();
    dump_screenshot("asmhex_tab2_active_demo.ppm");

    // Toggle back to Tab 1
    editor_handle_key(XK_F2, NULL, 0, 0);

    // 2. Generate Keyboard Selection & F12 Checksum Shot
    // Use Shift+Right and Shift+Down to select a range from 0x00 to 0x3F (64 bytes)
    for (int i = 0; i < 3; i++) {
        editor_handle_key(XK_Down, NULL, 0, 1); // Shift+Down
    }
    for (int i = 0; i < 15; i++) {
        editor_handle_key(XK_Right, NULL, 0, 1); // Shift+Right
    }

    // Press F12 to compute Checksums
    editor_handle_key(XK_F12, NULL, 0, 0);

    editor_render();
    dump_screenshot("selection_f12_diff_shot.ppm");

    file2_close();
    file_close();
    free(fb_data);

    // 3. Generate Resized Window Shot (1360x860) showing scaled layout & more visible rows
    win_w = 1360;
    win_h = 860;
    fb_pitch = 1360 * 4;
    fb_data = malloc(1360 * 860 * 4);
    file_open("test_data/firmware_v1.bin");
    editor_init();
    editor_render();
    dump_screenshot("asmhex_resized_window.ppm");
    file_close();
    free(fb_data);

    printf("Generated demo screenshots successfully!\n");
    return 0;
}
