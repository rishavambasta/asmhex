#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>
#include <X11/Xlib.h>

extern int x11_init(const char *title, int w, int h);
extern int x11_resize(int new_w, int new_h);
extern void x11_flush(void);
extern void x11_cleanup(void);
extern void editor_init(void);
extern void editor_update_geometry(void);
extern void editor_render(void);
extern int file_create_scratch(void);
extern uint32_t win_w, win_h, visible_rows, visible_bytes;
extern void *fb_data;

int main() {
    printf("Starting live X11 resize verification...\n");
    file_create_scratch();
    editor_init();

    int res = x11_init("AsmHex Live Resize Test", 1040, 720);
    if (res != 0) {
        printf("Notice: x11_init returned %d (DISPLAY unreachable); skipping live X11 test.\n", res);
        return 0;
    }
    editor_update_geometry();
    printf("1. Initial window: %ux%u, visible_rows=%u, visible_bytes=%u\n",
           win_w, win_h, visible_rows, visible_bytes);
    assert(win_w == 1040 && win_h == 720);
    assert(visible_rows == 36);

    editor_render();
    x11_flush();

    // Resize 1: expand to 1600x900
    printf("2. Resizing to 1600x900...\n");
    int r = x11_resize(1600, 900);
    assert(r == 0);
    editor_update_geometry();
    assert(win_w == 1600 && win_h == 900);
    assert(visible_rows == 47); // (900 - 140) / 16 = 47
    editor_render();
    x11_flush();
    printf("   -> 1600x900 successfully rendered! visible_rows=%u\n", visible_rows);

    // Resize 2: shrink to 800x600
    printf("3. Resizing to 800x600...\n");
    r = x11_resize(800, 600);
    assert(r == 0);
    editor_update_geometry();
    assert(win_w == 800 && win_h == 600);
    assert(visible_rows == 28); // (600 - 140) / 16 = 28
    editor_render();
    x11_flush();
    printf("   -> 800x600 successfully rendered! visible_rows=%u\n", visible_rows);

    // Resize 3: expand to 1920x1080
    printf("4. Resizing to 1920x1080...\n");
    r = x11_resize(1920, 1080);
    assert(r == 0);
    editor_update_geometry();
    assert(win_w == 1920 && win_h == 1080);
    assert(visible_rows == 58); // (1080 - 140) / 16 = 58
    editor_render();
    x11_flush();
    printf("   -> 1920x1080 successfully rendered! visible_rows=%u\n", visible_rows);

    x11_cleanup();
    printf("Live X11 resize test completed successfully!\n");
    return 0;
}
