; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; file_io.asm - Memory mapped file I/O using direct Linux 64-bit syscalls
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

section .data
    default_blank_name:   db "untitled.bin", 0
    default_scratch_name: db "[ Scratch Buffer - 4 KB ]", 0
    welcome_banner:
        db "================================================================", 10
        db "  AsmHex v1.2 - Pure x86_64 Assembly Graphical Hex Editor       ", 10
        db "  Developed for ultra-fast, zero-latency binary editing.        ", 10
        db "================================================================", 10
        db "  * Use Arrows or Mouse to navigate bytes                       ", 10
        db "  * Tab / Space: Switch between Hex and ASCII editing panes     ", 10
        db "  * Type hex digits (0-9, A-F) in Hex pane to edit nibbles      ", 10
        db "  * Type characters directly in ASCII pane to write bytes       ", 10
        db "  * Appending past EOF automatically extends file size          ", 10
        db "  * Ctrl+S: Save changes to disk (safe copy-on-write)           ", 10
        db "  * Ctrl+Z: Undo modifications                                  ", 10
        db "  * Ctrl+G: Jump directly to offset (hex or dec)                ", 10
        db "  * Ctrl+F: Search byte patterns or ASCII strings               ", 10
        db "  * F3 / Shift+F3: Next / Previous Diff (in Diff Mode)          ", 10
        db "  * Ctrl+Q or Esc: Quit without saving                          ", 10
        db "================================================================", 10
    welcome_banner_len equ $ - welcome_banner

    align 4
    global file_fd
    file_fd:        dd -1             ; File descriptor (-1 if new/unsaved)
    global file2_fd
    file2_fd:       dd -1             ; File 2 descriptor (-1 if closed)

section .bss
    global file_ptr
    global file_size
    global file_capacity
    global is_readonly
    global is_scratch
    global file_path
    global file2_ptr
    global file2_size
    global file2_capacity
    global is_readonly2
    global file2_path

    extern is_dirty

    align 16
    file_ptr:       resq 1            ; Pointer to mapped memory
    file_size:      resq 1            ; Total file size in bytes
    file_capacity:  resq 1            ; Allocated memory capacity in bytes
    is_readonly:    resd 1            ; 1 if read-only, 0 if read-write
    is_scratch:     resd 1            ; 1 if legacy scratch buffer
    file_path:      resb 512          ; Path to opened file
    stat_buf:       resb 144          ; struct stat buffer

    ; Secondary file for comparison / diffing
    file2_ptr:      resq 1            ; Pointer to mapped memory for file 2
    file2_size:     resq 1            ; Total file 2 size in bytes
    file2_capacity: resq 1            ; Allocated capacity for file 2
    is_readonly2:   resd 1            ; 1 if read-only, 0 if read-write
    file2_path:     resb 512          ; Path to opened file 2
    stat_buf2:      resb 144          ; struct stat buffer for file 2

section .text

; ------------------------------------------------------------------------------
; file_open:
; Opens and memory-maps file at rdi (null-terminated path string)
; Uses anonymous private memory (safe copy-on-write) + 64KB headroom
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

    ; If a file was already open, close it first
    call file_close

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

    ; Enforce 4 GiB file size limit (will not edit a file > 4 GiB)
    mov rsi, MAX_FILE_SIZE
    cmp rax, rsi
    ja .file_too_large

    ; capacity = max(file_size + 65536, 65536), page-aligned (4096)
    mov rsi, rax
    add rsi, 65536
    cmp rsi, 65536
    jae .cap_aligned
    mov rsi, 65536
.cap_aligned:
    add rsi, 4095
    and rsi, -4096
    mov [rel file_capacity], rsi

    ; Allocate anonymous private memory
    mov rax, SYS_mmap
    xor edi, edi                      ; addr = NULL
    ; rsi = length (file_capacity)
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall

    cmp rax, -4095
    jae .mmap_failed

    mov [rel file_ptr], rax

    ; Read file contents into allocated buffer
    mov r12, [rel file_size]
    test r12, r12
    jz .read_done

    mov rbx, rax                      ; dest buffer
    xor r13, r13                      ; offset read so far
