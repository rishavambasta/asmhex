; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; renderer.asm - High performance SIMD renderer, font blitter & text drawing
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

extern win_w
extern win_h
extern fb_data
extern fb_pitch
%ifndef OS_WINDOWS
extern snprintf
%endif

section .rodata
    align 16
    font_bitmap: incbin "font.bin"     ; 4096 bytes of 8x16 Terminus bold font
    hex_chars:   db "0123456789ABCDEF"
    hex_chars_l: db "0123456789abcdef"
    ppm_fmt:     db "P6", 10, "%d %d", 10, "255", 10, 0

section .data
    align 4
    global font_scale
    font_scale:    dd 1               ; Text zoom/scaling factor (1 = 100% 8x16, 2 = 200% 16x32)

section .bss
    global hex_lut
    global bin_lut
    alignb 16
    hex_lut:       resw 256           ; 256 * 2 bytes = 512 bytes
    bin_lut:       resq 256           ; 256 * 8 bytes = 2048 bytes (8 chars per byte)
    temp_str_buf:  resb 128           ; Temporary scratch string formatting buffer
    ppm_hdr_buf:   resb 64            ; Dynamic PPM header buffer
    ppm_line_buf:  resb 4096 * 3      ; Buffer for one scanline of RGB bytes (up to 4K px)

section .text

; ------------------------------------------------------------------------------
; init_renderer_luts:
; Precomputes lookup tables for 2-cycle byte-to-hex and 1-cycle byte-to-bin conversion
; ------------------------------------------------------------------------------
global init_renderer_luts
init_renderer_luts:
    push rbx
    push r12

    lea rsi, [rel hex_chars_l]
    lea rdi, [rel hex_lut]

    ; Initialize hex_lut (2 lowercase hex ASCII characters for each byte 0..255)
    xor ecx, ecx                      ; ecx = byte value 0..255
.loop_hex:
    mov eax, ecx
    shr eax, 4
    and eax, 0x0F
    mov al, [rsi + rax]               ; High nibble char

    mov edx, ecx
    and edx, 0x0F
    mov ah, [rsi + rdx]               ; Low nibble char

    mov [rdi + rcx * 2], ax           ; Store 2 chars
    inc ecx
    cmp ecx, 256
    jl .loop_hex

    ; Initialize bin_lut (8 ASCII '0'/'1' characters for each byte 0..255)
    lea rdi, [rel bin_lut]
    xor ecx, ecx                      ; ecx = byte value 0..255
.loop_bin:
    xor rdx, rdx                      ; rdx will hold 8 ASCII chars
    mov ebx, ecx                      ; byte value
    mov r8d, 8                        ; 8 bits
.bit_loop:
    shl rdx, 8                        ; shift left to make room for next char
    test bl, 0x80
    jz .bit_is_0
    or dl, '1'
    jmp .next_bit
.bit_is_0:
    or dl, '0'
.next_bit:
    shl bl, 1
    dec r8d
    jnz .bit_loop

    bswap rdx
    mov [rdi + rcx * 8], rdx

    inc ecx
    cmp ecx, 256
    jl .loop_bin

    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------------------
; draw_rect:
; Fills rectangle (x, y, w, h) with 32-bit ARGB color
; edi = x, esi = y, edx = w, ecx = h, r8d = color
; ------------------------------------------------------------------------------
global draw_rect
draw_rect:
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Bounds clipping
    test edx, edx
    jle .done
    test ecx, ecx
    jle .done

    ; Check bounds against window width & height
    cmp edi, [rel win_w]
    jge .done
    cmp esi, [rel win_h]
    jge .done

    ; Clamp x + w <= win_w
    mov eax, edi
    add eax, edx
    cmp eax, [rel win_w]
    jle .w_ok
    mov edx, [rel win_w]
    sub edx, edi
.w_ok:
    ; Clamp y + h <= win_h
    mov eax, esi
    add eax, ecx
    cmp eax, [rel win_h]
    jle .h_ok
    mov ecx, [rel win_h]
    sub ecx, esi
