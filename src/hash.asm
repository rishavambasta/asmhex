; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; hash.asm - Hardware-accelerated CRC32 & SHA-256 Cryptographic Checksums
; ==============================================================================

bits 64
default rel

section .rodata
align 16
K256:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

init_state:
    dd 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    dd 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

hex_digits_lower:
    db "0123456789abcdef"

section .bss
alignb 16
global crc32_table
crc32_table: resd 256

section .text
global init_crc32_table
global compute_crc32
global compute_sha256
global format_sha256_hex

; ------------------------------------------------------------------------------
; init_crc32_table:
; Precomputes 256-dword IEEE 802.3 CRC32 lookup table (polynomial 0xEDB88320)
; ------------------------------------------------------------------------------
init_crc32_table:
    lea rdi, [rel crc32_table]
    xor ecx, ecx                      ; i = 0..255
.table_loop:
    mov eax, ecx                      ; c = i
    mov edx, 8                        ; 8 bits
.bit_loop:
    test al, 1
    jz .bit_zero
    shr eax, 1
    xor eax, 0xEDB88320
    jmp .bit_next
.bit_zero:
    shr eax, 1
.bit_next:
    dec edx
    jnz .bit_loop
    mov [rdi + rcx * 4], eax
    inc ecx
    cmp ecx, 256
    jl .table_loop
    ret

; ------------------------------------------------------------------------------
; compute_crc32:
; Computes standard IEEE 802.3 32-bit CRC over buffer
; Arguments:
;   rdi = data ptr
;   rsi = length in bytes
; Returns:
;   eax = 32-bit CRC value
; ------------------------------------------------------------------------------
compute_crc32:
    mov eax, 0xFFFFFFFF
    test rsi, rsi
    jz .crc_ret
    lea r8, [rel crc32_table]
.crc_byte_loop:
    movzx edx, byte [rdi]
    xor edx, eax
    and edx, 0xFF
    shr eax, 8
    xor eax, [r8 + rdx * 4]
    inc rdi
    dec rsi
    jnz .crc_byte_loop
.crc_ret:
    not eax
    ret

; ------------------------------------------------------------------------------
; sha256_transform:
; Internal helper: processes one 64-byte block using FIPS 180-4 SHA-256
; Arguments:
;   rdi = state ptr (8 dwords: A, B, C, D, E, F, G, H)
;   rsi = block ptr (64 bytes)
; ------------------------------------------------------------------------------
sha256_transform:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256 + 8                  ; 256 bytes for W[0..63] (16-byte aligned)

    ; 1. Load W[0..15] with big-endian byte-swapped dwords
    xor ecx, ecx
.load_w:
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rsp + rcx * 4], eax
    inc ecx
    cmp ecx, 16
    jl .load_w

    ; 2. Expand W[16..63]
    ; W[t] = sig1(W[t-2]) + W[t-7] + sig0(W[t-15]) + W[t-16]
    mov ecx, 16
.expand_w:
    ; x = W[t-2]
    mov eax, [rsp + rcx * 4 - 8]
    ; sig1(x) = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10)
    mov edx, eax
    ror edx, 17
    mov ebx, eax
    ror ebx, 19
    xor edx, ebx
    shr eax, 10
    xor edx, eax                      ; edx = sig1(W[t-2])

    ; + W[t-7]
    add edx, [rsp + rcx * 4 - 28]

    ; + sig0(W[t-15])
    mov eax, [rsp + rcx * 4 - 60]     ; W[t-15]
    ; sig0(x) = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3)
    mov r8d, eax
    ror r8d, 7
    mov ebx, eax
    ror ebx, 18
    xor r8d, ebx
    shr eax, 3
    xor r8d, eax                      ; r8d = sig0(W[t-15])
    add edx, r8d

    ; + W[t-16]
    add edx, [rsp + rcx * 4 - 64]
    mov [rsp + rcx * 4], edx

    inc ecx
    cmp ecx, 64
    jl .expand_w

    ; 3. Load state into registers
    ; eax = a, ebx = b, ecx = c, edx = d
    ; r8d = e, r9d = f, r10d = g, r11d = h
    mov eax, [rdi + 0]
    mov ebx, [rdi + 4]
    mov ecx, [rdi + 8]
    mov edx, [rdi + 12]
    mov r8d, [rdi + 16]
    mov r9d, [rdi + 20]
    mov r10d, [rdi + 24]
    mov r11d, [rdi + 28]

    ; 4. 64 Rounds
    xor r12d, r12d                    ; t = 0..63
    lea r13, [rel K256]

