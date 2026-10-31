/* ==============================================================================
 * AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
 * win32_host.c - Thin Win32 Platform Host for Windows 64-bit Port
 * ============================================================================== */

#define _WIN32_WINNT 0x0601 // Windows 7 or higher
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>

/* X11-compatible KeySyms and modifier masks expected by core assembly */
#define XK_BackSpace        0xFF08
#define XK_Tab              0xFF09
#define XK_Return           0xFF0D
#define XK_Escape           0xFF1B
#define XK_Home             0xFF50
#define XK_Left             0xFF51
#define XK_Up               0xFF52
#define XK_Right            0xFF53
#define XK_Down             0xFF54
#define XK_Page_Up          0xFF55
#define XK_Page_Down        0xFF56
#define XK_End              0xFF57
#define XK_Delete           0xFFFF
#define XK_F1               0xFFBE
#define XK_F2               0xFFBF
#define XK_F3               0xFFC0
#define XK_F7               0xFFC4
#define XK_F8               0xFFC5
#define XK_F11              0xFFC8
#define XK_F12              0xFFC9
#define XK_KP_Add           0xFFAB
#define XK_KP_Subtract      0xFFAD
#define XK_KP_0             0xFFB0

#define ShiftMask           (1 << 0)
#define ControlMask         (1 << 2)

#define MODE_NORMAL         0
#define MODE_GOTO           1
#define MODE_SEARCH         2
#define MODE_SAVE_AS        3
#define MODE_CONFIRM_QUIT   4

#define WIN_DEFAULT_W       1040
#define WIN_DEFAULT_H       720

/* ------------------------------------------------------------------------------
 * Global State Exported to Core Assembly
 * ------------------------------------------------------------------------------ */
int32_t win_w = WIN_DEFAULT_W;
int32_t win_h = WIN_DEFAULT_H;
void *fb_data = NULL;
uint64_t fb_pitch = WIN_DEFAULT_W * 4;

uint8_t *file_ptr = NULL;
uint64_t file_size = 0;
uint64_t file_capacity = 0;
int32_t file_fd = -1;
int32_t is_readonly = 0;
int32_t is_scratch = 0;
char file_path[512] = {0};

uint8_t *file2_ptr = NULL;
uint64_t file2_size = 0;
uint64_t file2_capacity = 0;
int32_t file2_fd = -1;
int32_t is_readonly2 = 0;
char file2_path[512] = {0};

/* State Imported from Core Assembly */
extern int32_t is_dirty;
extern int32_t is_diff_mode;
extern int32_t diff_active_file;
extern int32_t font_scale;
extern int32_t editor_mode;

/* Functions in Core Assembly (System V AMD64 ABI) */
extern __attribute__((sysv_abi)) void init_renderer_luts(void);
extern __attribute__((sysv_abi)) void init_crc32_table(void);
extern __attribute__((sysv_abi)) void editor_init(void);
extern __attribute__((sysv_abi)) void editor_update_geometry(void);
extern __attribute__((sysv_abi)) void editor_render(void);
extern __attribute__((sysv_abi)) void editor_ensure_visible(void);
extern __attribute__((sysv_abi)) int  editor_handle_key(uint64_t keysym, const char *ascii_buf, int ascii_len, uint32_t state);
extern __attribute__((sysv_abi)) void editor_handle_click(int x, int y, int button);
extern __attribute__((sysv_abi)) void editor_handle_mouse_move(int x, int y);
extern __attribute__((sysv_abi)) void editor_handle_button_release(int x, int y, int button);
extern __attribute__((sysv_abi)) void editor_handle_wheel(int button);
extern __attribute__((sysv_abi)) void editor_set_status(const char *msg, uint32_t color);
extern __attribute__((sysv_abi)) void editor_prompt_confirm_quit(void);
extern __attribute__((sysv_abi)) void diff_recompute(void);

/* ------------------------------------------------------------------------------
 * System V AMD64 ABI Bridges for Standard C Library Calls from Core Assembly
 * ------------------------------------------------------------------------------ */
__attribute__((sysv_abi))
int host_snprintf(char *str, size_t size, const char *fmt, void *a1, void *a2, void *a3) {
    return snprintf(str, size, fmt, a1, a2, a3);
}

__attribute__((sysv_abi))
int host_printf(const char *fmt, void *a1, void *a2, void *a3, void *a4, void *a5) {
    return printf(fmt, a1, a2, a3, a4, a5);
}