.h_ok:
    test edx, edx
    jle .done
    test ecx, ecx
    jle .done

    ; Calculate start pointer in framebuffer
    ; ptr = fb_data + y * fb_pitch + x * 4
    mov r9, [rel fb_data]
    test r9, r9
    jz .done

    mov r10d, [rel fb_pitch]          ; pitch in bytes
    mov eax, esi
    imul rax, r10                     ; y * pitch
    mov r11d, edi
    shl r11, 2                        ; x * 4
    add rax, r11
    add r9, rax                       ; r9 = fb start address

    ; Broadcast 32-bit color to all 4 lanes of xmm0
    movd xmm0, r8d
    pshufd xmm0, xmm0, 0              ; xmm0 = [color, color, color, color]

    mov r12d, ecx                     ; r12 = remaining height
.row_loop:
    mov rdi, r9                       ; destination row pointer
    mov r13d, edx                     ; r13 = remaining width (pixels)

    ; Fast path: 16-pixel chunks (4 xmm stores = 64 bytes)
    cmp r13d, 16
    jl .check_4

.loop_16:
    movdqu [rdi], xmm0
    movdqu [rdi + 16], xmm0
    movdqu [rdi + 32], xmm0
    movdqu [rdi + 48], xmm0
    add rdi, 64
    sub r13d, 16
    cmp r13d, 16
    jge .loop_16

.check_4:
    ; 4-pixel chunks (16 bytes)
    cmp r13d, 4
    jl .loop_1
.loop_4:
    movdqu [rdi], xmm0
    add rdi, 16
    sub r13d, 4
    cmp r13d, 4
    jge .loop_4

.loop_1:
    test r13d, r13d
    jz .row_next
    mov [rdi], r8d
    add rdi, 4
    dec r13d
    jnz .loop_1

.row_next:
    add r9, r10                       ; advance to next scanline
    dec r12d
    jnz .row_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------------------
; draw_rect_alpha:
; Fills rectangle (x, y, w, h) with alpha-blended ARGB color
; edi = x, esi = y, edx = w, ecx = h, r8d = color, r9d = alpha (0..255)
; SSE2 SIMD accelerated
; ------------------------------------------------------------------------------
global draw_rect_alpha
draw_rect_alpha:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte align (40 + 8 = 48)

    ; Check dimensions
    test edx, edx
    jle .dra_done
    test ecx, ecx
    jle .dra_done

    ; Bounds check against window width & height
    cmp edi, [rel win_w]
    jge .dra_done
    cmp esi, [rel win_h]
    jge .dra_done

    ; Clamp x + w <= win_w
    mov eax, edi
    add eax, edx
    cmp eax, [rel win_w]
    jle .dra_w_ok
    mov edx, [rel win_w]
    sub edx, edi
.dra_w_ok:
    ; Clamp y + h <= win_h
    mov eax, esi
    add eax, ecx
    cmp eax, [rel win_h]
    jle .dra_h_ok
    mov ecx, [rel win_h]
    sub ecx, esi
.dra_h_ok:
    test edx, edx
    jle .dra_done
    test ecx, ecx
    jle .dra_done

    ; Clamp alpha 0..256
    test r9d, r9d
    jle .dra_done
    cmp r9d, 256
    jle .dra_alpha_ok
    mov r9d, 256
.dra_alpha_ok:

    ; inv_alpha = 256 - alpha
    mov ebx, 256
    sub ebx, r9d                      ; ebx = inv_alpha

    ; Calculate src_b * alpha, src_g * alpha, src_r * alpha
    movzx eax, r8b                    ; src_b
    imul eax, r9d                     ; sb_a
    mov r10d, eax

    mov eax, r8d
    shr eax, 8
    movzx eax, al                     ; src_g
    imul eax, r9d                     ; sg_a
    mov r11d, eax

    mov eax, r8d
    shr eax, 16
    movzx eax, al                     ; src_r
    imul eax, r9d                     ; sr_a
    mov r12d, eax

    ; Construct xmm4 = [sb_a, sg_a, sr_a, 0, sb_a, sg_a, sr_a, 0]
    mov rax, r12
    shl rax, 16
    or rax, r11
    shl rax, 16
    or rax, r10                       ; rax has 4 words: [sb_a, sg_a, sr_a, 0]
    movq xmm4, rax
    punpcklqdq xmm4, xmm4             ; broadcast to both 64-bit halves

    ; Construct xmm5 = 8 words of inv_alpha
    movd xmm5, ebx
    pshuflw xmm5, xmm5, 0
    punpcklqdq xmm5, xmm5

    pxor xmm6, xmm6                   ; zero register for unpacking

    ; Calculate start pointer in fb
    mov r14, [rel fb_data]
    test r14, r14
    jz .dra_done

    mov r10d, [rel fb_pitch]
    mov eax, esi
    imul rax, r10                     ; y * pitch
    mov r11d, edi
    shl r11, 2                        ; x * 4
    add rax, r11
    add r14, rax                      ; r14 = fb start row

    mov r15d, ecx                     ; remaining height
