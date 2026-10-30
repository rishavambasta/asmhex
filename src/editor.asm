; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; editor.asm - Navigation, editing logic, undo tracking, inspector & search
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

extern win_w
extern win_h
extern fb_data
extern fb_pitch

extern file_ptr
extern file_size
extern file_fd
extern is_readonly
extern is_scratch
extern file_path
extern file_save

extern file2_ptr
extern file2_size
extern file2_fd
extern is_readonly2
extern file2_path
extern file2_open
extern file2_close

extern compute_crc32
extern compute_sha256
extern format_sha256_hex
extern printf

extern init_renderer_luts
extern draw_rect
extern draw_rect_alpha
extern draw_glyph
extern draw_glyph_transparent
extern draw_string
extern draw_string_len
extern draw_hline
extern draw_vline
extern format_hex_qword
extern format_hex_dword
extern format_dec_qword
extern format_dec_int64
extern format_size_human
extern dump_screenshot
extern hex_lut
extern bin_lut

section .data
    title_str:         db " AsmHex v1.0 ", 0
    sub_title:         db "Pure x86_64 Assembly Hex Editor", 0
    tag_mod:           db " [MODIFIED] ", 0
    tag_ro:            db " [READ-ONLY] ", 0
    tag_scratch:       db " [SCRATCH] ", 0

    screenshot_file:   db "asmhex_screenshot.ppm", 0
    status_shot_saved: db "Screenshot saved to asmhex_screenshot.ppm!", 0

    col_hdr_offset:    db "Offset (h)", 0
    col_hdr_hex:       db "00 01 02 03 04 05 06 07  08 09 0a 0b 0c 0d 0e 0f", 0
    col_hdr_ascii:     db "Decoded text", 0

    insp_title:        db "── DATA INSPECTOR ──", 0
    insp_off_h:        db "Offset (Hex):  0x", 0
    insp_off_d:        db "Offset (Dec):  ", 0
    insp_val_h:        db "Value (Hex):   0x", 0
    insp_val_b:        db "Value (Bin):   ", 0
    insp_val_c:        db "Value (Char):  '", 0
    insp_sec_int:      db "── INTEGERS (LE) ──", 0
    insp_u8:           db "uint8:         ", 0
    insp_s8:           db "int8:          ", 0
    insp_u16:          db "uint16:        ", 0
    insp_s16:          db "int16:         ", 0
    insp_u32:          db "uint32:        ", 0
    insp_s32:          db "int32:         ", 0
    insp_u64:          db "uint64:        0x", 0
    insp_sec_file:     db "── FILE STATS ──", 0
    insp_size:         db "Size:          ", 0
    insp_pos:          db "Cursor Pos:    ", 0
    insp_mode:         db "Active Pane:   ", 0
    insp_mode_hex:     db "HEX", 0
    insp_mode_asc:     db "ASCII", 0

    insp_sec_diff:      db "── FILE DIFF (F2) ──", 0
    insp_diff_cnt:      db "Diffs:     ", 0
    insp_diff_active:   db "Active:    File ", 0
    insp_diff_f1_val:   db "File 1:    0x", 0
    insp_diff_f2_val:   db "File 2:    0x", 0
    insp_diff_status:   db "Status:    ", 0
    insp_diff_match:    db "IDENTICAL [==]", 0
    insp_diff_mismatch: db "MISMATCH  [!=]", 0
    insp_diff_eof:      db "<EOF>     ", 0
    tag_diff:           db " [DIFF MODE] ", 0
    insp_h_diff_nav:    db "F7 / F8      : Prev/Next Diff", 0
    insp_h_diff_flip:   db "F2           : Flip File (1 <-> 2)", 0
    status_flipped_1:   db "Flipped active display to File 1.", 0
    status_flipped_2:   db "Flipped active display to File 2.", 0
    status_diff_nav:    db "Jumped to difference at offset 0x", 0
    status_no_diffs:    db "Files are bit-identical! 0 differences found.", 0

    insp_sec_sel:      db "── SELECTION ──", 0
    insp_sel_range:    db "Range:  0x", 0
    insp_sel_dots:     db "..0x", 0
    insp_sel_len:      db "Length: ", 0
    insp_sel_bytes:    db " B (0x", 0
    str_close_paren:   db ")", 0

    insp_sec_hash:     db "── CHECKSUMS (F12) ──", 0
    insp_crc_lbl:      db "CRC-32:  0x", 0
    insp_sha_lbl:      db "SHA-256:", 0

    insp_sec_help:     db "── SHORTCUTS ──", 0
    insp_h1:           db "Arrows/Mouse : Move cursor", 0
    insp_h_sel:        db "Shift+Arrows : Select range", 0
    insp_h2:           db "PgUp / PgDn  : Scroll page", 0
    insp_h3:           db "Tab / Space  : Switch pane", 0
    insp_h4:           db "0-9, a-f     : Edit nibble", 0
    insp_h5:           db "Ctrl+S       : Save changes", 0
    insp_h6:           db "Ctrl+Z       : Undo edit", 0
    insp_h7:           db "Ctrl+G       : Goto offset", 0
    insp_h8:           db "Ctrl+F       : Find pattern", 0
    insp_h9:           db "Ctrl+Q / Esc : Quit", 0
    insp_h10:          db "F12          : Checksums (SHA/CRC)", 0
    insp_h11:          db "F11          : Screenshot", 0

    status_ready:      db "Ready. Press Ctrl+S to save changes. Ctrl+Z to undo.", 0
    status_saved:      db "File saved successfully (msync committed to disk).", 0
    status_ro_err:     db "Cannot save: File is open in READ-ONLY mode!", 0
    status_undone:     db "Undid edit at offset 0x", 0
    status_not_found:  db "Pattern not found.", 0
    status_found_at:   db "Pattern found at offset 0x", 0
    status_goto_jump:  db "Jumped to offset 0x", 0
    status_hash_empty: db "Range empty (0 bytes) -> CRC32: 0x00000000 | SHA256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 0
    fmt_checksum_log:  db "[AsmHex Checksum] Range 0x%lx..0x%lx (%lu bytes):", 10, "  CRC-32:  0x%08x", 10, "  SHA-256: %s", 10, 0
    fmt_checksum_empty: db "[AsmHex Checksum] Range empty (0 bytes):", 10, "  CRC-32:  0x00000000", 10, "  SHA-256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 10, 0
    empty_sha256_str:  db "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 0
    status_help_bar:      db "^S Save  ^Z Undo  Shift+Arrows Select  F12 Hash  ^G Goto  ^F Find  ^Q Quit", 0
    status_help_bar_diff: db "^S Save  ^Z Undo  Shift+Arrows Select  F12 Hash  F7/F8 Diff  F2 Flip  ^Q Quit", 0
    str_diff_sep:         db "<=>", 0

    prompt_goto:       db "GOTO OFFSET (hex or dec): ", 0
    prompt_goto_help:  db "[Enter] Jump to offset    [Esc] Cancel", 0
    prompt_find:       db "FIND (ASCII or \x Hex): ", 0
    prompt_find_help:  db "[Enter] Find Next    [Esc] Cancel", 0

    str_gutter_sep:    db "|", 0
    str_quote_nl:      db "'", 0

section .bss
    global cursor_offset
    global scroll_offset
    global active_pane
    global nibble_index
    global is_dirty
    global editor_mode
    global sel_start
    global sel_end
    global has_selection
    global is_selecting
    global is_dragging_scrollbar
    global drag_mouse_y
    global drag_scroll_orig
    global thumb_y
    global thumb_h
    global last_checksum_valid
    global last_crc32
    global last_sha256_hex
    global last_checksum_off
    global last_checksum_len
    global is_diff_mode
    global diff_active_file
    global diff_count

    alignb 16
    cursor_offset:     resq 1            ; Current file byte offset
    scroll_offset:     resq 1            ; Offset of top-left visible byte
    active_pane:       resd 1            ; PANE_HEX (0) or PANE_ASCII (1)
    nibble_index:      resd 1            ; 0 = high nibble, 1 = low nibble
    is_dirty:          resd 1            ; 1 if modifications exist
    editor_mode:       resd 1            ; MODE_NORMAL (0), MODE_GOTO (1), MODE_SEARCH (2)

    ; Diff & Multi-File Comparison State
    is_diff_mode:      resd 1            ; 1 if diff mode active
    diff_active_file:  resd 1            ; 0 = File 1 active, 1 = File 2 active
    diff_count:        resq 1            ; Total count of differing bytes

    sel_start:              resq 1       ; Selection start offset
    sel_end:                resq 1       ; Selection end offset
    has_selection:          resd 1       ; 1 if selection active
    is_selecting:           resd 1       ; 1 if dragging selection in window
    is_dragging_scrollbar:  resd 1       ; 1 if dragging scrollbar
    drag_mouse_y:           resd 1       ; Mouse Y when scrollbar drag started
    drag_scroll_orig:       resq 1       ; Scroll offset when drag started
    thumb_y:                resd 1       ; Current computed thumb Y
    thumb_h:                resd 1       ; Current computed thumb H

    ; Active selection checksums (F12)
    last_checksum_valid:   resd 1        ; 1 if checksums valid & computed
    last_crc32:            resd 1        ; IEEE 802.3 CRC32
    last_sha256_digest:    resb 32       ; Binary SHA256 (32 bytes)
    last_sha256_hex:       resb 68       ; Lowercase Hex SHA256 (64 chars + null)
    last_checksum_off:     resq 1        ; Range start offset
    last_checksum_len:     resq 1        ; Range byte count
    status_hash_buf:       resb 128      ; Status line formatted checksum buffer

    ; Undo stack: 4096 entries (16 bytes each: offset (8), old_val (1), new_val (1), pad (6))
    undo_count:        resd 1
    alignb 16
    undo_stack:        resb MAX_UNDO * 16

    ; Modal input buffer (for Goto & Search)
    input_buf:         resb 128
    input_len:         resd 1
    search_pat:        resb 128
    search_pat_len:    resd 1

    ; Status line message buffer
    status_msg_buf:    resb 256
    status_msg_len:    resd 1
    status_msg_color:  resd 1

    ; Formatting scratch buffers
    str_buf_1:         resb 64
    str_buf_2:         resb 64

section .text

; ------------------------------------------------------------------------------
; editor_init:
; ------------------------------------------------------------------------------
global editor_init
editor_init:
    mov qword [rel cursor_offset], 0
    mov qword [rel scroll_offset], 0
    mov dword [rel active_pane], PANE_HEX
    mov dword [rel nibble_index], 0
    mov dword [rel is_dirty], 0
    mov dword [rel editor_mode], MODE_NORMAL
    mov dword [rel undo_count], 0
    mov dword [rel input_len], 0
    mov dword [rel search_pat_len], 0
    mov qword [rel sel_start], 0
    mov qword [rel sel_end], 0
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    mov dword [rel is_dragging_scrollbar], 0
    mov dword [rel drag_mouse_y], 0
    mov qword [rel drag_scroll_orig], 0
    mov dword [rel thumb_y], SEPARATOR_Y
    mov dword [rel thumb_h], SCROLL_THUMB_MIN_H
    mov dword [rel last_checksum_valid], 0
    mov dword [rel last_crc32], 0
    mov qword [rel last_checksum_off], 0
    mov qword [rel last_checksum_len], 0
    mov byte [rel last_sha256_hex], 0
    mov dword [rel is_diff_mode], 0
    mov dword [rel diff_active_file], 0
    mov qword [rel diff_count], 0

    ; Set initial status message
    lea rdi, [rel status_ready]
    mov esi, COLOR_TEXT_DIM
    call editor_set_status
    ret

; ------------------------------------------------------------------------------
; editor_set_status:
; rdi = status text ptr, esi = color
; ------------------------------------------------------------------------------
global editor_set_status
editor_set_status:
    push rbx
    mov [rel status_msg_color], esi
    lea rsi, [rdi]
    lea rdi, [rel status_msg_buf]
    xor ecx, ecx
.cpy:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    inc ecx
    test al, al
    jnz .cpy
    dec ecx
    mov [rel status_msg_len], ecx
    pop rbx
    ret

; ------------------------------------------------------------------------------
; editor_get_active_file:
; Returns rax = active file_ptr, rdx = active file_size
; ------------------------------------------------------------------------------
global editor_get_active_file
editor_get_active_file:
    cmp dword [rel is_diff_mode], 1
    jne .act_f1
    cmp dword [rel diff_active_file], 1
    jne .act_f1
    mov rax, [rel file2_ptr]
    mov rdx, [rel file2_size]
    ret
.act_f1:
    mov rax, [rel file_ptr]
    mov rdx, [rel file_size]
    ret

; ------------------------------------------------------------------------------
; editor_get_diff_max_size:
; Returns rdx = max(file_size, file2_size) if diff mode, else file_size
; ------------------------------------------------------------------------------
global editor_get_diff_max_size
editor_get_diff_max_size:
    mov rdx, [rel file_size]
    cmp dword [rel is_diff_mode], 1
    jne .dms_ret
    push rcx
    mov rcx, [rel file2_size]
    cmp rdx, rcx
    jae .dms_no_swap
    mov rdx, rcx
.dms_no_swap:
    pop rcx
.dms_ret:
    ret

; ------------------------------------------------------------------------------
; editor_ensure_visible:
; Adjusts scroll_offset so that cursor_offset is on screen
; ------------------------------------------------------------------------------
global editor_ensure_visible
editor_ensure_visible:
    mov rax, [rel cursor_offset]

    ; If cursor < scroll_offset, scroll up to align cursor's row
    cmp rax, [rel scroll_offset]
    jae .check_below
    ; scroll_offset = cursor_offset & ~15
    and rax, ~15
    mov [rel scroll_offset], rax
    ret

