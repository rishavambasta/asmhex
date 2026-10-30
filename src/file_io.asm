; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; file_io.asm - Memory mapped file I/O using direct Linux 64-bit syscalls
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

section .data
    default_scratch_name: db "[ Scratch Buffer - 4 KB ]", 0
    welcome_banner:
        db "================================================================", 10
        db "  AsmHex v1.0 - Pure x86_64 Assembly Graphical Hex Editor       ", 10
        db "  Developed for ultra-fast, zero-latency binary editing.        ", 10
        db "================================================================", 10
        db "  * Use Arrows or Mouse to navigate bytes                       ", 10
        db "  * Tab / Space: Switch between Hex and ASCII editing panes     ", 10
        db "  * Type hex digits (0-9, A-F) in Hex pane to edit nibbles      ", 10
        db "  * Type characters directly in ASCII pane to overwrite bytes   ", 10
        db "  * Ctrl+S: Save changes (msync)                                ", 10
        db "  * Ctrl+Z: Undo modifications                                  ", 10
        db "  * Ctrl+G: Jump directly to offset (hex or dec)                ", 10
        db "  * Ctrl+F: Search byte patterns or ASCII strings               ", 10
        db "  * Ctrl+Q or Esc: Quit application                             ", 10
        db "================================================================", 10
    welcome_banner_len equ $ - welcome_banner

section .bss
    global file_ptr
    global file_size
    global file_fd
    global is_readonly
    global is_scratch
    global file_path
    global file2_ptr
    global file2_size
    global file2_fd
    global is_readonly2
    global file2_path

    align 16
    file_ptr:       resq 1            ; Pointer to mapped memory
    file_size:      resq 1            ; Total file size in bytes
    file_fd:        resd 1            ; File descriptor
    is_readonly:    resd 1            ; 1 if read-only, 0 if read-write
    is_scratch:     resd 1            ; 1 if anonymous scratch buffer
    file_path:      resb 512          ; Path to opened file
    stat_buf:       resb 144          ; struct stat buffer

    ; Secondary file for comparison / diffing
    file2_ptr:      resq 1            ; Pointer to mapped memory for file 2
    file2_size:     resq 1            ; Total file 2 size in bytes
    file2_fd:       resd 1            ; File 2 descriptor
    is_readonly2:   resd 1            ; 1 if read-only, 0 if read-write
    file2_path:     resb 512          ; Path to opened file 2
    stat_buf2:      resb 144          ; struct stat buffer for file 2

section .text

; ------------------------------------------------------------------------------
; file_open:
; Opens and memory-maps file at rdi (null-terminated path string)
; Returns rax = 0 on success, negative error code on failure
; ------------------------------------------------------------------------------
global file_open
file_open:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8                        ; 16-byte alignment (32 + 8 = 40)

    mov r12, rdi                      ; save path pointer

    ; Copy path to file_path buffer
    lea rsi, [r12]
    lea rdi, [rel file_path]
    mov ecx, 511
.copy_path:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jz .path_copied
    dec ecx
    jnz .copy_path
    mov byte [rdi], 0
.path_copied:

    ; Try opening with O_RDWR (2)
    mov rax, SYS_open
    lea rdi, [rel file_path]
    mov esi, O_RDWR
    xor edx, edx
    syscall

    cmp rax, 0
    jge .opened_rw

    ; Open failed with RDWR, try O_RDONLY (0)
    mov rax, SYS_open
    lea rdi, [rel file_path]
    mov esi, O_RDONLY
    xor edx, edx
    syscall

    cmp rax, 0
    jl .open_failed

    ; Opened read-only
    mov [rel file_fd], eax
    mov dword [rel is_readonly], 1
    jmp .get_fstat

.opened_rw:
    mov [rel file_fd], eax
    mov dword [rel is_readonly], 0

.get_fstat:
    mov dword [rel is_scratch], 0

    ; fstat(fd, &stat_buf)
    mov rax, SYS_fstat
    mov edi, [rel file_fd]
    lea rsi, [rel stat_buf]
    syscall

    test rax, rax
    jnz .fstat_failed

    ; st_size is at stat_buf + 48
    mov rax, [rel stat_buf + 48]
    mov [rel file_size], rax

    ; Check if file size is 0
    test rax, rax
    jnz .do_mmap

    ; Empty file: allocate 4KB scratch buffer so editor doesn't crash
    mov rax, SYS_mmap
    xor edi, edi
    mov esi, 4096
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall

    cmp rax, -4095
    jae .mmap_failed

    mov [rel file_ptr], rax
    mov qword [rel file_size], 0
    xor eax, eax
    jmp .open_done