.dra_row_loop:
    mov rdi, r14                      ; row pointer
    mov ecx, edx                      ; remaining width in pixels

    cmp ecx, 2
    jl .dra_check_last_1

.dra_loop_2_pix:
    movq xmm0, [rdi]
    punpcklbw xmm0, xmm6
    pmullw xmm0, xmm5
    paddw xmm0, xmm4
    psrlw xmm0, 8
    packuswb xmm0, xmm6
    movq [rdi], xmm0
    add rdi, 8
    sub ecx, 2
    cmp ecx, 2
    jge .dra_loop_2_pix

.dra_check_last_1:
    test ecx, ecx
    jz .dra_row_next
    movd xmm0, [rdi]
    punpcklbw xmm0, xmm6
    pmullw xmm0, xmm5
    paddw xmm0, xmm4
    psrlw xmm0, 8
    packuswb xmm0, xmm6
    movd [rdi], xmm0

.dra_row_next:
    add r14, r10                      ; advance to next scanline
    dec r15d
    jnz .dra_row_loop

.dra_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; draw_glyph:
; Blits an 8x16 bitmap character at (x, y) with fg and bg colors
; edi = x, esi = y, edx = char (0..255), ecx = fg_color, r8d = bg_color
; ------------------------------------------------------------------------------
global draw_glyph
draw_glyph:
    ; Bounds check
    mov eax, [rel font_scale]
    shl eax, 3                        ; char_w = font_scale * 8
    mov r10d, [rel win_w]
    sub r10d, eax
    cmp edi, r10d
    jg .glyph_done

    mov eax, [rel font_scale]
    shl eax, 4                        ; char_h = font_scale * 16
    mov r10d, [rel win_h]
    sub r10d, eax
    cmp esi, r10d
    jg .glyph_done

    mov r9, [rel fb_data]
    test r9, r9
    jz .glyph_done

    ; Pointer = fb_data + y * fb_pitch + x * 4
    mov r10d, [rel fb_pitch]
    mov eax, esi
    imul rax, r10
    mov r11d, edi
    shl r11, 2
    add rax, r11
    add r9, rax                       ; r9 = fb start for glyph

    ; Font glyph offset: (char & 0xFF) * 16
    and edx, 0xFF
    shl edx, 4
    lea rax, [rel font_bitmap]
    add rax, rdx                      ; rax = font glyph address

    cmp dword [rel font_scale], 1
    jle .scanline_loop_1x

    ; 2x Font Blitter (16x32)
    mov edx, 16                       ; 16 font scanlines
    mov rsi, [rel fb_pitch]
.s2_loop:
    movzx r11d, byte [rax]            ; 8 bits of font scanline
    inc rax

    test r11b, 0x80
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 0], r10d
    mov [r9 + 4], r10d

    test r11b, 0x40
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 8], r10d
    mov [r9 + 12], r10d

    test r11b, 0x20
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 16], r10d
    mov [r9 + 20], r10d

    test r11b, 0x10
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 24], r10d
    mov [r9 + 28], r10d

    test r11b, 0x08
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 32], r10d
    mov [r9 + 36], r10d

    test r11b, 0x04
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 40], r10d
    mov [r9 + 44], r10d

    test r11b, 0x02
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 48], r10d
    mov [r9 + 52], r10d

    test r11b, 0x01
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 56], r10d
    mov [r9 + 60], r10d

    ; Duplicate 64 bytes (16 pixels) to row 2 using SSE2 movdqu
    movdqu xmm0, [r9]
    movdqu xmm1, [r9 + 16]
    movdqu xmm2, [r9 + 32]
    movdqu xmm3, [r9 + 48]
    movdqu [r9 + rsi], xmm0
    movdqu [r9 + rsi + 16], xmm1
    movdqu [r9 + rsi + 32], xmm2
    movdqu [r9 + rsi + 48], xmm3

    lea r9, [r9 + rsi * 2]
    dec edx
    jnz .s2_loop
    ret

.scanline_loop_1x:
    mov edx, 16                       ; 16 rows