__attribute__((sysv_abi))
size_t host_strlen(const char *s) {
    return strlen(s);
}

/* ------------------------------------------------------------------------------
 * PPM Screenshot Exporter
 * ------------------------------------------------------------------------------ */
__attribute__((sysv_abi))
int dump_screenshot(const char *filename) {
    if (!filename || !fb_data || win_w <= 0 || win_h <= 0) return -1;
    FILE *fp = fopen(filename, "wb");
    if (!fp) return -1;
    fprintf(fp, "P6\n%d %d\n255\n", win_w, win_h);
    uint8_t *line_buf = (uint8_t *)malloc(win_w * 3);
    if (!line_buf) { fclose(fp); return -1; }
    for (int y = 0; y < win_h; y++) {
        uint32_t *src = (uint32_t *)((uint8_t *)fb_data + y * fb_pitch);
        uint8_t *dst = line_buf;
        for (int x = 0; x < win_w; x++) {
            uint32_t pix = src[x];
            *dst++ = (pix >> 16) & 0xFF; // R
            *dst++ = (pix >> 8) & 0xFF;  // G
            *dst++ = pix & 0xFF;         // B
        }
        fwrite(line_buf, 1, win_w * 3, fp);
    }
    free(line_buf);
    fclose(fp);
    return 0;
}

/* ------------------------------------------------------------------------------
 * Win32 File Management Functions (System V AMD64 ABI for Assembly Callers)
 * ------------------------------------------------------------------------------ */
__attribute__((sysv_abi))
void file_close(void) {
    if (file_ptr) {
        free(file_ptr);
        file_ptr = NULL;
    }
    file_size = 0;
    file_capacity = 0;
    file_fd = -1;
}

__attribute__((sysv_abi))
int64_t file_open(const char *path) {
    if (!path || !path[0]) return -1;
    file_close();

    strncpy(file_path, path, sizeof(file_path) - 1);
    file_path[sizeof(file_path) - 1] = '\0';

    FILE *fp = fopen(path, "rb");
    if (!fp) return -1;

    _fseeki64(fp, 0, SEEK_END);
    int64_t sz = _ftelli64(fp);
    _fseeki64(fp, 0, SEEK_SET);

    if (sz < 0 || (uint64_t)sz > 4294967296ULL) { // 4 GiB max
        fclose(fp);
        return -4;
    }

    uint64_t cap = (uint64_t)sz + 65536;
    if (cap < 65536) cap = 65536;
    cap = (cap + 4095) & ~4095ULL;

    uint8_t *buf = (uint8_t *)calloc(1, cap);
    if (!buf) {
        fclose(fp);
        return -3;
    }

    if (sz > 0) {
        fread(buf, 1, (size_t)sz, fp);
    }
    fclose(fp);

    file_ptr = buf;
    file_size = (uint64_t)sz;
    file_capacity = cap;
    file_fd = 1;
    is_readonly = 0;
    is_scratch = 0;
    is_dirty = 0;
    return 0;
}

__attribute__((sysv_abi))
int64_t file_create_blank(void) {
    file_close();
    uint64_t cap = 65536;
    uint8_t *buf = (uint8_t *)calloc(1, cap);
    if (!buf) return -1;

    file_ptr = buf;
    file_size = 0;
    file_capacity = cap;
    file_fd = -1;
    is_readonly = 0;
    is_scratch = 1;
    is_dirty = 0;
    strcpy(file_path, "untitled.bin");
    return 0;
}

__attribute__((sysv_abi))
int64_t file_create_scratch(uint64_t size) {
    file_close();
    if (size == 0) size = 4096;
    uint64_t cap = (size + 4095) & ~4095ULL;
    uint8_t *buf = (uint8_t *)calloc(1, cap);
    if (!buf) return -1;

    file_ptr = buf;
    file_size = size;
    file_capacity = cap;
    file_fd = -1;
    is_readonly = 0;
    is_scratch = 1;
    is_dirty = 0;
    strcpy(file_path, "[ Scratch Buffer - 4 KB ]");

    const char banner[] =
        "================================================================\n"
        "  AsmHex v1.2 - Pure x86_64 Assembly Graphical Hex Editor       \n"
        "  Developed for ultra-fast, zero-latency binary editing.        \n"
        "================================================================\n"
        "  * Use Arrows or Mouse to navigate bytes                       \n"
        "  * Tab / Space: Switch between Hex and ASCII editing panes     \n"
        "  * Type hex digits (0-9, A-F) in Hex pane to edit nibbles      \n"
        "  * Type characters directly in ASCII pane to write bytes       \n"
        "  * Appending past EOF automatically extends file size          \n"
        "  * Ctrl+S: Save changes to disk (safe copy-on-write)           \n"
        "  * Ctrl+Z: Undo modifications                                  \n"
        "  * Ctrl+G: Jump directly to offset (hex or dec)                \n"
        "  * Ctrl+F: Search byte patterns or ASCII strings               \n"
        "  * F3 / Shift+F3: Next / Previous Diff (in Diff Mode)          \n"
        "  * Ctrl+Q or Esc: Quit without saving                          \n"
        "================================================================\n";
    size_t banner_len = strlen(banner);
    if (banner_len > size) banner_len = size;
    memcpy(buf, banner, banner_len);
    return 0;
}

