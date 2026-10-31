; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; macros.inc - High performance assembly macros and helpers
; ==============================================================================

; Clear a register to zero
%macro ZERO 1
    xor %1, %1
%endmacro

; Direct Linux Syscall macro
%macro SYSCALL_1 2
    mov rax, %1
    mov rdi, %2
    syscall
%endmacro

%macro SYSCALL_2 3
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    syscall
%endmacro

%macro SYSCALL_3 4
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    mov rdx, %4
    syscall
%endmacro

%macro SYSCALL_6 7
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    mov rdx, %4
    mov r10, %5
    mov r8,  %6
    mov r9,  %7
    syscall
%endmacro

; Clamp register value to [min, max]
%macro CLAMP 3
    cmp %1, %2
    jge %%not_below
    mov %1, %2
%%not_below:
    cmp %1, %3
    jle %%not_above
    mov %1, %3
%%not_above:
%endmacro

; Cross-platform dynamic linker call (ELF PLT on Linux, host bridge on Windows)
%ifdef OS_WINDOWS
    %macro CALL_PLT 1
        call host_%1
    %endmacro
%else
    %macro CALL_PLT 1
        call %1 wrt ..plt
    %endmacro
%endif