.scanline_loop:
    movzx r11d, byte [rax]            ; 8 bits of font scanline
    inc rax

    ; Unrolled 8-pixel horizontal blit with branchless cmov
    test r11b, 0x80
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9], r10d

    test r11b, 0x40
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 4], r10d

    test r11b, 0x20
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 8], r10d

    test r11b, 0x10
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 12], r10d

    test r11b, 0x08
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 16], r10d

    test r11b, 0x04
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 20], r10d

    test r11b, 0x02
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 24], r10d

    test r11b, 0x01
    mov r10d, r8d
    cmovnz r10d, ecx
    mov [r9 + 28], r10d

    add r9, [rel fb_pitch]            ; next row
    dec edx
    jnz .scanline_loop

.glyph_done:
    ret

; ------------------------------------------------------------------------------
; draw_glyph_transparent:
; Blits an 8x16 bitmap character with transparent background (foreground only)
; Preserves any alpha-blended or textured background underneath the glyph.
; edi = x, esi = y, edx = char (0..255), ecx = fg_color
; ------------------------------------------------------------------------------
global draw_glyph_transparent
draw_glyph_transparent:
    ; Bounds check
    mov eax, [rel font_scale]
    shl eax, 3                        ; char_w = font_scale * 8
    mov r10d, [rel win_w]
    sub r10d, eax
    cmp edi, r10d
    jg .gt_done

    mov eax, [rel font_scale]
    shl eax, 4                        ; char_h = font_scale * 16
    mov r10d, [rel win_h]
    sub r10d, eax
    cmp esi, r10d
    jg .gt_done

    mov r9, [rel fb_data]
    test r9, r9
    jz .gt_done

    ; Pointer = fb_data + y * fb_pitch + x * 4
    mov r10d, [rel fb_pitch]
    mov eax, esi
    imul rax, r10
    mov r11d, edi
    shl r11, 2
    add rax, r11
    add r9, rax                       ; r9 = fb start for glyph

    ; Font glyph offset: (char & 0xFF) * 16
    and edx, 0xFF
    shl edx, 4
    lea rax, [rel font_bitmap]
    add rax, rdx                      ; rax = font glyph address

    cmp dword [rel font_scale], 1
    jle .gt_scanline_loop_1x

    ; 2x Transparent Blitter
    mov edx, 16                       ; 16 rows
    mov rsi, [rel fb_pitch]
.gt_s2_loop:
    movzx r11d, byte [rax]            ; 8 bits of font scanline
    inc rax

    test r11b, 0x80
    jz .gt2_b6
    mov [r9 + 0], ecx
    mov [r9 + 4], ecx
    mov [r9 + rsi + 0], ecx
    mov [r9 + rsi + 4], ecx
.gt2_b6:
    test r11b, 0x40
    jz .gt2_b5
    mov [r9 + 8], ecx
    mov [r9 + 12], ecx
    mov [r9 + rsi + 8], ecx
    mov [r9 + rsi + 12], ecx
.gt2_b5:
    test r11b, 0x20
    jz .gt2_b4
    mov [r9 + 16], ecx
    mov [r9 + 20], ecx
    mov [r9 + rsi + 16], ecx
    mov [r9 + rsi + 20], ecx
.gt2_b4:
    test r11b, 0x10
    jz .gt2_b3
    mov [r9 + 24], ecx
    mov [r9 + 28], ecx
    mov [r9 + rsi + 24], ecx
    mov [r9 + rsi + 28], ecx
.gt2_b3:
    test r11b, 0x08
    jz .gt2_b2
    mov [r9 + 32], ecx
    mov [r9 + 36], ecx
    mov [r9 + rsi + 32], ecx
    mov [r9 + rsi + 36], ecx
.gt2_b2:
    test r11b, 0x04
    jz .gt2_b1
    mov [r9 + 40], ecx
    mov [r9 + 44], ecx
    mov [r9 + rsi + 40], ecx
    mov [r9 + rsi + 44], ecx
.gt2_b1:
    test r11b, 0x02
    jz .gt2_b0
    mov [r9 + 48], ecx
    mov [r9 + 52], ecx
    mov [r9 + rsi + 48], ecx
    mov [r9 + rsi + 52], ecx
.gt2_b0:
    test r11b, 0x01
    jz .gt2_row_next
    mov [r9 + 56], ecx
    mov [r9 + 60], ecx
    mov [r9 + rsi + 56], ecx
    mov [r9 + rsi + 60], ecx