.check_below:
    ; page_bytes = VISIBLE_ROWS * 16 = 576
    mov rdx, [rel scroll_offset]
    add rdx, VISIBLE_ROWS * 16
    cmp rax, rdx
    jb .visible_ok

    ; cursor is below visible area
    ; scroll_offset = (cursor_offset & ~15) - (VISIBLE_ROWS - 1) * 16
    and rax, ~15
    sub rax, (VISIBLE_ROWS - 1) * 16
    cmp rax, 0
    jge .set_sc
    xor eax, eax
.set_sc:
    mov [rel scroll_offset], rax

.visible_ok:
    ret

; ------------------------------------------------------------------------------
; Navigation commands
; ------------------------------------------------------------------------------
global editor_move_left
editor_move_left:
    cmp dword [rel active_pane], PANE_HEX
    jne .asc_left
    ; In hex pane: if nibble == 1, move to high nibble
    cmp dword [rel nibble_index], 1
    jne .byte_left
    mov dword [rel nibble_index], 0
    ret

.byte_left:
    mov rax, [rel cursor_offset]
    test rax, rax
    jz .left_done
    dec rax
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 1
    call editor_ensure_visible
.left_done:
    ret

.asc_left:
    mov rax, [rel cursor_offset]
    test rax, rax
    jz .asc_l_done
    dec rax
    mov [rel cursor_offset], rax
    call editor_ensure_visible
.asc_l_done:
    ret

global editor_next_byte
editor_next_byte:
    mov rax, [rel cursor_offset]
    call editor_get_diff_max_size
    test rdx, rdx
    jz .next_b_done
    dec rdx                           ; max index = max_size - 1
    cmp rax, rdx
    jae .next_b_done
    inc rax
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible
.next_b_done:
    ret

global editor_move_right
editor_move_right:
    cmp dword [rel active_pane], PANE_HEX
    jne .asc_right
    ; In hex pane: if nibble == 0, move to low nibble
    cmp dword [rel nibble_index], 0
    jne .byte_right
    mov dword [rel nibble_index], 1
    ret

.byte_right:
    call editor_next_byte
    ret

.asc_right:
    call editor_next_byte
    ret

global editor_move_up
editor_move_up:
    mov rax, [rel cursor_offset]
    cmp rax, 16
    jb .up_clamp
    sub rax, 16
    mov [rel cursor_offset], rax
    call editor_ensure_visible
    ret
.up_clamp:
    xor eax, eax
    mov [rel cursor_offset], rax
    call editor_ensure_visible
    ret

global editor_move_down
editor_move_down:
    mov rax, [rel cursor_offset]
    add rax, 16
    call editor_get_diff_max_size
    test rdx, rdx
    jz .down_done
    cmp rax, rdx
    jb .down_ok
    ; clamp to last byte
    mov rax, rdx
    dec rax
.down_ok:
    mov [rel cursor_offset], rax
    call editor_ensure_visible
.down_done:
    ret

global editor_page_up
editor_page_up:
    mov rax, [rel cursor_offset]
    mov rdx, VISIBLE_ROWS * 16
    cmp rax, rdx
    jb .pgup_zero
    sub rax, rdx
    mov [rel cursor_offset], rax
    call editor_ensure_visible
    ret
.pgup_zero:
    xor eax, eax
    mov [rel cursor_offset], rax
    call editor_ensure_visible
    ret

global editor_page_down
editor_page_down:
    mov rax, [rel cursor_offset]
    add rax, VISIBLE_ROWS * 16
    call editor_get_diff_max_size
    test rdx, rdx
    jz .pgdn_done
    cmp rax, rdx
    jb .pgdn_ok
    mov rax, rdx
    dec rax
.pgdn_ok:
    mov [rel cursor_offset], rax
    call editor_ensure_visible
.pgdn_done:
    ret

global editor_home
editor_home:
    ; Jump to start of current row (offset & ~15)
    mov rax, [rel cursor_offset]
    and rax, ~15
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible
    ret

global editor_end
editor_end:
    ; Jump to end of current row
    mov rax, [rel cursor_offset]
    or rax, 15
    call editor_get_diff_max_size
    test rdx, rdx
    jz .end_done
    cmp rax, rdx
    jb .end_ok
    mov rax, rdx
    dec rax
.end_ok:
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible
.end_done:
    ret

; ------------------------------------------------------------------------------
; Undo Tracking
; ------------------------------------------------------------------------------
; rdi = offset, sil = old_byte, dl = new_byte
editor_record_undo:
    mov ecx, [rel undo_count]
    test ecx, ecx
    jz .new_undo_entry

    ; Check if top of stack has same offset
    dec ecx
    lea rax, [rel undo_stack]
    shl rcx, 4
    add rax, rcx
    cmp [rax], rdi                    ; same offset?
    jne .new_undo_entry

    ; Same offset! Just update new_val, keep original old_val intact
    mov [rax + 9], dl
    mov dword [rel is_dirty], 1
    mov dword [rel last_checksum_valid], 0
    ret

.new_undo_entry:
    mov ecx, [rel undo_count]
    cmp ecx, MAX_UNDO
    jae .undo_full

    ; entry = undo_stack + count * 16
    lea rax, [rel undo_stack]
    shl rcx, 4
    add rax, rcx

    mov [rax], rdi                    ; offset (8 bytes)
    mov [rax + 8], sil                ; old_val
    mov [rax + 9], dl                 ; new_val
    inc dword [rel undo_count]
    mov dword [rel is_dirty], 1
    mov dword [rel last_checksum_valid], 0
.undo_full:
    ret

global editor_undo
editor_undo:
    mov ecx, [rel undo_count]
    test ecx, ecx
    jz .nothing_to_undo

    dec ecx
    mov [rel undo_count], ecx

    lea rax, [rel undo_stack]
    shl rcx, 4
    add rax, rcx

    mov rdi, [rax]                    ; offset
    movzx esi, byte [rax + 8]         ; old_val

    ; Restore old byte into memory buffer
    call editor_get_active_file       ; rax = active file_ptr, rdx = active file_size
    mov rbx, rax
    test rbx, rbx
    jz .undo_err
    mov [rbx + rdi], sil
    mov dword [rel last_checksum_valid], 0

    mov [rel cursor_offset], rdi
    mov dword [rel nibble_index], 0
    call editor_ensure_visible

    ; If in diff mode, recompute diffs
    cmp dword [rel is_diff_mode], 1
    jne .undo_no_diff
    call diff_recompute
.undo_no_diff:

    ; If undo_count reached 0, clear is_dirty
    cmp dword [rel undo_count], 0
    jnz .still_dirty
    mov dword [rel is_dirty], 0
.still_dirty:

    ; Format status: "Undid edit at offset 0x..."
    lea rdi, [rel str_buf_1]
    mov rsi, [rel cursor_offset]
    call format_hex_qword

    lea rdi, [rel status_msg_buf]
    lea rsi, [rel status_undone]
.c1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c1
    dec rdi

    lea rsi, [rel str_buf_1]
.c2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .c2

    mov dword [rel status_msg_color], COLOR_INSP_VAL
.nothing_to_undo:
.undo_err:
    ret

; ------------------------------------------------------------------------------
; editor_is_byte_modified:
; Checks if file byte at rdi is in undo_stack
; Returns eax = 1 if modified, 0 if not
; ------------------------------------------------------------------------------
global editor_is_byte_modified
editor_is_byte_modified:
    mov ecx, [rel undo_count]
    test ecx, ecx
    jz .not_mod

    lea rax, [rel undo_stack]
.chk_loop:
    cmp [rax], rdi
    je .is_mod
    add rax, 16
    dec ecx
    jnz .chk_loop

.not_mod:
    xor eax, eax
    ret
.is_mod:
    mov eax, 1
    ret

; ------------------------------------------------------------------------------
; Modal Search & Goto Handlers
; ------------------------------------------------------------------------------
editor_start_goto:
    mov dword [rel editor_mode], MODE_GOTO
    mov dword [rel input_len], 0
    mov byte [rel input_buf], 0
    ret

editor_start_search:
    mov dword [rel editor_mode], MODE_SEARCH
    mov dword [rel input_len], 0
    mov byte [rel input_buf], 0
    ret

editor_cancel_modal:
    mov dword [rel editor_mode], MODE_NORMAL
    mov dword [rel input_len], 0
    lea rdi, [rel status_ready]
    mov esi, COLOR_TEXT_DIM
    call editor_set_status
    ret

editor_commit_goto:
    ; Parse input_buf as hex or dec
    lea rsi, [rel input_buf]
    xor rax, rax                      ; result
    xor ecx, ecx                      ; is_hex flag
    xor edx, edx

    ; Check for "0x" or "0X"
    cmp word [rsi], "0x"
    je .hex_pref
    cmp word [rsi], "0X"
    je .hex_pref
    jmp .parse_chars

.hex_pref:
    add rsi, 2
    mov ecx, 1                        ; force hex

.parse_chars:
    ; Detect if contains A-F / a-f
    lea rdi, [rsi]
.scan_hex:
    mov dl, [rdi]
    test dl, dl
    jz .do_parse
    cmp dl, 'a'
    jl .not_low
    cmp dl, 'f'
    jle .found_hex
.not_low:
    cmp dl, 'A'
    jl .scan_next
    cmp dl, 'F'
    jle .found_hex
.scan_next:
    inc rdi
    jmp .scan_hex
.found_hex:
    mov ecx, 1

.do_parse:
    test ecx, ecx
    jnz .parse_hex

    ; Parse Decimal
.dec_loop:
    movzx edx, byte [rsi]
    test dl, dl
    jz .parse_done
    cmp dl, '0'
    jb .parse_done
    cmp dl, '9'
    ja .parse_done
    sub dl, '0'
    imul rax, 10
    add rax, rdx
    inc rsi
    jmp .dec_loop

.parse_hex:
    movzx edx, byte [rsi]
    test dl, dl
    jz .parse_done
    cmp dl, '0'
    jb .parse_done
    cmp dl, '9'
    jbe .h_digit
    cmp dl, 'A'
    jb .check_h_low
    cmp dl, 'F'
    jbe .h_upper
.check_h_low:
    cmp dl, 'a'
    jb .parse_done
    cmp dl, 'f'
    ja .parse_done
    sub dl, 'a' - 10
    jmp .h_accum
.h_digit:
    sub dl, '0'
    jmp .h_accum
.h_upper:
    sub dl, 'A' - 10
.h_accum:
    shl rax, 4
    add rax, rdx
    inc rsi
    jmp .parse_hex

.parse_done:
    ; Clamp to file_size - 1
    mov rdx, [rel file_size]
    test rdx, rdx
    jz .goto_finish
    cmp rax, rdx
    jb .goto_clamp_ok
    mov rax, rdx
    dec rax
.goto_clamp_ok:
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible

    ; Status: Jumped to offset 0x...
    lea rdi, [rel str_buf_1]
    mov rsi, [rel cursor_offset]
    call format_hex_qword

    lea rdi, [rel status_msg_buf]
    lea rsi, [rel status_goto_jump]
.gc1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .gc1
    dec rdi

    lea rsi, [rel str_buf_1]
.gc2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .gc2
    mov dword [rel status_msg_color], COLOR_OFFSET

.goto_finish:
    mov dword [rel editor_mode], MODE_NORMAL
    ret

; ------------------------------------------------------------------------------
; editor_search_next:
; Searches forward from cursor_offset + 1
; ------------------------------------------------------------------------------
global editor_search_next
editor_search_next:
    mov r8, [rel file_ptr]
    test r8, r8
    jz .search_fail

    mov r9, [rel file_size]
    test r9, r9
    jz .search_fail

    mov ecx, [rel search_pat_len]
    test ecx, ecx
    jz .search_fail

    ; Start search from cursor_offset + 1
    mov r10, [rel cursor_offset]
    inc r10
    cmp r10, r9
    jb .start_search
    xor r10d, r10d                    ; wrap around to 0

.start_search:
    ; Max start position = file_size - pat_len
    mov r11, r9
    sub r11, rcx
    cmp r10, r11
    ja .wrap_search

.find_loop:
    ; Compare pat_len bytes at file_ptr + r10 with search_pat
    lea rsi, [r8 + r10]               ; file bytes
    lea rdi, [rel search_pat]         ; search pattern
    mov edx, ecx                      ; length
.cmp_byte:
    mov al, [rsi]
    cmp al, [rdi]
    jne .mismatch
    inc rsi
    inc rdi
    dec edx
    jnz .cmp_byte

    ; MATCH FOUND!
    mov [rel cursor_offset], r10
    mov dword [rel nibble_index], 0
    call editor_ensure_visible

    ; Format found message
    lea rdi, [rel str_buf_1]
    mov rsi, r10
    call format_hex_qword

    lea rdi, [rel status_msg_buf]
    lea rsi, [rel status_found_at]
.sc1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .sc1
    dec rdi

    lea rsi, [rel str_buf_1]
.sc2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .sc2
    mov dword [rel status_msg_color], COLOR_HEX_ASCII
    ret

.mismatch:
    inc r10
    cmp r10, r11
    jbe .find_loop

.wrap_search:
    ; Wrapped search from 0 to cursor_offset
    xor r10d, r10d
    mov r11, [rel cursor_offset]
    cmp r11, r9
    jb .wrap_loop_start
    mov r11, r9
.wrap_loop_start:
    cmp r11, rcx
    jb .search_fail
    sub r11, rcx

.wrap_loop:
    lea rsi, [r8 + r10]
    lea rdi, [rel search_pat]
    mov edx, ecx