__attribute__((sysv_abi))
int64_t file_ensure_capacity(uint64_t needed) {
    if (needed > 4294967296ULL) return -1; // 4 GiB max
    if (needed <= file_capacity) return 0;

    uint64_t new_cap = needed + 65536;
    new_cap = (new_cap + 4095) & ~4095ULL;
    if (new_cap > 4294967296ULL) new_cap = 4294967296ULL;

    uint8_t *new_buf = (uint8_t *)realloc(file_ptr, new_cap);
    if (!new_buf) return -1;

    if (new_cap > file_capacity) {
        memset(new_buf + file_capacity, 0, new_cap - file_capacity);
    }

    file_ptr = new_buf;
    file_capacity = new_cap;
    return 0;
}

__attribute__((sysv_abi))
int64_t file_save(void) {
    if (is_readonly) return -1;
    if (!file_ptr) return -3;
    if (!file_path[0]) return -3;

    FILE *fp = fopen(file_path, "wb");
    if (!fp) return -4;
    if (file_size > 0) {
        size_t written = fwrite(file_ptr, 1, file_size, fp);
        if (written != file_size) {
            fclose(fp);
            return -4;
        }
    }
    fflush(fp);
    fclose(fp);
    is_dirty = 0;
    is_scratch = 0;
    return 0;
}

__attribute__((sysv_abi))
int64_t file_save_as(const char *new_path) {
    if (!new_path || !new_path[0]) return -1;
    if (!file_ptr) return -2;

    FILE *fp = fopen(new_path, "wb");
    if (!fp) return -3;
    if (file_size > 0) {
        size_t written = fwrite(file_ptr, 1, file_size, fp);
        if (written != file_size) {
            fclose(fp);
            return -4;
        }
    }
    fflush(fp);
    fclose(fp);

    strncpy(file_path, new_path, sizeof(file_path) - 1);
    file_path[sizeof(file_path) - 1] = '\0';
    is_readonly = 0;
    is_scratch = 0;
    is_dirty = 0;
    return 0;
}

__attribute__((sysv_abi))
void file2_close(void) {
    if (file2_ptr) {
        free(file2_ptr);
        file2_ptr = NULL;
    }
    file2_size = 0;
    file2_capacity = 0;
    file2_fd = -1;
    file2_path[0] = '\0';
    is_readonly2 = 0;
}

__attribute__((sysv_abi))
int64_t file2_open(const char *path) {
    if (!path || !path[0]) return -1;
    file2_close();

    strncpy(file2_path, path, sizeof(file2_path) - 1);
    file2_path[sizeof(file2_path) - 1] = '\0';

    FILE *fp = fopen(path, "rb");
    if (!fp) return -1;

    _fseeki64(fp, 0, SEEK_END);
    int64_t sz = _ftelli64(fp);
    _fseeki64(fp, 0, SEEK_SET);

    if (sz < 0 || (uint64_t)sz > 4294967296ULL) {
        fclose(fp);
        return -4;
    }

    uint64_t cap = (uint64_t)sz + 65536;
    if (cap < 65536) cap = 65536;
    cap = (cap + 4095) & ~4095ULL;

    uint8_t *buf = (uint8_t *)calloc(1, cap);
    if (!buf) {
        fclose(fp);
        return -3;
    }

    if (sz > 0) {
        fread(buf, 1, (size_t)sz, fp);
    }
    fclose(fp);

    file2_ptr = buf;
    file2_size = (uint64_t)sz;
    file2_capacity = cap;
    file2_fd = 2;
    is_readonly2 = 1;
    return 0;
}