.gt2_row_next:
    lea r9, [r9 + rsi * 2]
    dec edx
    jnz .gt_s2_loop
    ret

.gt_scanline_loop_1x:
    mov edx, 16                       ; 16 rows

.gt_scanline_loop:
    movzx r11d, byte [rax]            ; 8 bits of font scanline
    inc rax

    ; Fast conditional stores: only write destination pixel when font bit is set (1)
    test r11b, 0x80
    jz .gt_b6
    mov [r9], ecx
.gt_b6:
    test r11b, 0x40
    jz .gt_b5
    mov [r9 + 4], ecx
.gt_b5:
    test r11b, 0x20
    jz .gt_b4
    mov [r9 + 8], ecx
.gt_b4:
    test r11b, 0x10
    jz .gt_b3
    mov [r9 + 12], ecx
.gt_b3:
    test r11b, 0x08
    jz .gt_b2
    mov [r9 + 16], ecx
.gt_b2:
    test r11b, 0x04
    jz .gt_b1
    mov [r9 + 20], ecx
.gt_b1:
    test r11b, 0x02
    jz .gt_b0
    mov [r9 + 24], ecx
.gt_b0:
    test r11b, 0x01
    jz .gt_row_next
    mov [r9 + 28], ecx

.gt_row_next:
    add r9, [rel fb_pitch]            ; next row
    dec edx
    jnz .gt_scanline_loop

.gt_done:
    ret

; ------------------------------------------------------------------------------
; draw_string:
; Draws null-terminated ASCII string at (x, y)
; rdi = str_ptr, esi = x, edx = y, ecx = fg_color, r8d = bg_color
; ------------------------------------------------------------------------------
global draw_string
draw_string:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                      ; str_ptr
    mov r13d, esi                     ; cur_x
    mov r14d, edx                     ; cur_y
    mov ebx, ecx                      ; fg
    mov r15d, r8d                     ; bg

.str_loop:
    movzx edx, byte [r12]
    test dl, dl
    jz .str_done

    mov edi, r13d
    mov esi, r14d
    mov ecx, ebx
    mov r8d, r15d
    call draw_glyph

    mov eax, [rel font_scale]
    shl eax, 3                        ; 8 * font_scale
    add r13d, eax
    inc r12
    cmp r13d, [rel win_w]
    jl .str_loop

.str_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------------------
; draw_string_len:
; Draws string with explicit length at (x, y)
; rdi = str_ptr, esi = len, edx = x, ecx = y, r8d = fg_color, r9d = bg_color
; ------------------------------------------------------------------------------
global draw_string_len
draw_string_len:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                      ; str_ptr
    mov ebx, esi                      ; len
    mov r13d, edx                     ; cur_x
    mov r14d, ecx                     ; cur_y
    mov r15d, r8d                     ; fg
    ; bg color in stack/r9d
    mov eax, r9d                      ; bg

.len_loop:
    test ebx, ebx
    jle .len_done

    movzx edx, byte [r12]
    mov edi, r13d
    mov esi, r14d
    mov ecx, r15d
    mov r8d, eax
    push rax
    call draw_glyph
    pop rax

    mov eax, [rel font_scale]
    shl eax, 3                        ; 8 * font_scale
    add r13d, eax
    inc r12
    dec ebx
    cmp r13d, [rel win_w]
    jl .len_loop

.len_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ------------------------------------------------------------------------------
; draw_hline:
; edi = x1, esi = x2, edx = y, ecx = color
; ------------------------------------------------------------------------------
global draw_hline
draw_hline:
    push rbx
    cmp edi, esi
    jle .h_ord
    xchg edi, esi
.h_ord:
    mov ebx, esi
    sub ebx, edi                      ; width = x2 - x1
    mov r8d, ecx                      ; color
    mov esi, edx                      ; y
    mov edx, ebx                      ; w
    mov ecx, 1                        ; h = 1
    call draw_rect
    pop rbx
    ret

; ------------------------------------------------------------------------------
; draw_vline:
; edi = x, esi = y1, edx = y2, ecx = color
; ------------------------------------------------------------------------------
global draw_vline
draw_vline:
    push rbx
    cmp esi, edx
    jle .v_ord
    xchg esi, edx