.w_cmp:
    mov al, [rsi]
    cmp al, [rdi]
    jne .w_mismatch
    inc rsi
    inc rdi
    dec edx
    jnz .w_cmp

    ; MATCH FOUND IN WRAP!
    mov [rel cursor_offset], r10
    mov dword [rel nibble_index], 0
    call editor_ensure_visible

    lea rdi, [rel str_buf_1]
    mov rsi, r10
    call format_hex_qword

    lea rdi, [rel status_msg_buf]
    lea rsi, [rel status_found_at]
.wsc1:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .wsc1
    dec rdi

    lea rsi, [rel str_buf_1]
.wsc2:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .wsc2
    mov dword [rel status_msg_color], COLOR_HEX_ASCII
    ret

.w_mismatch:
    inc r10
    cmp r10, r11
    jbe .wrap_loop

.search_fail:
    lea rdi, [rel status_not_found]
    mov esi, COLOR_MODIFIED
    call editor_set_status
    ret

editor_commit_search:
    ; Copy input_buf to search_pat
    mov ecx, [rel input_len]
    test ecx, ecx
    jz .no_search_term

    lea rsi, [rel input_buf]
    lea rdi, [rel search_pat]
    mov edx, ecx
    rep movsb
    mov [rel search_pat_len], edx

    mov dword [rel editor_mode], MODE_NORMAL
    call editor_search_next
    ret

.no_search_term:
    mov dword [rel editor_mode], MODE_NORMAL
    ret

; ------------------------------------------------------------------------------
; editor_handle_key:
; rdi = KeySym, rsi = ascii_buf, edx = ascii_len, ecx = state (modifiers)
; ------------------------------------------------------------------------------
global editor_handle_key
editor_handle_key:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte stack alignment

    mov r12, rdi                      ; KeySym
    mov r13, rsi                      ; ascii_buf
    mov r14d, edx                     ; ascii_len
    mov r15d, ecx                     ; state (ControlMask = 4)

    ; --------------------------------------------------------------------------
    ; Check Modal Input Mode (Goto / Search)
    ; --------------------------------------------------------------------------
    cmp dword [rel editor_mode], MODE_NORMAL
    je .handle_normal_mode

    ; In Modal Mode:
    cmp r12, XK_Escape
    je .modal_esc

    cmp r12, XK_Return
    je .modal_enter

    cmp r12, XK_BackSpace
    je .modal_bs

    ; If printable ASCII, append to input_buf
    test r14d, r14d
    jz .key_done

    movzx eax, byte [r13]
    cmp al, 32
    jb .key_done
    cmp al, 126
    ja .key_done

    mov ecx, [rel input_len]
    cmp ecx, 120
    jae .key_done

    lea r8, [rel input_buf]
    mov [r8 + rcx], al
    inc ecx
    mov [rel input_len], ecx
    mov byte [r8 + rcx], 0
    jmp .key_done

.modal_esc:
    call editor_cancel_modal
    jmp .key_done

.modal_enter:
    cmp dword [rel editor_mode], MODE_GOTO
    je .do_goto
    call editor_commit_search
    jmp .key_done
.do_goto:
    call editor_commit_goto
    jmp .key_done

.modal_bs:
    mov ecx, [rel input_len]
    test ecx, ecx
    jz .key_done
    dec ecx
    mov [rel input_len], ecx
    lea r8, [rel input_buf]
    mov byte [r8 + rcx], 0
    jmp .key_done

    ; --------------------------------------------------------------------------
    ; Normal Mode Processing
    ; --------------------------------------------------------------------------
.handle_normal_mode:
    ; Escape clears active selection
    cmp r12, XK_Escape
    je .k_esc

    ; Check for Ctrl shortcuts (state & 4)
    test r15d, 4
    jz .no_ctrl

    ; Ctrl+A: Select All
    cmp r12, 'a'
    je .ctrl_a
    cmp r12, 'A'
    je .ctrl_a

    ; Ctrl+S: Save
    cmp r12, 's'
    je .ctrl_s
    cmp r12, 'S'
    je .ctrl_s

    ; Ctrl+Z: Undo
    cmp r12, 'z'
    je .ctrl_z
    cmp r12, 'Z'
    je .ctrl_z

    ; Ctrl+G: Goto
    cmp r12, 'g'
    je .ctrl_g
    cmp r12, 'G'
    je .ctrl_g

    ; Ctrl+F: Find
    cmp r12, 'f'
    je .ctrl_f
    cmp r12, 'F'
    je .ctrl_f

    ; Ctrl+Q: Quit
    cmp r12, 'q'
    je .ctrl_q
    cmp r12, 'Q'
    je .ctrl_q

    ; Ctrl+Home: Jump to byte 0
    cmp r12, XK_Home
    je .ctrl_home

    ; Ctrl+End: Jump to last byte
    cmp r12, XK_End
    je .ctrl_end

.no_ctrl:
    ; Navigation keys
    cmp r12, XK_Left
    je .nav_left
    cmp r12, XK_Right
    je .nav_right
    cmp r12, XK_Up
    je .nav_up
    cmp r12, XK_Down
    je .nav_down
    cmp r12, XK_Page_Up
    je .nav_pgup
    cmp r12, XK_Page_Down
    je .nav_pgdn
    cmp r12, XK_Home
    je .nav_home
    cmp r12, XK_End
    je .nav_end

    ; Tab / Space: Switch pane
    cmp r12, XK_Tab
    je .k_tab

    ; F2: Flip active file in diff mode
    cmp r12, XK_F2
    je .k_f2

    ; F3: Find next
    cmp r12, XK_F3
    je .k_f3

    ; F7: Previous diff
    cmp r12, XK_F7
    je .k_f7

    ; F8: Next diff
    cmp r12, XK_F8
    je .k_f8

    ; F11: Screenshot
    cmp r12, XK_F11
    je .k_f11

    ; F12: Range Checksums (SHA-256 & CRC-32)
    cmp r12, XK_F12
    je .k_f12

    ; Backspace in Hex or ASCII pane
    cmp r12, XK_BackSpace
    je .k_bs

    ; If in read-only mode, don't allow typing modifications
    cmp dword [rel is_diff_mode], 1
    jne .chk_main_ro
    cmp dword [rel diff_active_file], 1
    jne .chk_main_ro
    cmp dword [rel is_readonly2], 1
    je .key_done
    jmp .chk_pane_edit
.chk_main_ro:
    cmp dword [rel is_readonly], 1
    je .key_done

.chk_pane_edit:
    ; Editing keys
    cmp dword [rel active_pane], PANE_HEX
    je .edit_hex
    jmp .edit_ascii

.k_esc:
    cmp dword [rel has_selection], 1
    jne .key_done
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    jmp .key_done

.ctrl_a:
    call editor_get_diff_max_size
    test rdx, rdx
    jz .key_done
    mov qword [rel sel_start], 0
    dec rdx
    mov [rel sel_end], rdx
    mov [rel cursor_offset], rdx
    mov dword [rel nibble_index], 0
    mov dword [rel has_selection], 1
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_ensure_visible
    jmp .key_done

.nav_left:
    test r15d, ShiftMask
    jnz .shift_left
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_move_left
    jmp .key_done

.shift_left:
    cmp dword [rel has_selection], 0
    jne .sl_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.sl_anchor_done:
    mov rax, [rel cursor_offset]
    test rax, rax
    jz .nav_sel_update
    dec rax
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_right:
    test r15d, ShiftMask
    jnz .shift_right
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_move_right
    jmp .key_done

.shift_right:
    cmp dword [rel has_selection], 0
    jne .sr_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.sr_anchor_done:
    mov rax, [rel cursor_offset]
    call editor_get_diff_max_size
    inc rax
    cmp rax, rdx
    jae .nav_sel_update
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_up:
    test r15d, ShiftMask
    jnz .shift_up
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_move_up
    jmp .key_done

.shift_up:
    cmp dword [rel has_selection], 0
    jne .su_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.su_anchor_done:
    call editor_move_up
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_down:
    test r15d, ShiftMask
    jnz .shift_down
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_move_down
    jmp .key_done

.shift_down:
    cmp dword [rel has_selection], 0
    jne .sd_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.sd_anchor_done:
    call editor_move_down
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_pgup:
    test r15d, ShiftMask
    jnz .shift_pgup
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_page_up
    jmp .key_done

.shift_pgup:
    cmp dword [rel has_selection], 0
    jne .spu_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.spu_anchor_done:
    call editor_page_up
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_pgdn:
    test r15d, ShiftMask
    jnz .shift_pgdn
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_page_down
    jmp .key_done

.shift_pgdn:
    cmp dword [rel has_selection], 0
    jne .spd_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.spd_anchor_done:
    call editor_page_down
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_home:
    test r15d, ShiftMask
    jnz .shift_home
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_home
    jmp .key_done

.shift_home:
    cmp dword [rel has_selection], 0
    jne .sh_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.sh_anchor_done:
    test r15d, ControlMask
    jz .sh_row
    mov qword [rel cursor_offset], 0
    jmp .sh_done
.sh_row:
    call editor_home
.sh_done:
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_end:
    test r15d, ShiftMask
    jnz .shift_end
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_end
    jmp .key_done

.shift_end:
    cmp dword [rel has_selection], 0
    jne .se_anchor_done
    mov rax, [rel cursor_offset]
    mov [rel sel_start], rax
.se_anchor_done:
    test r15d, ControlMask
    jz .se_row
    call editor_get_diff_max_size
    test rdx, rdx
    jz .se_done
    dec rdx
    mov [rel cursor_offset], rdx
    jmp .se_done
.se_row:
    call editor_end
.se_done:
    mov dword [rel nibble_index], 0
    jmp .nav_sel_update

.nav_sel_update:
    call editor_ensure_visible
    mov rax, [rel cursor_offset]
    mov [rel sel_end], rax
    cmp rax, [rel sel_start]
    setne al
    movzx eax, al
    mov [rel has_selection], eax
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    jmp .key_done

.k_tab:
    xor dword [rel active_pane], 1   ; Toggle PANE_HEX <-> PANE_ASCII
    mov dword [rel nibble_index], 0
    jmp .key_done

.k_f2:
    call editor_diff_flip
    jmp .key_done

.k_f3:
    call editor_search_next
    jmp .key_done

.k_f7:
    call editor_diff_prev
    jmp .key_done

.k_f8:
    call editor_diff_next
    jmp .key_done

.k_f11:
    lea rdi, [rel screenshot_file]
    call dump_screenshot
    lea rdi, [rel status_shot_saved]
    mov esi, COLOR_HEX_ASCII
    call editor_set_status
    jmp .key_done

.k_f12:
    call editor_compute_selection_checksum
    jmp .key_done

.k_bs:
    call editor_move_left
    jmp .key_done

.ctrl_s:
    call file_save
    test eax, eax
    jnz .save_err
    lea rdi, [rel status_saved]
    mov esi, COLOR_HEX_ASCII
    call editor_set_status
    mov dword [rel is_dirty], 0
    jmp .key_done
.save_err:
    cmp eax, -1
    je .ro_err
    lea rdi, [rel status_ro_err]
    mov esi, COLOR_MODIFIED
    call editor_set_status
    jmp .key_done
.ro_err:
    lea rdi, [rel status_ro_err]
    mov esi, COLOR_MODIFIED
    call editor_set_status
    jmp .key_done

.ctrl_z:
    call editor_undo
    jmp .key_done

.ctrl_g:
    call editor_start_goto
    jmp .key_done

.ctrl_f:
    call editor_start_search
    jmp .key_done

.ctrl_q:
    ; Clean exit flag
    mov eax, 1                        ; request quit
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.ctrl_home:
    mov qword [rel cursor_offset], 0
    mov dword [rel nibble_index], 0
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_ensure_visible
    jmp .key_done

.ctrl_end:
    call editor_get_diff_max_size
    test rdx, rdx
    jz .key_done
    dec rdx
    mov [rel cursor_offset], rdx
    mov dword [rel nibble_index], 0
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    call editor_ensure_visible
    jmp .key_done

    ; --------------------------------------------------------------------------
    ; Hex Pane Editing (0..9, A..F, a..f)
    ; --------------------------------------------------------------------------
.edit_hex:
    test r14d, r14d
    jz .key_done

    movzx eax, byte [r13]
    ; Check 0..9
    cmp al, '0'
    jb .key_done
    cmp al, '9'
    jbe .hex_digit
    ; Check A..F
    cmp al, 'A'
    jb .check_low_hex
    cmp al, 'F'
    jbe .hex_upper
.check_low_hex:
    cmp al, 'a'
    jb .key_done
    cmp al, 'f'
    ja .key_done
    sub al, 'a' - 10
    jmp .apply_hex_val

.hex_digit:
    sub al, '0'
    jmp .apply_hex_val
.hex_upper:
    sub al, 'A' - 10

.apply_hex_val:
    ; al = 0..15 (nibble value)
    mov ebx, eax                      ; nibble in ebx
    call editor_get_active_file       ; rax = active file_ptr, rdx = active file_size
    test rax, rax
    jz .key_done
    mov r8, rax
    mov r9, [rel cursor_offset]
    cmp r9, rdx
    jae .key_done

    movzx eax, byte [r8 + r9]         ; current byte value
    mov r10d, eax                     ; old byte in r10d

    cmp dword [rel nibble_index], 0
    jne .low_nibble

    ; High nibble: replace bits 7..4
    and eax, 0x0F
    shl ebx, 4
    or eax, ebx
    ; Update byte in memory
    mov [r8 + r9], al
    ; Record undo
    mov rdi, r9
    mov sil, r10b
    mov dl, al
    call editor_record_undo
    mov dword [rel nibble_index], 1
    cmp dword [rel is_diff_mode], 1
    jne .hex_hi_no_diff
    call diff_recompute
