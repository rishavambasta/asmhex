; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; constants.inc - Global constants, colors, key definitions, and layout geometry
; ==============================================================================

; Window & Canvas Geometry
WIN_DEFAULT_W       equ 1040
WIN_DEFAULT_H       equ 720
FONT_W              equ 8
FONT_H              equ 16

HEADER_H            equ 32
COL_HDR_H           equ 20
STATUS_H            equ 54
SEPARATOR_Y         equ 52

BYTES_PER_ROW       equ 16
VISIBLE_ROWS        equ 36       ; (720 - 52 - 54) / 16 = ~38 rows, we use 36 safely

; Scrollbar Geometry
SCROLLBAR_X         equ 722
SCROLLBAR_W         equ 10
SCROLL_THUMB_MIN_H  equ 24

; Column X Coordinates
OFFSET_X            equ 16
GUTTER_SEP_X        equ 152
HEX_START_X         equ 164
BYTE_SPACING        equ 24       ; 2 hex chars (16px) + 8px gap
GROUP_GAP           equ 12       ; Extra spacing between 8-byte groups
HEX_END_X           equ 564
ASCII_SEP_X         equ 576
ASCII_START_X       equ 592
DATA_PANE_W         equ 734
PANEL_DIVIDER_X     equ 736
INSPECTOR_X         equ 748

; Modern Dark Theme Color Palette (32-bit ARGB 0x00RRGGBB)
COLOR_BG            equ 0x001E1E2E   ; Catppuccin Base
COLOR_PANEL_BG      equ 0x00181825   ; Mantle
COLOR_STATUS_BG     equ 0x0011111B   ; Crust
COLOR_HEADER_BG     equ 0x00181825   ; Mantle
COLOR_BORDER        equ 0x00313244   ; Surface0
COLOR_DIVIDER       equ 0x0045475A   ; Surface1

; Scrollbar Colors
COLOR_SCROLL_TRACK  equ 0x00151521   ; Darker slate track
COLOR_SCROLL_THUMB  equ 0x0045475A   ; Muted Surface1 thumb
COLOR_SCROLL_ACTIVE equ 0x0089B4FA   ; Bright Blue active dragging thumb

; Selection & Translucent Polygon Colors
COLOR_SEL_FILL      equ 0x0089B4FA   ; Bright Blue translucent polygon fill
COLOR_SEL_BORDER    equ 0x0089DCEB   ; Bright Cyan polygon perimeter outline
COLOR_SEL_ALPHA     equ 96           ; Alpha opacity (96/256 = ~38%)
COLOR_SEL_TEXT      equ 0x00FFFFFF   ; Pure white text inside selection

COLOR_TEXT_NORMAL   equ 0x00CDD6F4   ; Crisp Text
COLOR_TEXT_DIM      equ 0x006C7086   ; Dim Text
COLOR_TEXT_BRIGHT   equ 0x00FFFFFF   ; Bright White
COLOR_OFFSET        equ 0x0089B4FA   ; Soft Blue

; Hex Data Highlighting
COLOR_HEX_ZERO      equ 0x0045475A   ; Dimmed Nulls (00)
COLOR_HEX_ASCII     equ 0x00A6E3A1   ; Mint Green for printable ASCII
COLOR_HEX_SPECIAL   equ 0x00F9E2AF   ; Warm Yellow for high/special bytes
COLOR_HEX_CTRL      equ 0x00FAB387   ; Orange for control bytes
COLOR_MODIFIED      equ 0x00F38BA8   ; Coral Red for modified bytes

; Cursors & Selection
COLOR_CURSOR_BG     equ 0x0089B4FA   ; Bright Blue cursor
COLOR_CURSOR_FG     equ 0x0011111B   ; Dark text under cursor
COLOR_CURSOR_PEER   equ 0x00313244   ; Peer cursor in other pane (Hex <-> ASCII)
COLOR_NIBBLE_HILITE equ 0x00F5C2E7   ; Highlight active nibble

; Inspector & Status Colors
COLOR_INSP_TITLE    equ 0x00CBA6F7   ; Mauve
COLOR_INSP_LABEL    equ 0x009399B2   ; Subtext0
COLOR_INSP_VAL      equ 0x0089DCEB   ; Sky Cyan
COLOR_PROMPT_BG     equ 0x00313244   ; Surface0
COLOR_PROMPT_FG     equ 0x00F9E2AF   ; Yellow

; Editor Modes
MODE_NORMAL         equ 0
MODE_GOTO           equ 1
MODE_SEARCH         equ 2

; Active Panes
PANE_HEX            equ 0
PANE_ASCII          equ 1

; X11 KeySyms (from X11/keysymdef.h)
XK_BackSpace        equ 0xFF08
XK_Tab              equ 0xFF09
XK_Return           equ 0xFF0D
XK_Escape           equ 0xFF1B
XK_Home             equ 0xFF50
XK_Left             equ 0xFF51
XK_Up               equ 0xFF52
XK_Right            equ 0xFF53
XK_Down             equ 0xFF54
XK_Page_Up          equ 0xFF55
XK_Page_Down        equ 0xFF56
XK_End              equ 0xFF57
XK_Delete           equ 0xFFFF
XK_F3               equ 0xFFBE
XK_F11              equ 0xFFC8
XK_F12              equ 0xFFC9

; X11 Event Types
KeyPress            equ 2
ButtonPress         equ 4
ButtonRelease       equ 5
MotionNotify        equ 6
Expose              equ 12
ConfigureNotify     equ 22
SelectionNotify     equ 31
ClientMessage       equ 33

; X11 Event Masks
ExposureMask        equ (1 << 15)
KeyPressMask        equ (1 << 0)
ButtonPressMask     equ (1 << 2)
ButtonReleaseMask   equ (1 << 3)
Button1MotionMask   equ (1 << 8)
StructureNotifyMask equ (1 << 17)

; Linux Syscall Numbers (x86_64)
SYS_read            equ 0
SYS_write           equ 1
SYS_open            equ 2
SYS_close           equ 3
SYS_stat            equ 4
SYS_fstat           equ 5
SYS_mmap            equ 9
SYS_munmap          equ 11
SYS_msync           equ 26
SYS_exit            equ 60
SYS_newfstatat      equ 262

; File open flags & protections
O_RDONLY            equ 0
O_WRONLY            equ 1
O_RDWR              equ 2
O_CREAT             equ 64

PROT_READ           equ 1
PROT_WRITE          equ 2
MAP_SHARED          equ 1
MAP_PRIVATE         equ 2
MAP_ANONYMOUS       equ 32
MS_SYNC             equ 4

; Maximum modifications tracked in undo stack
MAX_UNDO            equ 4096