.read_loop:
    cmp r13, r12
    jae .read_done
    mov rax, SYS_read
    mov edi, [rel file_fd]
    lea rsi, [rbx + r13]
    mov rdx, r12
    sub rdx, r13
    syscall

    cmp rax, 0
    jle .read_done                    ; EOF or error
    add r13, rax
    jmp .read_loop

.read_done:
    ; Zero out remaining headroom up to file_capacity
    mov rdi, [rel file_ptr]
    add rdi, [rel file_size]
    mov rcx, [rel file_capacity]
    sub rcx, [rel file_size]
    xor al, al
    rep stosb

    xor eax, eax                      ; return 0 (success)
    jmp .open_done

.file_too_large:
    mov rax, SYS_close
    mov edi, [rel file_fd]
    syscall
    mov dword [rel file_fd], -1
    mov rax, -4
    jmp .open_done

.open_failed:
    mov rax, -1
    jmp .open_done

.fstat_failed:
    mov rax, SYS_close
    mov edi, [rel file_fd]
    syscall
    mov dword [rel file_fd], -1
    mov rax, -2
    jmp .open_done

.mmap_failed:
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
; file_create_blank:
; Creates a blank file ready for writing (untitled.bin, 0 bytes, 64KB capacity)
; Returns rax = 0 on success, negative on error
; ------------------------------------------------------------------------------
global file_create_blank
file_create_blank:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8

    call file_close

    lea rsi, [rel default_blank_name]
    lea rdi, [rel file_path]
    mov ecx, 64
.copy_blank_name:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_blank_name

    ; Allocate 64KB anonymous memory
    mov rax, SYS_mmap
    xor edi, edi
    mov esi, 65536
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall

    cmp rax, -4095
    jae .blank_fail

    mov [rel file_ptr], rax
    mov qword [rel file_capacity], 65536
    mov qword [rel file_size], 0
    mov dword [rel file_fd], -1
    mov dword [rel is_readonly], 0
    mov dword [rel is_scratch], 0

    ; Zero out buffer
    mov rdi, rax
    xor eax, eax
    mov ecx, 65536 / 8
    rep stosq

    xor eax, eax
    add rsp, 8
    pop rbx
    pop rbp
    ret

.blank_fail:
    mov rax, -1
    add rsp, 8
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; file_ensure_capacity:
; Grows file_ptr anonymous buffer if needed_bytes > file_capacity
; Arguments: rdi = needed_bytes
; Returns: rax = 0 on success, negative on error
; ------------------------------------------------------------------------------
global file_ensure_capacity
file_ensure_capacity:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    mov r12, rdi                      ; needed_bytes
    mov rax, MAX_FILE_SIZE
    cmp r12, rax
    ja .ensure_fail
    mov rbx, [rel file_capacity]
    cmp r12, rbx
    jbe .cap_ok

    ; new_capacity = max(needed_bytes + 65536, file_capacity * 2)
    mov r13, rbx
    shl r13, 1
    lea rax, [r12 + 65536]
    cmp rax, r13
    cmova r13, rax

    ; Align to 4096 page boundary
    add r13, 4095
    and r13, -4096

    ; SYS_mremap(file_ptr, file_capacity, new_capacity, MREMAP_MAYMOVE)
    mov rax, SYS_mremap
    mov rdi, [rel file_ptr]
    mov rsi, [rel file_capacity]
    mov rdx, r13
    mov r10d, MREMAP_MAYMOVE
    xor r8d, r8d
    syscall

    cmp rax, -4095
    jae .ensure_fail

    mov [rel file_ptr], rax

    ; Zero out newly added memory
    mov rdi, rax
    add rdi, [rel file_capacity]
    mov rcx, r13
    sub rcx, [rel file_capacity]
    xor al, al
    rep stosb

    mov [rel file_capacity], r13
    xor eax, eax
    jmp .ensure_done

.cap_ok:
    xor eax, eax
    jmp .ensure_done

.ensure_fail:
    mov rax, -1