.hex_hi_no_diff:
    jmp .key_done

.low_nibble:
    ; Low nibble: replace bits 3..0
    and eax, 0xF0
    and ebx, 0x0F
    or eax, ebx
    ; Update byte in memory
    mov [r8 + r9], al
    ; Record undo
    mov rdi, r9
    mov sil, r10b
    mov dl, al
    call editor_record_undo
    cmp dword [rel is_diff_mode], 1
    jne .hex_lo_no_diff
    call diff_recompute
.hex_lo_no_diff:
    ; Advance cursor to next byte!
    call editor_next_byte
    jmp .key_done

    ; --------------------------------------------------------------------------
    ; ASCII Pane Editing (Printable characters 32..126)
    ; --------------------------------------------------------------------------
.edit_ascii:
    test r14d, r14d
    jz .key_done

    movzx ebx, byte [r13]             ; Preserve character in ebx
    cmp bl, 32
    jb .key_done
    cmp bl, 126
    ja .key_done

    call editor_get_active_file       ; rax = active file_ptr, rdx = active file_size
    test rax, rax
    jz .key_done
    mov r8, rax
    mov r9, [rel cursor_offset]
    cmp r9, rdx
    jae .key_done

    movzx r10d, byte [r8 + r9]        ; old byte
    mov [r8 + r9], bl                 ; write new character

    mov rdi, r9
    mov sil, r10b
    mov dl, bl
    call editor_record_undo
    cmp dword [rel is_diff_mode], 1
    jne .asc_no_diff
    call diff_recompute
.asc_no_diff:

    ; Advance cursor
    call editor_move_right

.key_done:
    xor eax, eax                      ; 0 = keep running
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; editor_handle_click:
; edi = mouse_x, esi = mouse_y
; ------------------------------------------------------------------------------
global editor_handle_click
editor_handle_click:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8                        ; 16-byte alignment (24 + 8 = 32)

    mov r12d, edi                     ; click_x
    mov r13d, esi                     ; click_y

    ; 1. Check Scrollbar Track Hit
    cmp r12d, SCROLLBAR_X
    jl .not_scrollbar
    cmp r12d, SCROLLBAR_X + SCROLLBAR_W
    jge .not_scrollbar
    cmp r13d, SEPARATOR_Y
    jl .not_scrollbar
    mov eax, [rel win_h]
    sub eax, STATUS_H
    cmp r13d, eax
    jge .not_scrollbar

    ; Click is within scrollbar vertical track
    cmp r13d, [rel thumb_y]
    jl .sc_page_up
    mov eax, [rel thumb_y]
    add eax, [rel thumb_h]
    cmp r13d, eax
    jge .sc_page_down

    ; Click is inside scrollbar thumb -> begin thumb dragging
    mov dword [rel is_dragging_scrollbar], 1
    mov [rel drag_mouse_y], r13d
    mov rax, [rel scroll_offset]
    mov [rel drag_scroll_orig], rax
    mov dword [rel has_selection], 0
    mov dword [rel is_selecting], 0
    mov dword [rel last_checksum_valid], 0
    jmp .click_done

.sc_page_up:
    call editor_page_up
    jmp .click_done

.sc_page_down:
    call editor_page_down
    jmp .click_done

.not_scrollbar:
    ; 2. Check Data Rows Area (SEPARATOR_Y < y < win_h - STATUS_H)
    cmp r13d, SEPARATOR_Y
    jle .click_done
    mov eax, [rel win_h]
    sub eax, STATUS_H
    cmp r13d, eax
    jge .click_done

    ; row_idx = (y - (SEPARATOR_Y + 4)) / 16
    mov eax, r13d
    sub eax, SEPARATOR_Y + 4
    cmp eax, 0
    jl .click_done
    shr eax, 4                        ; / 16
    cmp eax, VISIBLE_ROWS
    jae .click_done
    mov ebx, eax                      ; row_idx in ebx

    ; Check Hex Pane click (HEX_START_X <= x < HEX_END_X)
    cmp r12d, HEX_START_X
    jl .check_ascii_click
    cmp r12d, HEX_END_X
    jge .check_ascii_click

    ; Hex column calculation
    mov eax, r12d
    sub eax, HEX_START_X
    ; Check if before group gap (first 8 bytes: 8 * 24 = 192 px)
    cmp eax, 192
    jl .hex_col_0_7
    sub eax, GROUP_GAP
    cmp eax, 192
    jl .click_done
    mov ecx, 24
    xor edx, edx
    div ecx
    cmp eax, 16
    jae .click_done
    jmp .set_cursor_target_hex

.hex_col_0_7:
    mov ecx, 24
    xor edx, edx
    div ecx
    cmp eax, 8
    jae .click_done

.set_cursor_target_hex:
    ; Target offset = scroll_offset + row_idx * 16 + byte_idx (eax)
    mov rdx, [rel scroll_offset]
    shl rbx, 4
    add rdx, rbx
    add rdx, rax
    cmp rdx, [rel file_size]
    jae .click_done

    mov [rel cursor_offset], rdx
    mov dword [rel active_pane], PANE_HEX
    mov dword [rel nibble_index], 0
    mov [rel sel_start], rdx
    mov [rel sel_end], rdx
    mov dword [rel is_selecting], 1
    mov dword [rel has_selection], 0
    mov dword [rel last_checksum_valid], 0
    mov dword [rel is_dragging_scrollbar], 0
    call editor_ensure_visible
    jmp .click_done

.check_ascii_click:
    ; ASCII Pane (ASCII_START_X <= x < ASCII_START_X + 16 * 8)
    cmp r12d, ASCII_START_X
    jl .click_done
    mov eax, r12d
    sub eax, ASCII_START_X
    shr eax, 3                        ; / 8
    cmp eax, 16
    jae .click_done

    mov rdx, [rel scroll_offset]
    shl rbx, 4
    add rdx, rbx
    add rdx, rax
    cmp rdx, [rel file_size]
    jae .click_done

    mov [rel cursor_offset], rdx
    mov dword [rel active_pane], PANE_ASCII
    mov dword [rel nibble_index], 0
    mov [rel sel_start], rdx
    mov [rel sel_end], rdx
    mov dword [rel is_selecting], 1
    mov dword [rel has_selection], 0
    mov dword [rel last_checksum_valid], 0
    mov dword [rel is_dragging_scrollbar], 0
    call editor_ensure_visible

.click_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; editor_handle_mouse_move:
; Handles mouse drag for scrollbar thumb dragging and byte range selection
; edi = mouse_x, esi = mouse_y
; ------------------------------------------------------------------------------
global editor_handle_mouse_move
editor_handle_mouse_move:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12d, edi                     ; x
    mov r13d, esi                     ; y

    ; 1. Scrollbar Dragging
    cmp dword [rel is_dragging_scrollbar], 1
    jne .check_selecting

    ; track_h = win_h - STATUS_H - SEPARATOR_Y
    mov eax, [rel win_h]
    sub eax, STATUS_H
    sub eax, SEPARATOR_Y
    mov ebx, eax                      ; ebx = track_h

    mov ecx, [rel thumb_h]
    sub ebx, ecx                      ; ebx = avail_track
    cmp ebx, 0
    jle .move_done

    ; max_sc = (max_size > 576) ? (max_size - 576 + 15) & ~15 : 0
    call editor_get_diff_max_size
    mov r8, rdx
    cmp r8, 576
    jbe .move_done
    sub r8, 576
    add r8, 15
    and r8, -16                       ; r8 = max_sc

    ; delta_y = y - drag_mouse_y
    mov eax, r13d
    sub eax, [rel drag_mouse_y]
    cdqe                              ; sign-extend to rax (int64)

    ; rax = delta_y * max_sc
    imul rax, r8
    movsxd rcx, ebx
    cqo
    idiv rcx

    ; new_sc = drag_scroll_orig + delta_sc
    add rax, [rel drag_scroll_orig]
    test rax, rax
    jns .sc_not_neg
    xor eax, eax
.sc_not_neg:
    cmp rax, r8
    jle .sc_clamp_max
    mov rax, r8
.sc_clamp_max:
    and rax, -16                      ; align to 16
    mov [rel scroll_offset], rax
    jmp .move_done

.check_selecting:
    ; 2. Range Drag Selection
    cmp dword [rel is_selecting], 1
    jne .move_done

    ; Auto-scroll check
    cmp r13d, SEPARATOR_Y
    jge .check_sc_down
    ; Mouse is above grid: scroll up
    mov rax, [rel scroll_offset]
    cmp rax, 16
    jb .sc_up_zero
    sub rax, 16
    mov [rel scroll_offset], rax
    jmp .calc_sel_offset
.sc_up_zero:
    mov qword [rel scroll_offset], 0
    jmp .calc_sel_offset

.check_sc_down:
    mov eax, [rel win_h]
    sub eax, STATUS_H
    cmp r13d, eax
    jl .calc_sel_offset
    ; Mouse is below grid: scroll down
    mov rax, [rel scroll_offset]
    add rax, 576
    cmp rax, [rel file_size]
    jae .calc_sel_offset
    add qword [rel scroll_offset], 16

.calc_sel_offset:
    ; Calculate row: (y - (SEPARATOR_Y + 4)) / 16
    mov eax, r13d
    sub eax, SEPARATOR_Y + 4
    test eax, eax
    jns .row_not_neg
    xor eax, eax
.row_not_neg:
    shr eax, 4                        ; / 16
    cmp eax, VISIBLE_ROWS
    jl .row_clamp_max
    mov eax, VISIBLE_ROWS - 1
.row_clamp_max:
    mov ebx, eax                      ; ebx = row_idx

    ; Check column based on active_pane
    cmp dword [rel active_pane], PANE_ASCII
    je .calc_ascii_col

    ; Hex Pane Column
    mov eax, r12d
    sub eax, HEX_START_X
    test eax, eax
    jns .hex_x_not_neg
    xor eax, eax
.hex_x_not_neg:
    cmp eax, 192
    jl .hex_col_div
    sub eax, GROUP_GAP
    test eax, eax
    jns .hex_col_div
    xor eax, eax
.hex_col_div:
    mov ecx, 24
    xor edx, edx
    div ecx
    cmp eax, 16
    jl .col_ready
    mov eax, 15
    jmp .col_ready

.calc_ascii_col:
    mov eax, r12d
    sub eax, ASCII_START_X
    test eax, eax
    jns .asc_x_not_neg
    xor eax, eax
.asc_x_not_neg:
    shr eax, 3                        ; / 8
    cmp eax, 16
    jl .col_ready
    mov eax, 15

.col_ready:
    ; Target byte offset = scroll_offset + row * 16 + col (eax)
    mov r8, [rel scroll_offset]
    shl rbx, 4
    add r8, rbx
    add r8, rax                       ; r8 = target offset

    ; Clamp target offset to max_size - 1
    call editor_get_diff_max_size     ; rdx = max_size
    test rdx, rdx
    jz .move_done
    cmp r8, rdx
    jb .target_in_range
    mov r8, rdx
    dec r8                            ; max_size - 1
.target_in_range:
    mov [rel sel_end], r8
    mov [rel cursor_offset], r8

    ; If sel_start != sel_end, has_selection = 1
    mov rax, [rel sel_start]
    cmp rax, r8
    setne al
    movzx eax, al
    mov [rel has_selection], eax

.move_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; editor_handle_button_release:
; edi = mouse_x, esi = mouse_y
; ------------------------------------------------------------------------------
global editor_handle_button_release
editor_handle_button_release:
    mov dword [rel is_dragging_scrollbar], 0
    mov dword [rel is_selecting], 0
    mov rax, [rel sel_start]
    cmp rax, [rel sel_end]
    jne .rel_done
    mov dword [rel has_selection], 0
.rel_done:
    ret

; ------------------------------------------------------------------------------
; editor_handle_wheel:
; edi = button (4 = up, 5 = down)
; ------------------------------------------------------------------------------
global editor_handle_wheel
editor_handle_wheel:
    cmp edi, 4
    je .wheel_up
    cmp edi, 5
    je .wheel_down
    ret

.wheel_up:
    mov rax, [rel scroll_offset]
    cmp rax, 48                       ; 3 rows = 48 bytes
    jb .sc_zero
    sub rax, 48
    mov [rel scroll_offset], rax
    ret
.sc_zero:
    xor eax, eax
    mov [rel scroll_offset], rax
    ret

.wheel_down:
    mov rax, [rel scroll_offset]
    add rax, 48
    call editor_get_diff_max_size
    test rdx, rdx
    jz .wh_done
    cmp rax, rdx
    jb .wh_set
    ret
.wh_set:
    mov [rel scroll_offset], rax
.wh_done:
    ret

; ------------------------------------------------------------------------------
; render_scrollbar:
; Draws the scrollbar track and proportional thumb based on file_size & scroll_offset
; ------------------------------------------------------------------------------
render_scrollbar:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    ; Track dimensions: (SCROLLBAR_X, SEPARATOR_Y, SCROLLBAR_W, track_h)
    mov edi, SCROLLBAR_X
    mov esi, SEPARATOR_Y
    mov edx, SCROLLBAR_W
    mov ecx, [rel win_h]
    sub ecx, SEPARATOR_Y + STATUS_H   ; track_h
    mov r8d, COLOR_SCROLL_TRACK
    mov r12d, ecx                     ; r12d = track_h
    call draw_rect

    ; Compute thumb
    call editor_get_diff_max_size
    mov r8, rdx
    cmp r8, 576
    jbe .sb_full_page

    ; th_h = (track_h * 576) / file_size
    mov eax, r12d
    imul eax, 576
    xor edx, edx
    div r8d
    cmp eax, SCROLL_THUMB_MIN_H
    jge .sb_h_min_ok
    mov eax, SCROLL_THUMB_MIN_H