.v_ord:
    mov ebx, edx
    sub ebx, esi                      ; height = y2 - y1
    mov r8d, ecx                      ; color
    mov edx, 1                        ; w = 1
    mov ecx, ebx                      ; h
    call draw_rect
    pop rbx
    ret

; ------------------------------------------------------------------------------
; format_hex_qword:
; Converts 64-bit value to 16 hex uppercase ASCII digits at [rdi]
; rdi = dst (must be >= 17 bytes), rsi = 64-bit value
; ------------------------------------------------------------------------------
global format_hex_qword
format_hex_qword:
    lea r8, [rel hex_chars_l]
    mov rax, rsi
    mov rcx, 16                       ; 16 nibbles
.q_loop:
    dec rcx
    mov rdx, rax
    and edx, 0x0F
    mov dl, [r8 + rdx]
    mov [rdi + rcx], dl
    shr rax, 4
    test rcx, rcx
    jnz .q_loop
    mov byte [rdi + 16], 0            ; null terminator
    ret

; ------------------------------------------------------------------------------
; format_hex_dword:
; Converts 32-bit value to 8 hex lowercase ASCII digits at [rdi]
; rdi = dst (>= 9 bytes), esi = 32-bit value
; ------------------------------------------------------------------------------
global format_hex_dword
format_hex_dword:
    lea r8, [rel hex_chars_l]
    mov eax, esi
    mov ecx, 8
.d_loop:
    dec ecx
    mov edx, eax
    and edx, 0x0F
    mov dl, [r8 + rdx]
    mov [rdi + rcx], dl
    shr eax, 4
    test ecx, ecx
    jnz .d_loop
    mov byte [rdi + 8], 0
    ret

; ------------------------------------------------------------------------------
; format_dec_qword:
; Formats 64-bit unsigned integer to decimal string at [rdi]
; Returns rax = length of string
; ------------------------------------------------------------------------------
global format_dec_qword
format_dec_qword:
    push rbx
    mov rax, rsi                      ; value
    mov rbx, rdi                      ; dst
    lea r8, [rdi + 32]                ; write backwards from end of temp
    mov byte [r8], 0
    dec r8
    mov r10, 10

    test rax, rax
    jnz .div_loop
    mov byte [r8], '0'
    mov rdi, rbx
    lea rsi, [r8]
    mov al, '0'
    mov [rdi], al
    mov byte [rdi + 1], 0
    mov rax, 1
    pop rbx
    ret

.div_loop:
    xor edx, edx
    div r10
    add dl, '0'
    mov [r8], dl
    dec r8
    test rax, rax
    jnz .div_loop

    inc r8                            ; points to first character
    ; Copy to dst
    mov rsi, r8
    mov rdi, rbx
    xor ecx, ecx
.copy_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    inc ecx
    cmp byte [rsi - 1], 0
    jnz .copy_loop

    dec ecx                           ; length without null
    mov eax, ecx
    pop rbx
    ret

; ------------------------------------------------------------------------------
; format_dec_int64:
; Formats 64-bit signed integer to decimal string at [rdi]
; ------------------------------------------------------------------------------
global format_dec_int64
format_dec_int64:
    push rbx
    test rsi, rsi
    jns .positive
    mov byte [rdi], '-'
    inc rdi
    neg rsi
.positive:
    call format_dec_qword
    pop rbx
    ret

; ------------------------------------------------------------------------------
; format_size_human:
; Formats byte size into human readable string: e.g. "1.45 MB", "420 KB", "85 B"
; rdi = dst buffer, rsi = byte size
; ------------------------------------------------------------------------------
global format_size_human
format_size_human:
    push rbx
    push r12
    mov rbx, rdi
    mov rax, rsi

    ; Check if >= 1 GB (1073741824)
    cmp rax, 1073741824
    jge .size_gb
    ; Check if >= 1 MB (1048576)
    cmp rax, 1048576
    jge .size_mb
    ; Check if >= 1 KB (1024)
    cmp rax, 1024
    jge .size_kb

    ; Just bytes
    mov rsi, rax
    mov rdi, rbx
    call format_dec_qword
    lea rdi, [rbx + rax]
    mov dword [rdi], " B"             ; " B\0\0"
    jmp .done_size

.size_kb:
    ; KB = rax * 100 / 1024 -> integer part and 2 decimal places
    imul rax, 100
    shr rax, 10                       ; / 1024
    call .format_with_dot
    lea rdi, [rbx + rax]
    mov dword [rdi], " KB"
    jmp .done_size