/* ------------------------------------------------------------------------------
 * Win32 GDI Presentation & DIBSection Management
 * ------------------------------------------------------------------------------ */
static HWND g_hwnd = NULL;
static HDC hdc_mem = NULL;
static HBITMAP hbm_dib = NULL;
static BITMAPINFO bmi;

static void win32_resize_framebuffer(int new_w, int new_h) {
    if (new_w <= 0 || new_h <= 0) return;
    if (new_w == win_w && new_h == win_h && fb_data) return;

    win_w = new_w;
    win_h = new_h;
    fb_pitch = win_w * 4;

    if (hbm_dib) {
        DeleteObject(hbm_dib);
        hbm_dib = NULL;
    }

    memset(&bmi, 0, sizeof(bmi));
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = win_w;
    bmi.bmiHeader.biHeight = -win_h; // Top-down DIB: (0,0) is top-left
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    HDC hdc_screen = GetDC(NULL);
    if (!hdc_mem) {
        hdc_mem = CreateCompatibleDC(hdc_screen);
    }
    void *bits = NULL;
    hbm_dib = CreateDIBSection(hdc_screen, &bmi, DIB_RGB_COLORS, &bits, NULL, 0);
    ReleaseDC(NULL, hdc_screen);

    fb_data = bits;
    SelectObject(hdc_mem, hbm_dib);
}

__attribute__((sysv_abi))
void x11_set_window_size(int w, int h) {
    if (!g_hwnd) return;
    RECT rc = {0, 0, w, h};
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);
    SetWindowPos(g_hwnd, NULL, 0, 0, rc.right - rc.left, rc.bottom - rc.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    win32_resize_framebuffer(w, h);
    editor_update_geometry();
    editor_ensure_visible();
    editor_render();
    InvalidateRect(g_hwnd, NULL, FALSE);
}

/* ------------------------------------------------------------------------------
 * Win32 Window Procedure
 * ------------------------------------------------------------------------------ */