.sb_h_min_ok:
    cmp eax, r12d
    jle .sb_h_ok
    mov eax, r12d
.sb_h_ok:
    mov [rel thumb_h], eax

    ; max_sc = (file_size - 576 + 15) & ~15
    mov r9, r8
    sub r9, 576
    add r9, 15
    and r9, -16
    test r9, r9
    jnz .sb_max_sc_ok
    mov r9, 1
.sb_max_sc_ok:
    ; avail = track_h - th_h
    mov edx, r12d
    sub edx, eax                      ; edx = avail
    ; th_y = SEPARATOR_Y + (avail * scroll_offset) / max_sc
    mov eax, edx
    imul rax, [rel scroll_offset]
    xor edx, edx
    div r9
    add eax, SEPARATOR_Y
    mov [rel thumb_y], eax
    jmp .sb_draw_thumb

.sb_full_page:
    mov [rel thumb_h], r12d
    mov dword [rel thumb_y], SEPARATOR_Y

.sb_draw_thumb:
    mov edi, SCROLLBAR_X + 1
    mov esi, [rel thumb_y]
    mov edx, SCROLLBAR_W - 2
    mov ecx, [rel thumb_h]
    mov r8d, COLOR_SCROLL_THUMB
    cmp dword [rel is_dragging_scrollbar], 1
    jne .sb_col_ok
    mov r8d, COLOR_SCROLL_ACTIVE
.sb_col_ok:
    call draw_rect

    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; render_row_selection_polygon:
; Encloses selected byte range on this row in a bright translucent polygon
; r13 = row_offset, r14d = row_y
; ------------------------------------------------------------------------------
render_row_selection_polygon:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 40                       ; local vars & alignment

    cmp dword [rel has_selection], 1
    jne .rsp_done

    mov r8, [rel sel_start]
    mov r9, [rel sel_end]
    cmp r8, r9
    jle .rsp_ord
    xchg r8, r9
.rsp_ord:
    mov [rsp + 0], r8                 ; s_min
    mov [rsp + 8], r9                 ; s_max

    ; Check if row [r13, r13 + 15] intersects [s_min, s_max]
    mov rax, r13
    add rax, 15
    cmp rax, r8
    jb .rsp_done
    cmp r13, r9
    ja .rsp_done

    ; c1 = max(r13, s_min) - r13
    mov r10, r13
    cmp r10, r8
    jge .rsp_c1_ok
    mov r10, r8
.rsp_c1_ok:
    sub r10, r13                      ; r10 = c1 (0..15)

    ; c2 = min(r13 + 15, s_max) - r13
    mov r11, rax
    cmp r11, r9
    jle .rsp_c2_ok
    mov r11, r9
.rsp_c2_ok:
    sub r11, r13                      ; r11 = c2 (0..15)

    mov [rsp + 16], r10               ; c1
    mov [rsp + 24], r11               ; c2

    ; --------------------------------------------------------------------------
    ; 1. Hex Pane Selection Polygon
    ; --------------------------------------------------------------------------
    mov eax, r10d
    imul eax, 24
    add eax, HEX_START_X
    cmp r10d, 8
    jl .rsp_h1_nogap
    add eax, 12
.rsp_h1_nogap:
    sub eax, 2
    mov ebx, eax                      ; ebx = hx1

    mov eax, r11d
    imul eax, 24
    add eax, HEX_START_X
    cmp r11d, 8
    jl .rsp_h2_nogap
    add eax, 12
.rsp_h2_nogap:
    add eax, 18                       ; 16 + 2
    mov r15d, eax                     ; r15d = hx2

    ; Fill Translucent Polygon Interior in Hex Pane
    mov edi, ebx                      ; x
    mov esi, r14d                     ; y
    mov edx, r15d
    sub edx, ebx                      ; w = hx2 - hx1
    mov ecx, 16                       ; h = 16
    mov r8d, COLOR_SEL_FILL
    mov r9d, COLOR_SEL_ALPHA
    call draw_rect_alpha

    ; Vertical Perimeter Outlines (Left and Right)
    mov edi, ebx
    mov esi, r14d
    mov edx, r14d
    add edx, 16
    mov ecx, COLOR_SEL_BORDER
    call draw_vline

    mov edi, r15d
    dec edi
    mov esi, r14d
    mov edx, r14d
    add edx, 16
    mov ecx, COLOR_SEL_BORDER
    call draw_vline

    ; Top border: if r13 <= s_min, draw entire hx1..hx2
    mov r8, [rsp + 0]                 ; s_min
    cmp r13, r8
    ja .rsp_hex_step_top
    mov edi, ebx
    mov esi, r15d
    mov edx, r14d
    mov ecx, COLOR_SEL_BORDER
    call draw_hline
    jmp .rsp_hex_check_bot

.rsp_hex_step_top:
    mov rax, r13
    sub rax, 16
    cmp rax, r8
    ja .rsp_hex_check_bot
    mov rcx, r8
    sub rcx, rax                      ; rcx = c_prev
    mov r10, [rsp + 16]               ; c1
    cmp r10, rcx
    jae .rsp_hex_check_bot
    mov eax, ecx
    imul eax, 24
    add eax, HEX_START_X
    cmp ecx, 8
    jl .rsp_step_top_nogap
    add eax, 12
.rsp_step_top_nogap:
    sub eax, 2                        ; eax = hx_prev
    mov edi, ebx                      ; hx1
    mov esi, eax                      ; hx_prev
    mov edx, r14d
    mov ecx, COLOR_SEL_BORDER
    call draw_hline

.rsp_hex_check_bot:
    mov r9, [rsp + 8]                 ; s_max
    mov rax, r13
    add rax, 15
    cmp rax, r9
    jb .rsp_hex_step_bot
    mov edi, ebx
    mov esi, r15d
    mov edx, r14d
    add edx, 15
    mov ecx, COLOR_SEL_BORDER
    call draw_hline
    jmp .rsp_hex_done

.rsp_hex_step_bot:
    mov rax, r13
    add rax, 31
    cmp rax, r9
    jb .rsp_hex_done
    mov rcx, r9
    sub rcx, r13
    sub rcx, 16                       ; rcx = c_next
    mov r11, [rsp + 24]               ; c2
    cmp r11, rcx
    jbe .rsp_hex_done
    inc ecx
    mov eax, ecx
    imul eax, 24
    add eax, HEX_START_X
    cmp ecx, 8
    jl .rsp_step_bot_nogap
    add eax, 12
.rsp_step_bot_nogap:
    sub eax, 2                        ; eax = hx_next
    mov edi, eax
    mov esi, r15d
    mov edx, r14d
    add edx, 15
    mov ecx, COLOR_SEL_BORDER
    call draw_hline

.rsp_hex_done:
    ; --------------------------------------------------------------------------
    ; 2. ASCII Pane Selection Polygon
    ; --------------------------------------------------------------------------
    mov r10, [rsp + 16]               ; c1
    mov r11, [rsp + 24]               ; c2

    mov eax, r10d
    shl eax, 3
    add eax, ASCII_START_X
    mov ebx, eax                      ; ebx = ax1

    mov eax, r11d
    inc eax
    shl eax, 3
    add eax, ASCII_START_X
    mov r15d, eax                     ; r15d = ax2

    ; Translucent Fill in ASCII pane
    mov edi, ebx
    mov esi, r14d
    mov edx, r15d
    sub edx, ebx
    mov ecx, 16
    mov r8d, COLOR_SEL_FILL
    mov r9d, COLOR_SEL_ALPHA
    call draw_rect_alpha

    ; Perimeter vertical lines
    mov edi, ebx
    mov esi, r14d
    mov edx, r14d
    add edx, 16
    mov ecx, COLOR_SEL_BORDER
    call draw_vline

    mov edi, r15d
    dec edi
    mov esi, r14d
    mov edx, r14d
    add edx, 16
    mov ecx, COLOR_SEL_BORDER
    call draw_vline

    ; Top border
    mov r8, [rsp + 0]                 ; s_min
    cmp r13, r8
    ja .rsp_asc_step_top
    mov edi, ebx
    mov esi, r15d
    mov edx, r14d
    mov ecx, COLOR_SEL_BORDER
    call draw_hline
    jmp .rsp_asc_check_bot

.rsp_asc_step_top:
    mov rax, r13
    sub rax, 16
    cmp rax, r8
    ja .rsp_asc_check_bot
    mov rcx, r8
    sub rcx, rax                      ; c_prev
    mov r10, [rsp + 16]               ; c1
    cmp r10, rcx
    jae .rsp_asc_check_bot
    mov eax, ecx
    shl eax, 3
    add eax, ASCII_START_X            ; ax_prev
    mov edi, ebx
    mov esi, eax
    mov edx, r14d
    mov ecx, COLOR_SEL_BORDER
    call draw_hline

.rsp_asc_check_bot:
    mov r9, [rsp + 8]                 ; s_max
    mov rax, r13
    add rax, 15
    cmp rax, r9
    jb .rsp_asc_step_bot
    mov edi, ebx
    mov esi, r15d
    mov edx, r14d
    add edx, 15
    mov ecx, COLOR_SEL_BORDER
    call draw_hline
    jmp .rsp_done

.rsp_asc_step_bot:
    mov rax, r13
    add rax, 31
    cmp rax, r9
    jb .rsp_done
    mov rcx, r9
    sub rcx, r13
    sub rcx, 16                       ; c_next
    mov r11, [rsp + 24]               ; c2
    cmp r11, rcx
    jbe .rsp_done
    inc ecx
    mov eax, ecx
    shl eax, 3
    add eax, ASCII_START_X            ; ax_next
    mov edi, eax
    mov esi, r15d
    mov edx, r14d
    add edx, 15
    mov ecx, COLOR_SEL_BORDER
    call draw_hline

.rsp_done:
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; diff_recompute:
; Counts total differences between file_ptr and file2_ptr
; ------------------------------------------------------------------------------
global diff_recompute
diff_recompute:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    cmp dword [rel is_diff_mode], 1
    jne .dr_zero

    mov r12, [rel file_ptr]
    mov r13, [rel file2_ptr]
    test r12, r12
    jz .dr_zero
    test r13, r13
    jz .dr_zero

    mov r14, [rel file_size]
    mov r15, [rel file2_size]

    mov rcx, r14
    cmp rcx, r15
    jbe .dr_len_ok
    mov rcx, r15
.dr_len_ok:
    xor rbx, rbx                      ; diff count
    xor r8, r8                       ; byte index = 0

    test rcx, rcx
    jz .dr_tail

.dr_cmp_loop:
    mov al, [r12 + r8]
    cmp al, [r13 + r8]
    je .dr_byte_match
    inc rbx
.dr_byte_match:
    inc r8
    cmp r8, rcx
    jl .dr_cmp_loop

.dr_tail:
    mov rax, r14
    sub rax, r15
    jge .dr_tail_pos
    neg rax
.dr_tail_pos:
    add rbx, rax
    mov [rel diff_count], rbx
    jmp .dr_done

.dr_zero:
    mov qword [rel diff_count], 0

.dr_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; editor_diff_next:
; Finds next difference from cursor_offset + 1
; ------------------------------------------------------------------------------
global editor_diff_next
editor_diff_next:
    cmp dword [rel is_diff_mode], 1
    jne .edn_ret

    mov r8, [rel file_ptr]
    mov r9, [rel file2_ptr]
    test r8, r8
    jz .edn_ret
    test r9, r9
    jz .edn_ret

    mov r10, [rel file_size]
    mov r11, [rel file2_size]
    cmp r10, r11
    jae .edn_max_ok
    mov r10, r11
.edn_max_ok:
    test r10, r10
    jz .edn_ret

    mov rax, [rel cursor_offset]
    inc rax

.edn_search:
    cmp rax, r10
    jae .edn_wrap

    cmp rax, [rel file_size]
    jae .edn_found
    cmp rax, [rel file2_size]
    jae .edn_found
    mov cl, [r8 + rax]
    cmp cl, [r9 + rax]
    jne .edn_found
    inc rax
    jmp .edn_search

.edn_wrap:
    xor rax, rax
.edn_wrap_loop:
    cmp rax, [rel cursor_offset]
    jae .edn_none_found

    cmp rax, [rel file_size]
    jae .edn_found
    cmp rax, [rel file2_size]
    jae .edn_found
    mov cl, [r8 + rax]
    cmp cl, [r9 + rax]
    jne .edn_found
    inc rax
    jmp .edn_wrap_loop

.edn_found:
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible
    lea rdi, [rel status_diff_nav]
    mov esi, COLOR_DIFF_FG
    call editor_set_status
    ret

.edn_none_found:
    lea rdi, [rel status_no_diffs]
    mov esi, COLOR_HEX_ASCII
    call editor_set_status

.edn_ret:
    ret

; ------------------------------------------------------------------------------
; editor_diff_prev:
; Finds previous difference from cursor_offset - 1
; ------------------------------------------------------------------------------
global editor_diff_prev
editor_diff_prev:
    cmp dword [rel is_diff_mode], 1
    jne .edp_ret

    mov r8, [rel file_ptr]
    mov r9, [rel file2_ptr]
    test r8, r8
    jz .edp_ret
    test r9, r9
    jz .edp_ret

    mov rax, [rel cursor_offset]
    test rax, rax
    jz .edp_wrap
    dec rax

.edp_search:
    cmp rax, [rel file_size]
    jae .edp_found
    cmp rax, [rel file2_size]
    jae .edp_found
    mov cl, [r8 + rax]
    cmp cl, [r9 + rax]
    jne .edp_found
    test rax, rax
    jz .edp_wrap
    dec rax
    jmp .edp_search

