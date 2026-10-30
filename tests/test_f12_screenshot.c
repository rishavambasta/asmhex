#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern void init_renderer_luts(void);
extern void init_crc32_table(void);
extern void editor_init(void);
extern void editor_render(void);
extern int file_create_scratch(void);
extern void file_close(void);
extern int dump_screenshot(const char *path);
extern void editor_handle_key(uint64_t sym, char *ascii_buf, int ascii_len, int state);

extern uint32_t *fb_data;
extern int32_t win_w;
extern int32_t win_h;
extern int32_t fb_pitch;
extern uint8_t *file_ptr;
extern uint64_t file_size;
extern uint64_t sel_start;
extern uint64_t sel_end;
extern uint32_t has_selection;

int main() {
    init_renderer_luts();
    init_crc32_table();

    uint32_t *fb = malloc(1040 * 720 * 4);
    fb_data = fb;
    win_w = 1040;
    win_h = 720;
    fb_pitch = 1040 * 4;

    file_create_scratch();
    editor_init();

    // Populate buffer with realistic pattern
    for (int i = 0; i < 512; i++) {
        file_ptr[i] = (uint8_t)((i * 7 + 0x1F) & 0xFF);
    }
    const char *sig = "AsmHex Fast Pure x86_64 Engine!";
    memcpy(file_ptr + 32, sig, strlen(sig));

    // Select range 0x20 .. 0x7F (96 bytes)
    has_selection = 1;
    sel_start = 0x20;
    sel_end = 0x7F;

    // Trigger F12 (XK_F12 = 0xFFC9)
    editor_handle_key(0xFFC9, NULL, 0, 0);

    // Render frame
    editor_render();

    // Dump screenshot
    dump_screenshot("f12_checksum_demo.ppm");
    printf("Saved f12_checksum_demo.ppm successfully!\n");

    free(fb);
    file_close();
    return 0;
}