static LRESULT CALLBACK WndProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    switch (uMsg) {
    case WM_SIZE: {
        int w = LOWORD(lParam);
        int h = HIWORD(lParam);
        if (w > 0 && h > 0) {
            win32_resize_framebuffer(w, h);
            editor_update_geometry();
            editor_ensure_visible();
            editor_render();
            InvalidateRect(hwnd, NULL, FALSE);
        }
        return 0;
    }

    case WM_PAINT: {
        PAINTSTRUCT ps;
        HDC hdc = BeginPaint(hwnd, &ps);
        if (fb_data && hdc_mem) {
            BitBlt(hdc, 0, 0, win_w, win_h, hdc_mem, 0, 0, SRCCOPY);
        }
        EndPaint(hwnd, &ps);
        return 0;
    }

    case WM_ERASEBKGND:
        return 1; // Prevent flickering; backbuffer covers entire client area

    case WM_KEYDOWN: {
        uint32_t state = 0;
        if (GetKeyState(VK_SHIFT) & 0x8000) state |= ShiftMask;
        if (GetKeyState(VK_CONTROL) & 0x8000) state |= ControlMask;

        if (state & ControlMask) {
            // Ctrl combinations
            uint64_t keysym = 0;
            char ascii[2] = {0, 0};
            if (wParam >= 'A' && wParam <= 'Z') {
                keysym = wParam + 32; // Lowercase char
                ascii[0] = (char)keysym;
            } else if (wParam == VK_OEM_PLUS || wParam == VK_ADD) {
                keysym = '+';
                ascii[0] = '+';
            } else if (wParam == VK_OEM_MINUS || wParam == VK_SUBTRACT) {
                keysym = '-';
                ascii[0] = '-';
            } else if (wParam == '0' || wParam == VK_NUMPAD0) {
                keysym = '0';
                ascii[0] = '0';
            } else if (wParam == VK_HOME) {
                keysym = XK_Home;
            } else if (wParam == VK_END) {
                keysym = XK_End;
            }

            if (keysym != 0) {
                int res = editor_handle_key(keysym, ascii, ascii[0] ? 1 : 0, state);
                if (res == 1) {
                    PostQuitMessage(0);
                } else {
                    editor_render();
                    InvalidateRect(hwnd, NULL, FALSE);
                }
                return 0;
            }
        }

        // Special / navigation keys
        uint64_t keysym = 0;
        switch (wParam) {
        case VK_LEFT:      keysym = XK_Left; break;
        case VK_RIGHT:     keysym = XK_Right; break;
        case VK_UP:        keysym = XK_Up; break;
        case VK_DOWN:      keysym = XK_Down; break;
        case VK_HOME:      keysym = XK_Home; break;
        case VK_END:       keysym = XK_End; break;
        case VK_PRIOR:     keysym = XK_Page_Up; break;
        case VK_NEXT:      keysym = XK_Page_Down; break;
        case VK_BACK:      keysym = XK_BackSpace; break;
        case VK_TAB:       keysym = XK_Tab; break;
        case VK_RETURN:    keysym = XK_Return; break;
        case VK_ESCAPE:    keysym = XK_Escape; break;
        case VK_DELETE:    keysym = XK_Delete; break;
        case VK_F1:        keysym = XK_F1; break;
        case VK_F2:        keysym = XK_F2; break;
        case VK_F3:        keysym = XK_F3; break;
        case VK_F7:        keysym = XK_F7; break;
        case VK_F8:        keysym = XK_F8; break;
        case VK_F11:       keysym = XK_F11; break;
        case VK_F12:       keysym = XK_F12; break;
        default:           break;
        }

        if (keysym != 0) {
            int res = editor_handle_key(keysym, "", 0, state);
            if (res == 1) {
                PostQuitMessage(0);
            } else {
                editor_render();
                InvalidateRect(hwnd, NULL, FALSE);
            }
            return 0;
        }

        // If in MODE_CONFIRM_QUIT, handle 'y', 'n', 'c' directly from virtual key
        if (editor_mode == MODE_CONFIRM_QUIT) {
            if (wParam == 'Y' || wParam == 'N' || wParam == 'C') {
                char ascii[2] = { (char)(wParam + 32), 0 };
                int res = editor_handle_key((uint64_t)(wParam + 32), ascii, 1, 0);
                if (res == 1) {
                    PostQuitMessage(0);
                } else {
                    editor_render();
                    InvalidateRect(hwnd, NULL, FALSE);
                }
                return 0;
            }
        }
        break;
    }

    case WM_CHAR: {
        // Printable ASCII input (Hex / ASCII panes & modals)
        if (wParam >= 32 && wParam <= 126) {
            if (!(GetKeyState(VK_CONTROL) & 0x8000)) {
                uint32_t state = (GetKeyState(VK_SHIFT) & 0x8000) ? ShiftMask : 0;
                char ascii[2] = { (char)wParam, 0 };
                int res = editor_handle_key((uint64_t)wParam, ascii, 1, state);
                if (res == 1) {
                    PostQuitMessage(0);
                } else {
                    editor_render();
                    InvalidateRect(hwnd, NULL, FALSE);
                }
            }
        }
        return 0;
    }

    case WM_LBUTTONDOWN: {
        SetCapture(hwnd);
        editor_handle_click(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam), 1);
        editor_render();
        InvalidateRect(hwnd, NULL, FALSE);
        return 0;
    }

    case WM_MOUSEMOVE: {
        if (wParam & MK_LBUTTON) {
            editor_handle_mouse_move(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam));
            editor_render();
            InvalidateRect(hwnd, NULL, FALSE);
        }
        return 0;
    }

    case WM_LBUTTONUP: {
        ReleaseCapture();
        editor_handle_button_release(GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam), 1);
        editor_render();
        InvalidateRect(hwnd, NULL, FALSE);
        return 0;
    }

    case WM_MOUSEWHEEL: {
        short delta = GET_WHEEL_DELTA_WPARAM(wParam);
        if (delta > 0) {
            editor_handle_wheel(4); // Wheel Up
        } else if (delta < 0) {
            editor_handle_wheel(5); // Wheel Down
        }
        editor_render();
        InvalidateRect(hwnd, NULL, FALSE);
        return 0;
    }

    case WM_DROPFILES: {
        HDROP hDrop = (HDROP)wParam;
        char drop_path[MAX_PATH];
        if (DragQueryFileA(hDrop, 0, drop_path, sizeof(drop_path))) {
            if (is_diff_mode == 1 || (!is_scratch && (file_fd != -1 || is_dirty != 0 || file_size != 0))) {
                if (file2_open(drop_path) == 0) {
                    is_diff_mode = 1;
                    diff_active_file = 0;
                    diff_recompute();
                } else {
                    editor_set_status("Failed to open dropped file for diff comparison!", 0x6C7086);
                }
            } else {
                file2_close();
                is_diff_mode = 0;
                file_close();
                if (file_open(drop_path) != 0) {
                    file_create_blank();
                }
                editor_init();
            }
            editor_render();
            InvalidateRect(hwnd, NULL, FALSE);
        }
        DragFinish(hDrop);
        return 0;
    }

    case WM_CLOSE: {
        if (is_dirty) {
            editor_prompt_confirm_quit();
            editor_render();
            InvalidateRect(hwnd, NULL, FALSE);
        } else {
            DestroyWindow(hwnd);
        }
        return 0;
    }

    case WM_DESTROY: {
        PostQuitMessage(0);
        return 0;
    }

    default:
        return DefWindowProcA(hwnd, uMsg, wParam, lParam);
    }
    return 0;
}