.edp_wrap:
    mov rax, [rel file_size]
    mov r11, [rel file2_size]
    cmp rax, r11
    jae .edp_wrap_max
    mov rax, r11
.edp_wrap_max:
    test rax, rax
    jz .edp_none
    dec rax

.edp_wrap_loop:
    cmp rax, [rel cursor_offset]
    jbe .edp_none

    cmp rax, [rel file_size]
    jae .edp_found
    cmp rax, [rel file2_size]
    jae .edp_found
    mov cl, [r8 + rax]
    cmp cl, [r9 + rax]
    jne .edp_found
    dec rax
    jmp .edp_wrap_loop

.edp_found:
    mov [rel cursor_offset], rax
    mov dword [rel nibble_index], 0
    call editor_ensure_visible
    lea rdi, [rel status_diff_nav]
    mov esi, COLOR_DIFF_FG
    call editor_set_status
    ret

.edp_none:
    lea rdi, [rel status_no_diffs]
    mov esi, COLOR_HEX_ASCII
    call editor_set_status

.edp_ret:
    ret

; ------------------------------------------------------------------------------
; editor_diff_flip:
; Toggles active display file between File 1 and File 2
; ------------------------------------------------------------------------------
global editor_diff_flip
editor_diff_flip:
    cmp dword [rel is_diff_mode], 1
    jne .edf_ret
    xor dword [rel diff_active_file], 1
    cmp dword [rel diff_active_file], 1
    jne .edf_f1
    lea rdi, [rel status_flipped_2]
    jmp .edf_set
.edf_f1:
    lea rdi, [rel status_flipped_1]
.edf_set:
    mov esi, COLOR_HEX_SPECIAL
    call editor_set_status
.edf_ret:
    ret

; ------------------------------------------------------------------------------
; render_diff_inspector:
; Displays Diff statistics, active file, File 1 vs File 2 byte values and match status
; ------------------------------------------------------------------------------
render_diff_inspector:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    cmp dword [rel is_diff_mode], 1
    jne .rdi_done

    mov rbx, [rel cursor_offset]

    ; Section Title: ── FILE DIFF (F2) ──
    lea rdi, [rel insp_sec_diff]
    mov esi, INSPECTOR_X
    mov edx, 328
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Line 1: Diffs count
    lea rdi, [rel insp_diff_cnt]
    mov esi, INSPECTOR_X
    mov edx, 348
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, [rel diff_count]
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 88
    mov edx, 348
    mov ecx, COLOR_DIFF_FG
    cmp qword [rel diff_count], 0
    jne .draw_diff_cnt
    mov ecx, COLOR_DIFF_MATCH
.draw_diff_cnt:
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Line 2: Active file (1 or 2)
    lea rdi, [rel insp_diff_active]
    mov esi, INSPECTOR_X
    mov edx, 366
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov byte [rdi], '1'
    cmp dword [rel diff_active_file], 1
    jne .draw_act_file
    mov byte [rdi], '2'
.draw_act_file:
    mov byte [rdi + 1], 0
    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 104
    mov edx, 366
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Line 3: File 1 byte value at cursor
    lea rdi, [rel insp_diff_f1_val]
    mov esi, INSPECTOR_X
    mov edx, 384
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    cmp rbx, [rel file_size]
    jae .f1_eof

    mov rax, [rel file_ptr]
    movzx r12d, byte [rax + rbx]      ; r12d = file1 byte

    lea r9, [rel hex_lut]
    movzx eax, word [r9 + r12 * 2]
    mov [rel str_buf_1], al
    mov [rel str_buf_1 + 1], ah
    mov byte [rel str_buf_1 + 2], ' '
    mov byte [rel str_buf_1 + 3], '('
    mov byte [rel str_buf_1 + 4], "'"
    mov al, r12b
    cmp al, 32
    jb .f1_dot
    cmp al, 126
    jbe .f1_ch_ok
.f1_dot:
    mov al, '.'
.f1_ch_ok:
    mov [rel str_buf_1 + 5], al
    mov byte [rel str_buf_1 + 6], "'"
    mov byte [rel str_buf_1 + 7], ')'
    mov byte [rel str_buf_1 + 8], 0
    jmp .draw_f1_val

.f1_eof:
    lea rsi, [rel insp_diff_eof]
    lea rdi, [rel str_buf_1]
    mov ecx, 10
    rep movsb

.draw_f1_val:
    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 88
    mov edx, 384
    mov ecx, COLOR_DIFF_PEER
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Line 4: File 2 byte value at cursor
    lea rdi, [rel insp_diff_f2_val]
    mov esi, INSPECTOR_X
    mov edx, 402
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    cmp rbx, [rel file2_size]
    jae .f2_eof

    mov rax, [rel file2_ptr]
    movzx r13d, byte [rax + rbx]      ; r13d = file2 byte

    lea r9, [rel hex_lut]
    movzx eax, word [r9 + r13 * 2]
    mov [rel str_buf_1], al
    mov [rel str_buf_1 + 1], ah
    mov byte [rel str_buf_1 + 2], ' '
    mov byte [rel str_buf_1 + 3], '('
    mov byte [rel str_buf_1 + 4], "'"
    mov al, r13b
    cmp al, 32
    jb .f2_dot
    cmp al, 126
    jbe .f2_ch_ok
.f2_dot:
    mov al, '.'
.f2_ch_ok:
    mov [rel str_buf_1 + 5], al
    mov byte [rel str_buf_1 + 6], "'"
    mov byte [rel str_buf_1 + 7], ')'
    mov byte [rel str_buf_1 + 8], 0
    jmp .draw_f2_val

.f2_eof:
    lea rsi, [rel insp_diff_eof]
    lea rdi, [rel str_buf_1]
    mov ecx, 10
    rep movsb

.draw_f2_val:
    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 88
    mov edx, 402
    mov ecx, COLOR_DIFF_PEER
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Line 5: Match status (MISMATCH [!=] or IDENTICAL [==])
    lea rdi, [rel insp_diff_status]
    mov esi, INSPECTOR_X
    mov edx, 420
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Compare values
    cmp rbx, [rel file_size]
    jae .st_mismatch
    cmp rbx, [rel file2_size]
    jae .st_mismatch
    cmp r12b, r13b
    jne .st_mismatch

    lea rdi, [rel insp_diff_match]
    mov ecx, COLOR_DIFF_MATCH
    jmp .draw_match_st

.st_mismatch:
    lea rdi, [rel insp_diff_mismatch]
    mov ecx, COLOR_DIFF_FG

.draw_match_st:
    mov esi, INSPECTOR_X + 88
    mov edx, 420
    mov r8d, COLOR_PANEL_BG
    call draw_string

.rdi_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; render_selection_inspector:
; Displays Selection Range, Length, and F12 Checksums in Inspector panel
; ------------------------------------------------------------------------------
render_selection_inspector:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte stack alignment (40 + 8 = 48)

    cmp dword [rel has_selection], 1
    jne .check_checksum_display

    mov r14d, 328
    cmp dword [rel is_diff_mode], 1
    jne .draw_sel_hdr
    mov r14d, 442

.draw_sel_hdr:
    lea rdi, [rel insp_sec_sel]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    mov r8, [rel sel_start]
    mov r9, [rel sel_end]
    cmp r8, r9
    jle .rsi_ord
    xchg r8, r9
.rsi_ord:
    mov r12, r8                       ; min
    mov r13, r9                       ; max

    add r14d, 18
    lea rdi, [rel insp_sel_range]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, r12
    call format_hex_dword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 80
    mov edx, r14d
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel insp_sel_dots]
    mov esi, INSPECTOR_X + 144
    mov edx, r14d
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, r13
    call format_hex_dword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 176
    mov edx, r14d
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 18
    lea rdi, [rel insp_sel_len]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    mov rax, r13
    sub rax, r12
    inc rax                           ; len
    mov r12, rax

    lea rdi, [rel str_buf_1]
    mov rsi, r12
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 64
    mov edx, r14d
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PANEL_BG
    call draw_string

.check_checksum_display:
    cmp dword [rel last_checksum_valid], 1
    jne .rsi_done

    mov r14d, 328
    cmp dword [rel is_diff_mode], 1
    jne .chk_cs_sel
    mov r14d, 442

.chk_cs_sel:
    cmp dword [rel has_selection], 1
    jne .draw_checksum_block
    add r14d, 46                      ; Place below selection info

.draw_checksum_block:
    ; Section Header: ── CHECKSUMS (F12) ──
    lea rdi, [rel insp_sec_hash]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; CRC-32 Label
    add r14d, 18
    lea rdi, [rel insp_crc_lbl]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; CRC-32 Value
    lea rdi, [rel str_buf_1]
    mov esi, [rel last_crc32]
    call format_hex_dword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 88
    mov edx, r14d
    mov ecx, COLOR_HEX_ASCII
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; SHA-256 Label
    add r14d, 18
    lea rdi, [rel insp_sha_lbl]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; First 32 hex characters
    add r14d, 16
    lea rsi, [rel last_sha256_hex]
    lea rdi, [rel str_buf_1]
    mov ecx, 32
.cp_p1:
    mov al, [rsi + rcx - 1]
    mov [rdi + rcx - 1], al
    dec ecx
    jnz .cp_p1
    mov byte [rel str_buf_1 + 32], 0

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_HEX_SPECIAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Second 32 hex characters
    add r14d, 16
    lea rsi, [rel last_sha256_hex + 32]
    lea rdi, [rel str_buf_1]
    mov ecx, 32
.cp_p2:
    mov al, [rsi + rcx - 1]
    mov [rdi + rcx - 1], al
    dec ecx
    jnz .cp_p2
    mov byte [rel str_buf_1 + 32], 0

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_HEX_SPECIAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

.rsi_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; editor_compute_selection_checksum:
; Calculates CRC32 and SHA256 over current selection (or whole file if no selection)
; ------------------------------------------------------------------------------
global editor_compute_selection_checksum
editor_compute_selection_checksum:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte stack alignment

    ; 1. Check if active file is open / size > 0
    call editor_get_active_file       ; rax = active file_ptr, rdx = active file_size
    mov r14, rdx
    test r14, r14
    jz .calc_empty
    test rax, rax
    jz .calc_empty
    mov r15, rax                      ; r15 = active base ptr

    ; 2. Determine target range
    cmp dword [rel has_selection], 1
    jne .use_whole_file

    mov r12, [rel sel_start]
    mov r13, [rel sel_end]
    cmp r12, r13
    jle .range_ordered
    xchg r12, r13
.range_ordered:
    cmp r12, r14
    jae .calc_empty
    cmp r13, r14
    jb .end_in_range
    mov r13, r14
    dec r13
.end_in_range:
    mov rbx, r13
    sub rbx, r12
    inc rbx                           ; rbx = length
    jmp .do_calc

.use_whole_file:
    xor r12, r12                      ; offset = 0
    mov rbx, r14                      ; length = active size

.do_calc:
    mov [rel last_checksum_off], r12
    mov [rel last_checksum_len], rbx

    ; Data pointer: [active file_ptr] + r12
    lea rdi, [r15 + r12]
    mov rsi, rbx

    ; Compute CRC32
    push rdi
    push rsi
    call compute_crc32
    mov [rel last_crc32], eax
    pop rsi
    pop rdi

    ; Compute SHA256
    lea rdx, [rel last_sha256_digest]
    call compute_sha256

    ; Format SHA256 hex string
    lea rdi, [rel last_sha256_digest]
    lea rsi, [rel last_sha256_hex]
    call format_sha256_hex

    mov dword [rel last_checksum_valid], 1

    ; Format Status Bar text: "CRC32: 0xXXXXXXXX | SHA256: <64-hex>"
    lea rdi, [rel status_hash_buf]
    mov byte [rdi + 0], 'C'
    mov byte [rdi + 1], 'R'
    mov byte [rdi + 2], 'C'
    mov byte [rdi + 3], '3'
    mov byte [rdi + 4], '2'
    mov byte [rdi + 5], ':'
    mov byte [rdi + 6], ' '
    mov byte [rdi + 7], '0'
    mov byte [rdi + 8], 'x'

    lea rdi, [rel status_hash_buf + 9]
    mov esi, [rel last_crc32]
    call format_hex_dword

    lea rdi, [rel status_hash_buf + 17]
    mov byte [rdi + 0], ' '
    mov byte [rdi + 1], '|'
    mov byte [rdi + 2], ' '
    mov byte [rdi + 3], 'S'
    mov byte [rdi + 4], 'H'
    mov byte [rdi + 5], 'A'
    mov byte [rdi + 6], '2'
    mov byte [rdi + 7], '5'
    mov byte [rdi + 8], '6'
    mov byte [rdi + 9], ':'
    mov byte [rdi + 10], ' '

    lea rsi, [rel last_sha256_hex]
    lea rdi, [rel status_hash_buf + 28]
    mov ecx, 65
.cpy_sha_stat:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .cpy_sha_stat

    ; Display in status line
    lea rdi, [rel status_hash_buf]
    mov esi, COLOR_HEX_ASCII
    call editor_set_status

    ; Log to stdout
    lea rdi, [rel fmt_checksum_log]
    mov rsi, [rel last_checksum_off]
    mov rdx, [rel last_checksum_off]
    add rdx, [rel last_checksum_len]
    dec rdx                           ; end offset
    mov rcx, [rel last_checksum_len]
    mov r8d, [rel last_crc32]
    lea r9, [rel last_sha256_hex]
    xor eax, eax
    call printf wrt ..plt
    jmp .calc_done