.size_mb:
    ; MB = rax * 100 / 1048576
    imul rax, 100
    shr rax, 20                       ; / 1048576
    call .format_with_dot
    lea rdi, [rbx + rax]
    mov dword [rdi], " MB"
    jmp .done_size

.size_gb:
    ; GB = rax * 100 / 1073741824
    imul rax, 100
    shr rax, 30                       ; / 1073741824
    call .format_with_dot
    lea rdi, [rbx + rax]
    mov dword [rdi], " GB"

.done_size:
    pop r12
    pop rbx
    ret

.format_with_dot:
    ; rax has value * 100
    xor edx, edx
    mov rcx, 100
    div rcx                           ; rax = integer, rdx = fraction (0..99)
    mov r12, rdx                      ; r12 = fraction

    mov rsi, rax
    mov rdi, rbx
    call format_dec_qword             ; writes integer part
    lea rdi, [rbx + rax]
    mov byte [rdi], '.'
    inc rdi

    ; Format 2 digits of fraction
    mov rax, r12
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    mov [rdi], al
    add dl, '0'
    mov [rdi + 1], dl
    mov byte [rdi + 2], 0

    ; Return total length in rax
    sub rdi, rbx
    add rdi, 2
    mov rax, rdi
    ret

%ifndef OS_WINDOWS
; ------------------------------------------------------------------------------
; dump_screenshot:
; Writes current backbuffer contents as a standard 24-bit PPM image file
; rdi = filename string ptr
; Returns rax = 0 on success, negative on error
; ------------------------------------------------------------------------------
global dump_screenshot
dump_screenshot:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte alignment

    mov r12, rdi                      ; filename

    ; sys_open(filename, O_WRONLY | O_CREAT | O_TRUNC, 0644)
    ; O_WRONLY = 1, O_CREAT = 64, O_TRUNC = 512 => 577
    mov rax, SYS_open
    mov rdi, r12
    mov esi, 1 | 64 | 512
    mov edx, 0644o
    syscall

    cmp rax, 0
    jl .ppm_open_err
    mov r13d, eax                     ; r13d = fd

    ; Format dynamic PPM header
    lea rdi, [rel ppm_hdr_buf]
    mov esi, 64
    lea rdx, [rel ppm_fmt]
    mov ecx, [rel win_w]
    mov r8d, [rel win_h]
    xor eax, eax
    CALL_PLT snprintf
    mov rbx, rax                      ; rbx = header len

    ; Write PPM header
    mov rax, SYS_write
    mov edi, r13d
    lea rsi, [rel ppm_hdr_buf]
    mov rdx, rbx
    syscall

    ; Convert each scanline from 32-bit ARGB to 24-bit RGB and write to file
    mov r14d, [rel win_h]             ; row loop counter (0..win_h-1)
    xor r15d, r15d                    ; current y

.ppm_row_loop:
    cmp r15d, r14d
    jae .ppm_done

    ; src_line = fb_data + y * fb_pitch
    mov r8, [rel fb_data]
    mov eax, r15d
    mov ecx, [rel fb_pitch]
    imul rax, rcx
    add r8, rax                       ; r8 = src pointer for row

    ; dst_line = ppm_line_buf
    lea r9, [rel ppm_line_buf]
    mov ebx, [rel win_w]              ; number of pixels

.ppm_pix_loop:
    mov edx, [r8]                     ; edx = 0x00RRGGBB
    ; Red = (edx >> 16) & 0xFF
    mov eax, edx
    shr eax, 16
    mov [r9], al
    ; Green = (edx >> 8) & 0xFF
    mov eax, edx
    shr eax, 8
    mov [r9 + 1], al
    ; Blue = edx & 0xFF
    mov [r9 + 2], dl

    add r8, 4
    add r9, 3
    dec ebx
    jnz .ppm_pix_loop

    ; Write line to file: count = win_w * 3
    mov eax, [rel win_w]
    imul eax, 3
    mov edx, eax

    mov rax, SYS_write
    mov edi, r13d
    lea rsi, [rel ppm_line_buf]
    syscall

    inc r15d
    jmp .ppm_row_loop

.ppm_done:
    ; Close fd
    mov rax, SYS_close
    mov edi, r13d
    syscall

    xor eax, eax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.ppm_open_err:
    mov rax, -1
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
%endif