/* ------------------------------------------------------------------------------
 * Main Entry Point
 * ------------------------------------------------------------------------------ */
int main(int argc, char **argv) {
    printf("================================================================\n");
    printf("  AsmHex v1.2.0 - Graphical Hex Editor in Pure x86_64 Assembly  \n");
    printf("  Platform: Windows 64-bit Port / GDI DIBSection Accelerated   \n");
    printf("================================================================\n");

    /* Initialize core assembly rendering LUTs, CRC32 table & editor state */
    init_renderer_luts();
    init_crc32_table();
    editor_init();

    const char *auto_shot_path = NULL;
    int is_auto_shot = 0;

    /* Parse Command-Line Options */
    int arg_idx = 1;
    if (argc >= 2 && strcmp(argv[1], "--screenshot") == 0) {
        if (argc >= 3) {
            auto_shot_path = argv[2];
            is_auto_shot = 1;
            arg_idx = 3;
        }
    }

    int remaining_args = argc - arg_idx;
    if (remaining_args >= 3 && (strcmp(argv[arg_idx], "--diff") == 0 || strcmp(argv[arg_idx], "-d") == 0)) {
        file_open(argv[arg_idx + 1]);
        file2_open(argv[arg_idx + 2]);
        is_diff_mode = 1;
        diff_recompute();
        printf("[AsmHex Diff] Comparing '%s' vs '%s'\n", argv[arg_idx + 1], argv[arg_idx + 2]);
    } else if (remaining_args >= 2) {
        file_open(argv[arg_idx]);
        file2_open(argv[arg_idx + 1]);
        is_diff_mode = 1;
        diff_recompute();
        printf("[AsmHex Diff] Comparing '%s' vs '%s'\n", argv[arg_idx], argv[arg_idx + 1]);
    } else if (remaining_args == 1) {
        if (file_open(argv[arg_idx]) != 0) {
            printf("Error opening '%s', creating blank buffer.\n", argv[arg_idx]);
            file_create_blank();
        }
    } else {
        file_create_blank();
    }

    /* Initialize Framebuffer and Geometry */
    win32_resize_framebuffer(win_w, win_h);
    editor_update_geometry();
    editor_render();

    /* Headless screenshot mode: render directly to backbuffer and exit */
    if (is_auto_shot && auto_shot_path) {
        dump_screenshot(auto_shot_path);
        printf("[AsmHex] Screenshot saved to '%s'\n", auto_shot_path);
        file2_close();
        file_close();
        return 0;
    }

    /* Register Win32 Window Class */
    HINSTANCE hInst = GetModuleHandle(NULL);
    WNDCLASSEXA wc = {0};
    wc.cbSize = sizeof(WNDCLASSEXA);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.lpszClassName = "AsmHexClass";
    RegisterClassExA(&wc);

    /* Calculate window rect including title bar and borders */
    RECT rc = {0, 0, win_w, win_h};
    AdjustWindowRect(&rc, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hwnd = CreateWindowExA(
        WS_EX_ACCEPTFILES,
        "AsmHexClass",
        " AsmHex v1.2 - Pure x86_64 Assembly Hex Editor",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        rc.right - rc.left, rc.bottom - rc.top,
        NULL, NULL, hInst, NULL
    );

    if (!hwnd) {
        fprintf(stderr, "Failed to create Win32 window.\n");
        return 1;
    }

    g_hwnd = hwnd;
    DragAcceptFiles(hwnd, TRUE);

    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);

    /* Win32 Message Loop */
    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    file2_close();
    file_close();
    return 0;
}