.calc_empty:
    mov dword [rel last_checksum_valid], 1
    mov dword [rel last_crc32], 0
    mov qword [rel last_checksum_off], 0
    mov qword [rel last_checksum_len], 0

    lea rsi, [rel empty_sha256_str]
    lea rdi, [rel last_sha256_hex]
    mov ecx, 65
.cpy_empty_sha:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .cpy_empty_sha

    lea rdi, [rel status_hash_empty]
    mov esi, COLOR_HEX_SPECIAL
    call editor_set_status

    lea rdi, [rel fmt_checksum_empty]
    xor eax, eax
    call printf wrt ..plt

.calc_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ==============================================================================
; editor_render:
; Master screen rendering routine (draws header, data grid, inspector, and status)
; ==============================================================================
global editor_render
editor_render:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte stack alignment (40 + 8 = 48)

    ; 1. Draw Panel Backgrounds
    ; Top Header: (0, 0, win_w, HEADER_H)
    xor edi, edi
    xor esi, esi
    mov edx, [rel win_w]
    mov ecx, HEADER_H
    mov r8d, COLOR_HEADER_BG
    call draw_rect

    ; Column Header bar background (0, HEADER_H, win_w, COL_HDR_H)
    xor edi, edi
    mov esi, HEADER_H
    mov edx, [rel win_w]
    mov ecx, COL_HDR_H
    mov r8d, COLOR_HEADER_BG
    call draw_rect

    ; Data Pane background: (0, SEPARATOR_Y, DATA_PANE_W, win_h - SEPARATOR_Y - STATUS_H)
    xor edi, edi
    mov esi, SEPARATOR_Y
    mov edx, DATA_PANE_W
    mov ecx, [rel win_h]
    sub ecx, SEPARATOR_Y + STATUS_H
    mov r8d, COLOR_BG
    call draw_rect

    ; Inspector Pane background: (DATA_PANE_W, SEPARATOR_Y, win_w - DATA_PANE_W, ...)
    mov edi, DATA_PANE_W
    mov esi, SEPARATOR_Y
    mov edx, [rel win_w]
    sub edx, DATA_PANE_W
    mov ecx, [rel win_h]
    sub ecx, SEPARATOR_Y + STATUS_H
    mov r8d, COLOR_PANEL_BG
    call draw_rect

    ; Status Bar background: (0, win_h - STATUS_H, win_w, STATUS_H)
    xor edi, edi
    mov esi, [rel win_h]
    sub esi, STATUS_H
    mov edx, [rel win_w]
    mov ecx, STATUS_H
    mov r8d, COLOR_STATUS_BG
    call draw_rect

    ; Separator lines
    ; Horizontal under column header
    xor edi, edi
    mov esi, [rel win_w]
    mov edx, SEPARATOR_Y
    mov ecx, COLOR_BORDER
    call draw_hline

    ; Horizontal above status bar
    xor edi, edi
    mov esi, [rel win_w]
    mov edx, [rel win_h]
    sub edx, STATUS_H
    mov ecx, COLOR_BORDER
    call draw_hline

    ; Vertical between data pane and inspector pane
    mov edi, PANEL_DIVIDER_X
    mov esi, HEADER_H
    mov edx, [rel win_h]
    sub edx, STATUS_H
    mov ecx, COLOR_BORDER
    call draw_vline

    ; --------------------------------------------------------------------------
    ; 2. Render Header Bar Contents
    ; --------------------------------------------------------------------------
    lea rdi, [rel title_str]
    mov esi, 12
    mov edx, 8
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_HEADER_BG
    call draw_string

    lea rdi, [rel sub_title]
    mov esi, 140
    mov edx, 8
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_HEADER_BG
    call draw_string

    cmp dword [rel is_diff_mode], 1
    jne .single_file_hdr

    ; Draw tag_diff at x = 380
    lea rdi, [rel tag_diff]
    mov esi, 380
    mov edx, 8
    mov ecx, COLOR_DIFF_FG
    mov r8d, COLOR_DIFF_BG
    call draw_string

    ; Draw File 1 path at x = 490
    lea rdi, [rel file_path]
    mov esi, 490
    mov edx, 8
    mov ecx, COLOR_TEXT_NORMAL
    cmp dword [rel diff_active_file], 0
    jne .hdr_f1_not_active
    mov ecx, COLOR_INSP_VAL
.hdr_f1_not_active:
    mov r8d, COLOR_HEADER_BG
    call draw_string

    ; Draw "<=>" at x = 680
    lea rdi, [rel str_diff_sep]
    mov esi, 680
    mov edx, 8
    mov ecx, COLOR_DIFF_PEER
    mov r8d, COLOR_HEADER_BG
    call draw_string

    ; Draw File 2 path at x = 720
    lea rdi, [rel file2_path]
    mov esi, 720
    mov edx, 8
    mov ecx, COLOR_TEXT_NORMAL
    cmp dword [rel diff_active_file], 1
    jne .hdr_f2_not_active
    mov ecx, COLOR_INSP_VAL
.hdr_f2_not_active:
    mov r8d, COLOR_HEADER_BG
    call draw_string
    jmp .header_done

.single_file_hdr:
    ; Draw file path at x = 450
    lea rdi, [rel file_path]
    mov esi, 450
    mov edx, 8
    mov ecx, COLOR_TEXT_NORMAL
    mov r8d, COLOR_HEADER_BG
    call draw_string

    ; Draw tags ([MODIFIED], [READ-ONLY], [SCRATCH])
    mov r12d, 820
    cmp dword [rel is_dirty], 1
    jne .chk_ro_tag
    lea rdi, [rel tag_mod]
    mov esi, r12d
    mov edx, 8
    mov ecx, COLOR_MODIFIED
    mov r8d, COLOR_HEADER_BG
    call draw_string
    add r12d, 100

.chk_ro_tag:
    cmp dword [rel is_readonly], 1
    jne .chk_scratch_tag
    lea rdi, [rel tag_ro]
    mov esi, r12d
    mov edx, 8
    mov ecx, COLOR_HEX_CTRL
    mov r8d, COLOR_HEADER_BG
    call draw_string
    add r12d, 100

.chk_scratch_tag:
    cmp dword [rel is_scratch], 1
    jne .header_done
    lea rdi, [rel tag_scratch]
    mov esi, r12d
    mov edx, 8
    mov ecx, COLOR_OFFSET
    mov r8d, COLOR_HEADER_BG
    call draw_string

.header_done:
    ; --------------------------------------------------------------------------
    ; 3. Render Column Header Bar
    ; --------------------------------------------------------------------------
    lea rdi, [rel col_hdr_offset]
    mov esi, OFFSET_X
    mov edx, 34
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_HEADER_BG
    call draw_string

    lea rdi, [rel col_hdr_hex]
    mov esi, HEX_START_X
    mov edx, 34
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_HEADER_BG
    call draw_string

    lea rdi, [rel col_hdr_ascii]
    mov esi, ASCII_START_X
    mov edx, 34
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_HEADER_BG
    call draw_string

    ; --------------------------------------------------------------------------
    ; 3B. Render Scrollbar Track & Proportional Thumb
    ; --------------------------------------------------------------------------
    call render_scrollbar

    ; --------------------------------------------------------------------------
    ; 4. Render Data Grid Rows
    ; --------------------------------------------------------------------------
    xor r12d, r12d                    ; r12d = row_index (0..VISIBLE_ROWS-1)

.row_render_loop:
    cmp r12d, VISIBLE_ROWS
    jae .rows_done

    ; row_offset = scroll_offset + r12 * 16
    mov r13, [rel scroll_offset]
    mov rax, r12
    shl rax, 4
    add r13, rax                      ; r13 = row_offset

    call editor_get_diff_max_size
    cmp r13, rdx
    jae .rows_done

    ; row_y = SEPARATOR_Y + 6 + r12 * 16
    mov r14d, r12d
    shl r14d, 4
    add r14d, SEPARATOR_Y + 6         ; r14d = row_y

    ; A. Draw 16-hex-digit Offset
    lea rdi, [rel str_buf_1]
    mov rsi, r13
    call format_hex_qword

    lea rdi, [rel str_buf_1]
    mov esi, OFFSET_X
    mov edx, r14d
    mov ecx, COLOR_OFFSET
    mov r8d, COLOR_BG
    call draw_string

    ; Draw Gutter separator '|'
    lea rdi, [rel str_gutter_sep]
    mov esi, GUTTER_SEP_X
    mov edx, r14d
    mov ecx, COLOR_DIVIDER
    mov r8d, COLOR_BG
    call draw_string

    ; Render bright translucent selection polygon on this row (if in range)
    call render_row_selection_polygon

    ; B. Draw 16 Hex Bytes & 16 ASCII Characters
    xor r15d, r15d                    ; r15d = byte_index (0..15)

.byte_render_loop:
    cmp r15d, 16
    jae .row_bytes_done

    ; byte_offset = row_offset + r15
    mov rbx, r13
    add rbx, r15                      ; rbx = byte_offset

    call editor_get_diff_max_size
    cmp rbx, rdx
    jae .row_bytes_done

    ; Check if byte is mismatch in diff mode
    xor r8d, r8d                      ; r8d = is_diff (0 or 1)
    cmp dword [rel is_diff_mode], 1
    jne .chk_b_val
    cmp rbx, [rel file_size]
    jae .b_diff_yes
    cmp rbx, [rel file2_size]
    jae .b_diff_yes
    mov rax, [rel file_ptr]
    mov rdx, [rel file2_ptr]
    mov al, [rax + rbx]
    cmp al, [rdx + rbx]
    je .chk_b_val
.b_diff_yes:
    mov r8d, 1

.chk_b_val:
    ; Read byte from active file
    call editor_get_active_file       ; rax = active ptr, rdx = active size
    xor ecx, ecx                      ; ecx = byte value
    xor r9d, r9d                      ; r9d = has_byte (0 or 1)
    cmp rbx, rdx
    jae .b_act_eof
    movzx ecx, byte [rax + rbx]
    mov r9d, 1
.b_act_eof:

    ; Check if byte is in active selection range
    cmp dword [rel has_selection], 1
    jne .not_in_selection
    mov r10, [rel sel_start]
    mov r11, [rel sel_end]
    cmp r10, r11
    jle .bs_ord
    xchg r10, r11
.bs_ord:
    cmp rbx, r10
    jb .not_in_selection
    cmp rbx, r11
    ja .not_in_selection

    ; BYTE IS IN SELECTION!
    ; 1. Draw Hex Digits Transparently over polygon fill
    mov edx, r15d
    imul edx, BYTE_SPACING
    add edx, HEX_START_X
    cmp r15d, 8
    jl .sel_no_gap
    add edx, GROUP_GAP
.sel_no_gap:
    ; edx = hex_x

    test r9d, r9d
    jz .sel_eof_hex

    ; char 0 (high nibble)
    push rcx
    push rdx
    mov edi, edx
    mov esi, r14d
    lea r10, [rel hex_lut]
    movzx edx, byte [r10 + rcx * 2]
    mov ecx, COLOR_SEL_TEXT
    call draw_glyph_transparent
    pop rdx
    pop rcx

    ; char 1 (low nibble)
    push rcx
    push rdx
    mov edi, edx
    add edi, FONT_W
    mov esi, r14d
    lea r10, [rel hex_lut]
    movzx edx, byte [r10 + rcx * 2 + 1]
    mov ecx, COLOR_SEL_TEXT
    call draw_glyph_transparent
    pop rdx
    pop rcx
    jmp .sel_ascii

.sel_eof_hex:
    push rdx
    mov edi, edx
    mov esi, r14d
    mov edx, '-'
    mov ecx, COLOR_SEL_TEXT
    call draw_glyph_transparent
    pop rdx

    mov edi, edx
    add edi, FONT_W
    mov esi, r14d
    mov edx, '-'
    mov ecx, COLOR_SEL_TEXT
    call draw_glyph_transparent

.sel_ascii:
    ; 2. Draw ASCII preview Transparently over polygon fill
    mov edi, r15d
    shl edi, 3
    add edi, ASCII_START_X
    mov esi, r14d
    mov edx, ecx                      ; byte value
    test r9d, r9d
    jz .sel_eof_asc
    cmp dl, 32
    jb .sel_dot
    cmp dl, 126
    jbe .sel_ch_ok
.sel_dot:
    mov dl, '.'
.sel_ch_ok:
    jmp .sel_draw_asc
.sel_eof_asc:
    mov dl, '.'
.sel_draw_asc:
    mov ecx, COLOR_SEL_TEXT
    call draw_glyph_transparent

    inc r15d
    jmp .byte_render_loop

.not_in_selection:
    ; Calculate Hex X coordinate
    mov edx, r15d
    imul edx, BYTE_SPACING
    add edx, HEX_START_X
    cmp r15d, 8
    jl .no_group_gap
    add edx, GROUP_GAP
.no_group_gap:
    ; edx = hex_x

    ; Determine Hex Colors (fg in r10d, bg in r11d)
    mov r11d, COLOR_BG
    cmp rbx, [rel cursor_offset]
    jne .not_cursor_hex

    ; Cursor byte!
    cmp dword [rel active_pane], PANE_HEX
    jne .peer_cursor_hex
    mov r11d, COLOR_CURSOR_BG
    mov r10d, COLOR_CURSOR_FG
    jmp .draw_hex_cell

.peer_cursor_hex:
    mov r11d, COLOR_CURSOR_PEER
    mov r10d, COLOR_TEXT_BRIGHT
    jmp .draw_hex_cell

.not_cursor_hex:
    test r8d, r8d
    jz .check_modified_hex
    ; Differing byte in diff mode!
    mov r11d, COLOR_DIFF_BG
    mov r10d, COLOR_DIFF_FG
    jmp .draw_hex_cell