.do_mmap:
    ; prot = is_readonly ? PROT_READ : (PROT_READ | PROT_WRITE)
    mov edx, PROT_READ | PROT_WRITE
    cmp dword [rel is_readonly], 1
    jne .prot_set
    mov edx, PROT_READ
.prot_set:

    ; flags = is_readonly ? MAP_PRIVATE : MAP_SHARED
    mov r10d, MAP_SHARED
    cmp dword [rel is_readonly], 1
    jne .flags_set
    mov r10d, MAP_PRIVATE
.flags_set:

    mov rax, SYS_mmap
    xor edi, edi                      ; addr = NULL
    mov rsi, [rel file_size]          ; length = file_size
    ; edx = prot
    ; r10d = flags
    mov r8d, [rel file_fd]            ; fd
    xor r9d, r9d                      ; offset = 0
    syscall

    cmp rax, -4095
    jae .mmap_failed

    mov [rel file_ptr], rax
    xor eax, eax                      ; return 0 (success)
    jmp .open_done

.open_failed:
    mov rax, -1
    jmp .open_done

.fstat_failed:
    ; Close fd on fstat fail
    mov rax, SYS_close
    mov edi, [rel file_fd]
    syscall
    mov dword [rel file_fd], -1
    mov rax, -2
    jmp .open_done

.mmap_failed:
    ; Close fd on mmap fail
    mov rax, SYS_close
    mov edi, [rel file_fd]
    syscall
    mov dword [rel file_fd], -1
    mov rax, -3

.open_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; file_create_scratch:
; Creates a 4KB in-memory scratch buffer with welcome banner
; ------------------------------------------------------------------------------
global file_create_scratch
file_create_scratch:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8                        ; 16-byte alignment (16 + 8 = 24)

    ; mmap 4096 bytes anonymous
    mov rax, SYS_mmap
    xor edi, edi
    mov esi, 4096
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall

    cmp rax, -4095
    jae .scratch_fail

    mov [rel file_ptr], rax
    mov qword [rel file_size], 4096
    mov dword [rel file_fd], -1
    mov dword [rel is_readonly], 0
    mov dword [rel is_scratch], 1

    ; Copy scratch name
    lea rsi, [rel default_scratch_name]
    lea rdi, [rel file_path]
    mov ecx, 64
.copy_scratch_name:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_scratch_name

    ; Zero out the 4096 buffer
    mov rdi, [rel file_ptr]
    xor eax, eax
    mov ecx, 1024                     ; 1024 dwords = 4096 bytes
    rep stosd

    ; Copy welcome banner into buffer
    mov rdi, [rel file_ptr]
    lea rsi, [rel welcome_banner]
    mov ecx, welcome_banner_len
    rep movsb

    ; Add some sample hexadecimal bytes for testing
    mov rdi, [rel file_ptr]
    add rdi, welcome_banner_len

    ; Pattern bytes: 0x00..0xFF
    xor ecx, ecx
.sample_loop:
    mov [rdi + rcx], cl
    inc ecx
    cmp ecx, 256
    jl .sample_loop

    xor eax, eax
    add rsp, 8
    pop rbx
    pop rbp
    ret

.scratch_fail:
    mov rax, -1
    add rsp, 8
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; file_save:
; Flushes memory map to disk using sys_msync
; Returns 0 on success, negative on error
; ------------------------------------------------------------------------------
global file_save
file_save:
    cmp dword [rel is_readonly], 1
    je .save_ro_err

    cmp dword [rel is_scratch], 1
    je .save_scratch_err

    mov rdi, [rel file_ptr]
    test rdi, rdi
    jz .save_no_file

    mov rsi, [rel file_size]
    test rsi, rsi
    jz .save_empty

    ; sys_msync(file_ptr, file_size, MS_SYNC)
    mov rax, SYS_msync
    mov edx, MS_SYNC
    syscall

    test rax, rax
    jnz .save_sys_err
    xor eax, eax
    ret

.save_empty:
    xor eax, eax
    ret

.save_ro_err:
    mov rax, -1                       ; File is read-only
    ret

.save_scratch_err:
    mov rax, -2                       ; Cannot save scratch without filename
    ret

.save_no_file:
    mov rax, -3
    ret

.save_sys_err:
    ret