.ensure_done:
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
    sub rsp, 8                        ; 16-byte alignment

    call file_close

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
    mov qword [rel file_capacity], 4096
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
; Explicitly saves memory contents to disk (copy-on-write commit)
; Truncates to file_size and calls fsync
; Returns 0 on success, negative on error
; ------------------------------------------------------------------------------
global file_save
file_save:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    cmp dword [rel is_readonly], 1
    je .save_ro_err

    cmp dword [rel is_scratch], 1
    je .save_scratch_err

    mov rbx, [rel file_ptr]
    test rbx, rbx
    jz .save_no_file

    ; If file_fd == -1, create file: SYS_open(file_path, O_CREAT | O_WRONLY | O_TRUNC, 0644o)
    mov edi, [rel file_fd]
    cmp edi, 0
    jge .have_fd

    mov rax, SYS_open
    lea rdi, [rel file_path]
    mov esi, O_CREAT | O_WRONLY | O_TRUNC
    mov edx, 420                      ; 0644 octal
    syscall

    cmp rax, 0
    jl .save_sys_err
    mov [rel file_fd], eax

.have_fd:
    ; Seek to 0: SYS_lseek(fd, 0, SEEK_SET)
    mov rax, SYS_lseek
    mov edi, [rel file_fd]
    xor esi, esi
    xor edx, edx
    syscall

    cmp rax, 0
    jl .save_sys_err

    ; Write file_size bytes
    mov r12, [rel file_size]
    xor r13, r13
.save_write_loop:
    cmp r13, r12
    jae .save_write_done

    mov rax, SYS_write
    mov edi, [rel file_fd]
    lea rsi, [rbx + r13]
    mov rdx, r12
    sub rdx, r13
    syscall

    cmp rax, 0
    jle .save_sys_err
    add r13, rax
    jmp .save_write_loop

.save_write_done:
    ; ftruncate(fd, file_size)
    mov rax, SYS_ftruncate
    mov edi, [rel file_fd]
    mov rsi, [rel file_size]
    syscall

    cmp rax, 0
    jl .save_sys_err

    ; fsync(fd)
    mov rax, SYS_fsync
    mov edi, [rel file_fd]
    syscall

    cmp rax, 0
    jl .save_sys_err

    ; Clear dirty flag
    mov dword [rel is_dirty], 0

    xor eax, eax
    jmp .save_done

.save_ro_err:
    mov rax, -1
    jmp .save_done

.save_scratch_err:
    mov rax, -2
    jmp .save_done

.save_no_file:
    mov rax, -3
    jmp .save_done

.save_sys_err:
    mov rax, -4

.save_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; file_save_as:
; Saves memory contents to a newly specified file path (Save As...)
; rdi = pointer to null-terminated new file path string
; Returns rax = 0 on success, negative error code on failure
; ------------------------------------------------------------------------------
global file_save_as
file_save_as:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    mov r12, rdi                      ; save new path pointer
    test r12, r12
    jz .fsa_null_err
    cmp byte [r12], 0
    jz .fsa_null_err

    mov rbx, [rel file_ptr]
    test rbx, rbx
    jz .fsa_no_buf

    ; Close previous file descriptor if open
    mov edi, [rel file_fd]
    cmp edi, 0
    jle .fsa_skip_close
    mov rax, SYS_close
    syscall
    mov dword [rel file_fd], -1

.fsa_skip_close:
    ; Copy new path into file_path buffer
    lea rsi, [r12]
    lea rdi, [rel file_path]
    mov ecx, 511
.fsa_copy_loop:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jz .fsa_copy_done
    dec ecx
    jnz .fsa_copy_loop
    mov byte [rdi], 0
.fsa_copy_done:

    ; Create/open target file with O_CREAT | O_RDWR | O_TRUNC, mode 0644o (420)
    mov rax, SYS_open
    lea rdi, [rel file_path]
    mov esi, O_CREAT | O_RDWR | O_TRUNC
    mov edx, 420                      ; 0644 octal
    syscall

    cmp rax, 0
    jl .fsa_open_err
    mov [rel file_fd], eax

    ; Write contents from memory: SYS_write(fd, file_ptr, file_size)
    mov r12, [rel file_size]
    xor r13, r13