.check_modified_hex:
    push rdx
    push rcx
    push r8
    push r9
    mov rdi, rbx
    call editor_is_byte_modified
    test eax, eax
    pop r9
    pop r8
    pop rcx
    pop rdx
    jz .check_byte_syntax_color
    mov r10d, COLOR_MODIFIED
    jmp .draw_hex_cell

.check_byte_syntax_color:
    test r9d, r9d
    jnz .has_byte_syntax
    mov r10d, COLOR_TEXT_DIM
    jmp .draw_hex_cell

.has_byte_syntax:
    test cl, cl
    jnz .not_zero
    mov r10d, COLOR_HEX_ZERO
    jmp .draw_hex_cell
.not_zero:
    cmp cl, 32
    jb .ctrl_byte
    cmp cl, 126
    ja .special_byte
    mov r10d, COLOR_HEX_ASCII
    jmp .draw_hex_cell
.ctrl_byte:
    mov r10d, COLOR_HEX_CTRL
    jmp .draw_hex_cell
.special_byte:
    mov r10d, COLOR_HEX_SPECIAL

.draw_hex_cell:
    test r9d, r9d
    jz .draw_eof_hex

    ; Draw two hex glyphs (cl = byte value, edx = hex_x, r10d = fg, r11d = bg)
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov edi, edx
    mov esi, r14d
    lea rax, [rel hex_lut]
    movzx edx, byte [rax + rcx * 2]
    mov ecx, r10d
    mov r8d, r11d
    call draw_glyph

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx

    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov edi, edx
    add edi, FONT_W
    mov esi, r14d
    lea rax, [rel hex_lut]
    movzx edx, byte [rax + rcx * 2 + 1]
    mov ecx, r10d
    mov r8d, r11d
    call draw_glyph

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    jmp .draw_ascii_cell

.draw_eof_hex:
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov edi, edx
    mov esi, r14d
    mov edx, '-'
    mov ecx, r10d
    mov r8d, r11d
    call draw_glyph

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx

    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    mov edi, edx
    add edi, FONT_W
    mov esi, r14d
    mov edx, '-'
    mov ecx, r10d
    mov r8d, r11d
    call draw_glyph

    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx

.draw_ascii_cell:
    ; --------------------------------------------------------------------------
    ; Draw ASCII preview character
    ; --------------------------------------------------------------------------
    mov edi, r15d
    shl edi, 3                        ; * 8
    add edi, ASCII_START_X
    mov esi, r14d

    ; Determine display character
    test r9d, r9d
    jz .dot_char
    mov edx, ecx                      ; byte value
    cmp dl, 32
    jb .dot_char
    cmp dl, 126
    jbe .char_ok
.dot_char:
    mov dl, '.'
.char_ok:

    ; Determine ASCII colors
    mov r11d, COLOR_BG
    cmp rbx, [rel cursor_offset]
    jne .not_cursor_ascii

    cmp dword [rel active_pane], PANE_ASCII
    jne .peer_cursor_ascii
    mov r11d, COLOR_CURSOR_BG
    mov r10d, COLOR_CURSOR_FG
    jmp .draw_ascii_glyph

.peer_cursor_ascii:
    mov r11d, COLOR_CURSOR_PEER
    mov r10d, COLOR_TEXT_BRIGHT
    jmp .draw_ascii_glyph

.not_cursor_ascii:
    test r8d, r8d
    jz .check_modified_ascii
    ; Diff byte!
    mov r11d, COLOR_DIFF_BG
    mov r10d, COLOR_DIFF_FG
    jmp .draw_ascii_glyph

.check_modified_ascii:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    mov rdi, rbx
    call editor_is_byte_modified
    test eax, eax
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    jz .ascii_syntax_color
    mov r10d, COLOR_MODIFIED
    jmp .draw_ascii_glyph

.ascii_syntax_color:
    cmp dl, '.'
    jne .ascii_normal
    mov r10d, COLOR_HEX_ZERO
    jmp .draw_ascii_glyph
.ascii_normal:
    mov r10d, COLOR_TEXT_NORMAL

.draw_ascii_glyph:
    mov ecx, r10d
    mov r8d, r11d
    call draw_glyph

    inc r15d
    jmp .byte_render_loop

.row_bytes_done:
    ; Draw ASCII separator '|'
    lea rdi, [rel str_gutter_sep]
    mov esi, ASCII_SEP_X
    mov edx, r14d
    mov ecx, COLOR_DIVIDER
    mov r8d, COLOR_BG
    call draw_string

    inc r12d
    jmp .row_render_loop

.rows_done:
    ; --------------------------------------------------------------------------
    ; 5. Render Data Inspector Pane
    ; --------------------------------------------------------------------------
    lea rdi, [rel insp_title]
    mov esi, INSPECTOR_X
    mov edx, 34
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_HEADER_BG
    call draw_string

    ; Check if cursor_offset is within file
    mov rbx, [rel cursor_offset]
    cmp rbx, [rel file_size]
    jae .render_status_bar

    ; Inspector Offset (Hex)
    lea rdi, [rel insp_off_h]
    mov esi, INSPECTOR_X
    mov edx, 56
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, rbx
    call format_hex_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 136
    mov edx, 56
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Inspector Offset (Dec)
    lea rdi, [rel insp_off_d]
    mov esi, INSPECTOR_X
    mov edx, 74
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, rbx
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 74
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Read byte value at cursor
    mov rax, [rel file_ptr]
    movzx r12d, byte [rax + rbx]      ; r12d = current byte value

    ; Value (Hex): 0xXX
    lea rdi, [rel insp_val_h]
    mov esi, INSPECTOR_X
    mov edx, 92
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rax, [rel hex_lut]
    movzx eax, word [rax + r12 * 2]
    mov [rel str_buf_1], al
    mov [rel str_buf_1 + 1], ah
    mov byte [rel str_buf_1 + 2], 0

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 136
    mov edx, 92
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Value (Bin): 8 bits from bin_lut
    lea rdi, [rel insp_val_b]
    mov esi, INSPECTOR_X
    mov edx, 110
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rax, [rel bin_lut]
    mov rax, [rax + r12 * 8]
    mov [rel str_buf_1], rax
    mov byte [rel str_buf_1 + 8], 0

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 110
    mov ecx, COLOR_HEX_ASCII
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Value (Char): 'X'
    lea rdi, [rel insp_val_c]
    mov esi, INSPECTOR_X
    mov edx, 128
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    mov eax, r12d
    cmp al, 32
    jb .c_dot
    cmp al, 126
    jbe .c_ok
.c_dot:
    mov al, '.'
.c_ok:
    mov [rel str_buf_1], al
    mov byte [rel str_buf_1 + 1], "'"
    mov byte [rel str_buf_1 + 2], 0

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 128
    mov edx, 128
    mov ecx, COLOR_HEX_SPECIAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Section: INTEGERS
    lea rdi, [rel insp_sec_int]
    mov esi, INSPECTOR_X
    mov edx, 150
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; uint8
    lea rdi, [rel insp_u8]
    mov esi, INSPECTOR_X
    mov edx, 170
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, r12
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 170
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; int8
    lea rdi, [rel insp_s8]
    mov esi, INSPECTOR_X
    mov edx, 188
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    movsx rsi, r12b
    lea rdi, [rel str_buf_1]
    call format_dec_int64

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 188
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; uint16 & int16 (if offset + 1 < file_size)
    mov rax, rbx
    inc rax
    cmp rax, [rel file_size]
    jae .skip_16

    mov rax, [rel file_ptr]
    movzx r13d, word [rax + rbx]

    lea rdi, [rel insp_u16]
    mov esi, INSPECTOR_X
    mov edx, 206
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, r13
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 206
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel insp_s16]
    mov esi, INSPECTOR_X
    mov edx, 224
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    movsx rsi, r13w
    lea rdi, [rel str_buf_1]
    call format_dec_int64

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 224
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

.skip_16:
    ; uint32 & int32 (if offset + 3 < file_size)
    mov rax, rbx
    add rax, 3
    cmp rax, [rel file_size]
    jae .skip_32

    mov rax, [rel file_ptr]
    mov r14d, dword [rax + rbx]

    lea rdi, [rel insp_u32]
    mov esi, INSPECTOR_X
    mov edx, 242
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, r14
    call format_dec_qword

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 242
    mov ecx, COLOR_INSP_VAL
    mov r8d, COLOR_PANEL_BG
    call draw_string

.skip_32:
    ; File stats section
    lea rdi, [rel insp_sec_file]
    mov esi, INSPECTOR_X
    mov edx, 266
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Human Size
    lea rdi, [rel insp_size]
    mov esi, INSPECTOR_X
    mov edx, 286
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    lea rdi, [rel str_buf_1]
    mov rsi, [rel file_size]
    call format_size_human

    lea rdi, [rel str_buf_1]
    mov esi, INSPECTOR_X + 120
    mov edx, 286
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Mode (HEX or ASCII)
    lea rdi, [rel insp_mode]
    mov esi, INSPECTOR_X
    mov edx, 304
    mov ecx, COLOR_INSP_LABEL
    mov r8d, COLOR_PANEL_BG
    call draw_string

    cmp dword [rel active_pane], PANE_HEX
    jne .show_asc_mode
    lea rdi, [rel insp_mode_hex]
    mov ecx, COLOR_OFFSET
    jmp .draw_mode_lbl
.show_asc_mode:
    lea rdi, [rel insp_mode_asc]
    mov ecx, COLOR_HEX_ASCII
.draw_mode_lbl:
    mov esi, INSPECTOR_X + 120
    mov edx, 304
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; Render Diff Inspector if in diff mode
    call render_diff_inspector

    ; Render Selection stats in inspector (if selection active)
    call render_selection_inspector

    ; Shortcuts Cheat Sheet start Y coordinate
    mov r14d, 330
    cmp dword [rel is_diff_mode], 1
    jne .chk_has_sel
    mov r14d, 442
    cmp dword [rel has_selection], 1
    jne .chk_cs_start
    add r14d, 46
    jmp .chk_cs_start

.chk_has_sel:
    cmp dword [rel has_selection], 1
    jne .chk_cs_start
    mov r14d, 390

.chk_cs_start:
    cmp dword [rel last_checksum_valid], 1
    jne .shortcuts_start
    add r14d, 70                      ; Shift down for checksums block

.shortcuts_start:
    lea rdi, [rel insp_sec_help]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_INSP_TITLE
    mov r8d, COLOR_PANEL_BG
    call draw_string

    cmp dword [rel is_diff_mode], 1
    jne .draw_normal_shortcuts

    ; Diff Mode Shortcuts
    add r14d, 18
    lea rdi, [rel insp_h_diff_nav]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_DIFF_PEER
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h_diff_flip]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_DIFF_PEER
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h_sel]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_HEX_ASCII
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h10]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h5]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h6]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h9]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string
    jmp .render_status_bar

.draw_normal_shortcuts:
    add r14d, 18
    lea rdi, [rel insp_h_sel]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_HEX_ASCII
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h10]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h1]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h2]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h3]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h4]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h5]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h6]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h7]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h8]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    add r14d, 16
    lea rdi, [rel insp_h9]
    mov esi, INSPECTOR_X
    mov edx, r14d
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_PANEL_BG
    call draw_string

    ; --------------------------------------------------------------------------
    ; 6. Render Bottom Status / Modal Command Bar
    ; --------------------------------------------------------------------------
.render_status_bar:
    mov r12d, [rel win_h]
    sub r12d, STATUS_H

    cmp dword [rel editor_mode], MODE_NORMAL
    jne .render_modal_bar

    ; Normal Mode:
    ; Line 1: status_msg_buf
    lea rdi, [rel status_msg_buf]
    mov esi, 16
    mov edx, r12d
    add edx, 8
    mov ecx, [rel status_msg_color]
    mov r8d, COLOR_STATUS_BG
    call draw_string

    ; Line 2: Help bar
    lea rdi, [rel status_help_bar]
    cmp dword [rel is_diff_mode], 1
    jne .draw_help_str
    lea rdi, [rel status_help_bar_diff]
.draw_help_str:
    mov esi, 16
    mov edx, r12d
    add edx, 28
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_STATUS_BG
    call draw_string
    jmp .render_all_done

.render_modal_bar:
    cmp dword [rel editor_mode], MODE_GOTO
    jne .render_search_bar

    ; Goto Mode Prompt:
    lea rdi, [rel prompt_goto]
    mov esi, 16
    mov edx, r12d
    add edx, 8
    mov ecx, COLOR_PROMPT_FG
    mov r8d, COLOR_STATUS_BG
    call draw_string

    ; Draw user input string
    lea rdi, [rel input_buf]
    mov esi, 240
    mov edx, r12d
    add edx, 8
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PROMPT_BG
    call draw_string

    ; Line 2 help
    lea rdi, [rel prompt_goto_help]
    mov esi, 16
    mov edx, r12d
    add edx, 28
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_STATUS_BG
    call draw_string
    jmp .render_all_done

.render_search_bar:
    ; Search Mode Prompt:
    lea rdi, [rel prompt_find]
    mov esi, 16
    mov edx, r12d
    add edx, 8
    mov ecx, COLOR_PROMPT_FG
    mov r8d, COLOR_STATUS_BG
    call draw_string

    lea rdi, [rel input_buf]
    mov esi, 220
    mov edx, r12d
    add edx, 8
    mov ecx, COLOR_TEXT_BRIGHT
    mov r8d, COLOR_PROMPT_BG
    call draw_string

    lea rdi, [rel prompt_find_help]
    mov esi, 16
    mov edx, r12d
    add edx, 28
    mov ecx, COLOR_TEXT_DIM
    mov r8d, COLOR_STATUS_BG
    call draw_string

.render_all_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