; ------------------------------------------------------------------------------
; file_close:
; Unmaps and closes currently open file
; ------------------------------------------------------------------------------
global file_close
file_close:
    mov rdi, [rel file_ptr]
    test rdi, rdi
    jz .no_unmap

    mov rsi, [rel file_size]
    test rsi, rsi
    jnz .do_unmap
    mov rsi, 4096                     ; unmap scratch size
.do_unmap:
    mov rax, SYS_munmap
    syscall
    mov qword [rel file_ptr], 0

.no_unmap:
    mov edi, [rel file_fd]
    cmp edi, 0
    jl .no_close
    mov rax, SYS_close
    syscall
    mov dword [rel file_fd], -1

.no_close:
    ret

; ------------------------------------------------------------------------------
; file2_open:
; Opens and memory-maps secondary file for comparison / diffing
; Arguments:
;   rdi = path string
; Returns:
;   rax = 0 on success, negative error code on failure
; ------------------------------------------------------------------------------
global file2_open
file2_open:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    mov r12, rdi                      ; save path pointer
    test r12, r12
    jz .f2_open_failed

    ; If file2 was already open, close it first
    call file2_close

    ; Copy path to file2_path buffer
    lea rsi, [r12]
    lea rdi, [rel file2_path]
    mov ecx, 511
.f2_copy_path:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jz .f2_path_copied
    dec ecx
    jnz .f2_copy_path
    mov byte [rdi], 0
.f2_path_copied:

    ; Try opening with O_RDWR (2)
    mov rax, SYS_open
    lea rdi, [rel file2_path]
    mov esi, O_RDWR
    xor edx, edx
    syscall

    cmp rax, 0
    jge .f2_opened_rw

    ; Open failed with RDWR, try O_RDONLY (0)
    mov rax, SYS_open
    lea rdi, [rel file2_path]
    mov esi, O_RDONLY
    xor edx, edx
    syscall

    cmp rax, 0
    jl .f2_open_failed

    ; Opened read-only
    mov [rel file2_fd], eax
    mov dword [rel is_readonly2], 1
    jmp .f2_get_fstat

.f2_opened_rw:
    mov [rel file2_fd], eax
    mov dword [rel is_readonly2], 0

.f2_get_fstat:
    ; fstat(fd, &stat_buf2)
    mov rax, SYS_fstat
    mov edi, [rel file2_fd]
    lea rsi, [rel stat_buf2]
    syscall

    test rax, rax
    jnz .f2_fstat_failed

    ; st_size is at stat_buf2 + 48
    mov rax, [rel stat_buf2 + 48]
    mov [rel file2_size], rax

    ; If size == 0, return error (empty file)
    test rax, rax
    jz .f2_mmap_failed

    ; mmap:
    cmp dword [rel is_readonly2], 1
    je .f2_mmap_ro

    ; MMap Read-Write
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, [rel file2_size]
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_SHARED
    mov r8d, [rel file2_fd]
    xor r9d, r9d
    syscall
    jmp .f2_check_mmap

.f2_mmap_ro:
    mov rax, SYS_mmap
    xor edi, edi
    mov rsi, [rel file2_size]
    mov edx, PROT_READ
    mov r10d, MAP_PRIVATE
    mov r8d, [rel file2_fd]
    xor r9d, r9d
    syscall

.f2_check_mmap:
    cmp rax, -4095
    jae .f2_mmap_failed

    mov [rel file2_ptr], rax
    xor eax, eax                      ; return 0 (success)
    jmp .f2_done

.f2_mmap_failed:
.f2_fstat_failed:
    mov edi, [rel file2_fd]
    cmp edi, 0
    jl .f2_open_failed
    mov rax, SYS_close
    syscall
    mov dword [rel file2_fd], -1

.f2_open_failed:
    mov qword [rel file2_ptr], 0
    mov qword [rel file2_size], 0
    mov rax, -1

.f2_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; file2_close:
; Unmaps and closes secondary file
; ------------------------------------------------------------------------------
global file2_close
file2_close:
    mov rdi, [rel file2_ptr]
    test rdi, rdi
    jz .f2_no_unmap

    mov rsi, [rel file2_size]
    test rsi, rsi
    jz .f2_no_unmap
    mov rax, SYS_munmap
    syscall
    mov qword [rel file2_ptr], 0

.f2_no_unmap:
    mov edi, [rel file2_fd]
    cmp edi, 0
    jl .f2_no_close
    mov rax, SYS_close
    syscall
    mov dword [rel file2_fd], -1

.f2_no_close:
    mov qword [rel file2_ptr], 0
    mov qword [rel file2_size], 0
    ret