.round_loop:
    ; T1 = h + SIG1(e) + CH(e, f, g) + K[t] + W[t]
    ; SIG1(e) = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
    mov r14d, r8d
    ror r14d, 6
    mov r15d, r8d
    ror r15d, 11
    xor r14d, r15d
    mov r15d, r8d
    ror r15d, 25
    xor r14d, r15d                    ; r14d = SIG1(e)

    ; CH(e, f, g) = (e & f) ^ (~e & g)
    mov r15d, r8d
    and r15d, r9d
    mov ebp, r8d
    not ebp
    and ebp, r10d
    xor r15d, ebp                     ; r15d = CH(e, f, g)

    ; T1 = h + SIG1(e) + CH(e, f, g) + K[t] + W[t]
    add r14d, r11d                    ; + h
    add r14d, r15d                    ; + CH
    add r14d, [r13 + r12 * 4]         ; + K[t]
    add r14d, [rsp + r12 * 4]         ; + W[t] -> r14d = T1

    ; T2 = SIG0(a) + MAJ(a, b, c)
    ; SIG0(a) = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
    mov r15d, eax
    ror r15d, 2
    mov ebp, eax
    ror ebp, 13
    xor r15d, ebp
    mov ebp, eax
    ror ebp, 22
    xor r15d, ebp                     ; r15d = SIG0(a)

    ; MAJ(a, b, c) = (a & b) ^ (a & c) ^ (b & c)
    mov ebp, eax
    and ebp, ebx
    push r14                          ; preserve T1
    mov r14d, eax
    and r14d, ecx
    xor ebp, r14d
    mov r14d, ebx
    and r14d, ecx
    xor ebp, r14d
    pop r14                           ; restore T1
    add r15d, ebp                     ; r15d = T2

    ; Update state:
    mov r11d, r10d                    ; h = g
    mov r10d, r9d                     ; g = f
    mov r9d, r8d                      ; f = e
    mov r8d, edx                      ; e = d + T1
    add r8d, r14d
    mov edx, ecx                      ; d = c
    mov ecx, ebx                      ; c = b
    mov ebx, eax                      ; b = a
    mov eax, r14d                     ; a = T1 + T2
    add eax, r15d

    inc r12d
    cmp r12d, 64
    jl .round_loop

    ; 5. Add back to state
    add [rdi + 0], eax
    add [rdi + 4], ebx
    add [rdi + 8], ecx
    add [rdi + 12], edx
    add [rdi + 16], r8d
    add [rdi + 20], r9d
    add [rdi + 24], r10d
    add [rdi + 28], r11d

    add rsp, 256 + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; compute_sha256:
; Computes FIPS 180-4 standard SHA-256 digest of arbitrary length buffer
; Arguments:
;   rdi = data ptr
;   rsi = length in bytes
;   rdx = digest output buffer (32 bytes)
; ------------------------------------------------------------------------------
compute_sha256:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 216                      ; 40B (5 pushed regs) + 216 = 256 (16-byte aligned)

    mov r12, rdi                      ; data ptr
    mov r13, rsi                      ; length
    mov r14, rdx                      ; digest_out

    ; Initialize state at [rbp - 72] (32 bytes, below all pushed registers)
    lea rdi, [rbp - 72]
    lea rsi, [rel init_state]
    mov rcx, 4
    rep movsq

    ; Process full 64-byte blocks
    xor r15, r15                      ; cur_offset = 0
.full_blocks_loop:
    mov rax, r15
    add rax, 64
    cmp rax, r13
    ja .full_blocks_done

    lea rdi, [rbp - 72]               ; state
    lea rsi, [r12 + r15]              ; block ptr
    call sha256_transform
    add r15, 64
    jmp .full_blocks_loop

.full_blocks_done:
    ; Remaining bytes: rem = len - cur_offset
    mov rax, r13
    sub rax, r15                      ; rax = rem (0..63)

    ; Clear 128-byte tail buffer at [rbp - 200]
    lea rdi, [rbp - 200]
    xor edx, edx
    mov ecx, 16
    xor eax, eax
.zero_tail:
    mov [rdi + rdx * 8], rax
    inc rdx
    dec ecx
    jnz .zero_tail

    ; Copy rem bytes into tail buffer
    mov rax, r13
    sub rax, r15                      ; rem
    test rax, rax
    jz .pad_80

    mov rcx, rax
    lea rsi, [r12 + r15]
    lea rdi, [rbp - 200]
    rep movsb

.pad_80:
    lea rdi, [rbp - 200]
    mov byte [rdi + rax], 0x80

    ; Total blocks: if rem + 1 + 8 <= 64, 1 block (64 bytes), else 2 blocks (128 bytes)
    lea rcx, [rax + 9]
    cmp rcx, 64
    jbe .one_block
    mov ebx, 128
    jmp .store_bitlen
.one_block:
    mov ebx, 64

.store_bitlen:
    ; Bit length = len * 8 in big-endian at end of tail blocks
    mov rax, r13
    shl rax, 3                        ; bit_len
    bswap rax                         ; big-endian
    mov [rdi + rbx - 8], rax

    ; Transform tail block 1
    lea rdi, [rbp - 72]
    lea rsi, [rbp - 200]
    call sha256_transform

    cmp ebx, 128
    jne .write_digest

    ; Transform tail block 2 (if 128 bytes required)
    lea rdi, [rbp - 72]
    lea rsi, [rbp - 200 + 64]
    call sha256_transform

.write_digest:
    ; Write 32 bytes digest (big-endian dwords)
    lea rsi, [rbp - 72]
    mov rdi, r14
    xor ecx, ecx
.wd_loop:
    mov eax, [rsi + rcx * 4]
    bswap eax
    mov [rdi + rcx * 4], eax
    inc ecx
    cmp ecx, 8
    jl .wd_loop

    add rsp, 216
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; format_sha256_hex:
; Converts 32-byte binary digest into 64 lowercase hexadecimal ASCII characters
; Arguments:
;   rdi = digest ptr (32 bytes)
;   rsi = output string buffer (at least 65 bytes, null-terminated)
; ------------------------------------------------------------------------------
format_sha256_hex:
    lea r8, [rel hex_digits_lower]
    xor ecx, ecx
.f_loop:
    movzx eax, byte [rdi + rcx]
    mov edx, eax
    shr edx, 4
    and edx, 0x0F
    mov dl, [r8 + rdx]
    mov [rsi + rcx * 2], dl

    and eax, 0x0F
    mov al, [r8 + rax]
    mov [rsi + rcx * 2 + 1], al

    inc ecx
    cmp ecx, 32
    jl .f_loop
    mov byte [rsi + 64], 0
    ret