.fsa_write_loop:
    cmp r13, r12
    jae .fsa_write_done
    mov rax, SYS_write
    mov edi, [rel file_fd]
    lea rsi, [rbx + r13]
    mov rdx, r12
    sub rdx, r13
    syscall

    cmp rax, 0
    jle .fsa_write_err
    add r13, rax
    jmp .fsa_write_loop

.fsa_write_done:
    ; ftruncate(fd, file_size)
    mov rax, SYS_ftruncate
    mov edi, [rel file_fd]
    mov rsi, [rel file_size]
    syscall

    ; fsync(fd)
    mov rax, SYS_fsync
    mov edi, [rel file_fd]
    syscall

    ; Reset status flags: now a saved, editable, non-scratch file!
    mov dword [rel is_readonly], 0
    mov dword [rel is_scratch], 0
    mov dword [rel is_dirty], 0

    xor eax, eax                      ; 0 = Success
    jmp .fsa_done

.fsa_null_err:
    mov rax, -1
    jmp .fsa_done

.fsa_no_buf:
    mov rax, -2
    jmp .fsa_done

.fsa_open_err:
    mov rax, -3
    jmp .fsa_done

.fsa_write_err:
    mov rax, -4

.fsa_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
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

    mov rsi, [rel file_capacity]
    test rsi, rsi
    jnz .do_unmap
    mov rsi, 65536
.do_unmap:
    mov rax, SYS_munmap
    syscall
    mov qword [rel file_ptr], 0
    mov qword [rel file_capacity], 0
    mov qword [rel file_size], 0

.no_unmap:
    mov edi, [rel file_fd]
    cmp edi, 0
    jle .no_close
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

    ; Open read-only
    mov rax, SYS_open
    lea rdi, [rel file2_path]
    mov esi, O_RDONLY
    xor edx, edx
    syscall

    cmp rax, 0
    jl .f2_open_failed

    mov [rel file2_fd], eax
    mov dword [rel is_readonly2], 0

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

    ; Enforce 4 GiB file size limit
    mov rsi, MAX_FILE_SIZE
    cmp rax, rsi
    ja .f2_fstat_failed

    ; capacity = max(file2_size + 4096, 4096), page aligned
    mov rsi, rax
    add rsi, 4096
    add rsi, 4095
    and rsi, -4096
    mov [rel file2_capacity], rsi

    ; Allocate anonymous private memory
    mov rax, SYS_mmap
    xor edi, edi
    ; rsi = file2_capacity
    mov edx, PROT_READ | PROT_WRITE
    mov r10d, MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    syscall

    cmp rax, -4095
    jae .f2_mmap_failed

    mov [rel file2_ptr], rax

    ; Read file2 contents
    mov r12, [rel file2_size]
    test r12, r12
    jz .f2_read_done

    mov rbx, rax
    xor r13, r13
.f2_read_loop:
    cmp r13, r12
    jae .f2_read_done
    mov rax, SYS_read
    mov edi, [rel file2_fd]
    lea rsi, [rbx + r13]
    mov rdx, r12
    sub rdx, r13
    syscall

    cmp rax, 0
    jle .f2_read_done
    add r13, rax
    jmp .f2_read_loop

.f2_read_done:
    xor eax, eax
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
    mov qword [rel file2_capacity], 0
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

    mov rsi, [rel file2_capacity]
    test rsi, rsi
    jnz .f2_do_unmap
    mov rsi, 4096
.f2_do_unmap:
    mov rax, SYS_munmap
    syscall
    mov qword [rel file2_ptr], 0
    mov qword [rel file2_capacity], 0
    mov qword [rel file2_size], 0

.f2_no_unmap:
    mov edi, [rel file2_fd]
    cmp edi, 0
    jle .f2_no_close
    mov rax, SYS_close
    syscall
    mov dword [rel file2_fd], -1

.f2_no_close:
    mov qword [rel file2_ptr], 0
    mov qword [rel file2_size], 0
    mov qword [rel file2_capacity], 0
    ret
