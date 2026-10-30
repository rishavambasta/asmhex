; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; main.asm - Main application entry point, CLI arguments & X11 event loop
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

extern puts
extern printf
extern strcmp
extern exit

extern disp
extern win
extern wm_del_atom
extern win_w
extern win_h
extern x11_init
extern x11_flush
extern x11_cleanup
extern x11_resize
extern dump_screenshot
extern XNextEvent
extern XLookupString

extern xdnd_enter_atom
extern xdnd_position_atom
extern xdnd_drop_atom
extern xdnd_status_atom
extern xdnd_finished_atom
extern xdnd_action_copy_atom
extern x11_send_xdnd_status
extern x11_send_xdnd_finished
extern x11_convert_xdnd_drop
extern x11_get_drop_file_path

extern file_open
extern file_create_blank
extern file_create_scratch
extern file_close
extern file_path
extern file_size
extern is_scratch

extern file2_open
extern file2_close
extern file2_path
extern file2_size
extern is_diff_mode
extern diff_recompute

extern init_crc32_table
extern init_renderer_luts
extern editor_init
extern editor_render
extern editor_update_geometry
extern editor_ensure_visible
extern editor_handle_key
extern editor_handle_click
extern editor_handle_mouse_move
extern editor_handle_button_release
extern editor_handle_wheel
extern editor_set_status

section .data
    app_title:     db "AsmHex v1.1.0 - Pure x86_64 Assembly Hex Editor", 0
    err_disp_msg:  db "Error: Failed to connect to X11 display (check DISPLAY env var).", 0
    err_file_msg:  db "Notice: Could not open file; loaded blank buffer for writing.", 0
    arg_screenshot: db "--screenshot", 0
    arg_diff:       db "--diff", 0
    arg_diff_short: db "-d", 0
    diff_banner:    db "[AsmHex] Diff Mode active: Comparing 2 files.", 10, 0
    banner_console:
        db "================================================================", 10
        db "  AsmHex v1.1.0 - Graphical Hex Editor in Pure x86_64 Assembly  ", 10
        db "  Hardware: Intel Celeron UHD GPU / SSE4.2 Accelerated          ", 10
        db "================================================================", 10, 0

section .bss
    alignb 16
    event_buf:       resb 192          ; XEvent union (192 bytes)
    ascii_buf:       resb 32           ; Character buffer for XLookupString
    keysym_buf:      resq 1            ; KeySym return from XLookupString
    auto_shot_path:  resq 1            ; Path for automatic screenshot
    is_auto_shot:    resd 1            ; 1 if auto-screenshot enabled
    xdnd_source_win: resq 1            ; Window handle of drag-and-drop source
    drop_path_buf:   resb 512          ; Decoded path buffer for dropped files

section .text
global main
main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8                        ; Align stack to 16 bytes (32 + 8 = 40)

    ; Save CLI args BEFORE any function calls clobber rdi/rsi
    mov r12d, edi                     ; argc
    mov r13, rsi                      ; argv

    ; Print greeting to console
    lea rdi, [rel banner_console]
    xor eax, eax
    call printf wrt ..plt

    ; Initialize CLI options
    mov dword [rel is_auto_shot], 0
    mov qword [rel auto_shot_path], 0

    ; Initialize Fast Rendering Lookup Tables, CRC32 Table, & Editor State BEFORE file processing
    call init_renderer_luts
    call init_crc32_table
    call editor_init

    ; 1. Initialize File I/O
    cmp r12d, 2
    jl .no_file_arg

    ; Check if argv[1] is "--screenshot"
    mov rdi, [r13 + 8]
    lea rsi, [rel arg_screenshot]
    call strcmp wrt ..plt
    test eax, eax
    jnz .normal_file_arg

    ; --screenshot mode!
    cmp r12d, 3
    jl .no_file_arg
    mov rax, [r13 + 16]               ; argv[2] (output ppm path)
    mov [rel auto_shot_path], rax
    mov dword [rel is_auto_shot], 1

    ; Check if target file arguments are provided at argv[3] (and argv[4] for diff)
    cmp r12d, 6
    jl .check_shot_two_files

    ; Check if argv[3] is "--diff" or "-d"
    mov rdi, [r13 + 24]               ; argv[3]
    lea rsi, [rel arg_diff]
    call strcmp wrt ..plt
    test eax, eax
    jz .shot_diff_explicit

    mov rdi, [r13 + 24]               ; argv[3]
    lea rsi, [rel arg_diff_short]
    call strcmp wrt ..plt
    test eax, eax
    jz .shot_diff_explicit

.check_shot_two_files:
    cmp r12d, 5
    jl .shot_one_file
    mov rdi, [r13 + 24]               ; argv[3]
    call file_open
    test eax, eax
    jnz .shot_one_file
    mov rdi, [r13 + 32]               ; argv[4]
    call file2_open
    test eax, eax
    jnz .file_ready
    mov dword [rel is_diff_mode], 1
    call diff_recompute
    jmp .file_ready

.shot_diff_explicit:
    mov rdi, [r13 + 32]               ; argv[4]
    call file_open
    test eax, eax
    jnz .shot_one_file
    mov rdi, [r13 + 40]               ; argv[5]
    call file2_open
    test eax, eax
    jnz .file_ready
    mov dword [rel is_diff_mode], 1
    call diff_recompute
    jmp .file_ready

.shot_one_file:
    cmp r12d, 4
    jl .no_file_arg
    mov rdi, [r13 + 24]               ; argv[3]
    call file_open
    test eax, eax
    jz .file_ready
    call file_create_blank
    jmp .file_ready

.normal_file_arg:
    ; Check if argv[1] is "--diff"
    mov rdi, [r13 + 8]
    lea rsi, [rel arg_diff]
    call strcmp wrt ..plt
    test eax, eax
    jz .diff_mode_explicit

    ; Check if argv[1] is "-d"
    mov rdi, [r13 + 8]
    lea rsi, [rel arg_diff_short]
    call strcmp wrt ..plt
    test eax, eax
    jz .diff_mode_explicit

    ; Check if 2 files were provided without flag: ./asmhex file1 file2
    cmp r12d, 3
    jge .check_two_files

.single_file_open:
    mov rdi, [r13 + 8]                ; argv[1]
    call file_open
    test eax, eax
    jz .file_ready

    ; File open failed: create blank buffer and notify user
    lea rdi, [rel err_file_msg]
    call puts wrt ..plt
    call file_create_blank
    jmp .file_ready

.diff_mode_explicit:
    cmp r12d, 4
    jl .no_file_arg
    mov rdi, [r13 + 16]               ; argv[2]
    call file_open
    test eax, eax
    jnz .single_file_open
    mov rdi, [r13 + 24]               ; argv[3]
    call file2_open
    test eax, eax
    jnz .file_ready
    mov dword [rel is_diff_mode], 1
    call diff_recompute
    lea rdi, [rel diff_banner]
    xor eax, eax
    call printf wrt ..plt
    jmp .file_ready

.check_two_files:
    mov rdi, [r13 + 8]                ; argv[1]
    call file_open
    test eax, eax
    jnz .single_file_open
    mov rdi, [r13 + 16]               ; argv[2]
    call file2_open
    test eax, eax
    jnz .file_ready
    mov dword [rel is_diff_mode], 1
    call diff_recompute
    lea rdi, [rel diff_banner]
    xor eax, eax
    call printf wrt ..plt
    jmp .file_ready

.no_file_arg:
    call file_create_blank

.file_ready:
    ; 4. Initialize X11 Display & Zero-Copy MIT-SHM Backbuffer
    lea rdi, [rel app_title]
    mov esi, WIN_DEFAULT_W
    mov edx, WIN_DEFAULT_H
    call x11_init
    test eax, eax
    jnz .disp_error

    call editor_update_geometry

    ; 5. First Frame Render
    call editor_render
    call x11_flush

    ; If automatic screenshot requested, save frame and exit immediately
    cmp dword [rel is_auto_shot], 1
    jne .event_loop

    mov rdi, [rel auto_shot_path]
    call dump_screenshot
    jmp .exit_loop

    ; ==========================================================================
    ; Main X11 Event Loop
    ; ==========================================================================
.event_loop:
    ; XNextEvent(disp, &event_buf)
    mov rdi, [rel disp]
    lea rsi, [rel event_buf]
    call XNextEvent wrt ..plt

    ; Event type is at offset 0
    mov eax, [rel event_buf]

    ; --------------------------------------------------------------------------
    ; A. ClientMessage (Window Close button clicked & XDnD Drag-and-Drop)
    ; --------------------------------------------------------------------------
    cmp eax, ClientMessage
    jne .check_expose

    ; Check if message matches WM_DELETE_WINDOW atom (at data.l[0], offset 56)
    mov rax, [rel event_buf + 56]
    cmp rax, [rel wm_del_atom]
    je .exit_loop

    ; Check XDnD Protocol messages (message_type is at offset 40)
    mov rax, [rel event_buf + 40]
    cmp rax, [rel xdnd_enter_atom]
    jne .check_xdnd_pos
    ; XdndEnter: data.l[0] (offset 56) is drag source window
    mov rax, [rel event_buf + 56]
    mov [rel xdnd_source_win], rax
    jmp .event_loop

.check_xdnd_pos:
    cmp rax, [rel xdnd_position_atom]
    jne .check_xdnd_drop
    ; XdndPosition: source window at offset 56
    mov rax, [rel event_buf + 56]
    mov [rel xdnd_source_win], rax
    mov rdi, rax                      ; target_win = source_win
    mov esi, 1                        ; accept = 1
    mov rdx, [rel xdnd_action_copy_atom]
    call x11_send_xdnd_status
    jmp .event_loop

.check_xdnd_drop:
    cmp rax, [rel xdnd_drop_atom]
    jne .event_loop
    ; XdndDrop: source win at offset 56, time at offset 72 (data.l[2])
    mov rax, [rel event_buf + 56]
    mov [rel xdnd_source_win], rax
    mov rdi, [rel event_buf + 72]     ; time
    call x11_convert_xdnd_drop
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; B. Expose (Window damaged or exposed)
    ; --------------------------------------------------------------------------
.check_expose:
    cmp eax, Expose
    jne .check_key

    call editor_render
    call x11_flush
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; C. KeyPress (Keyboard input)
    ; --------------------------------------------------------------------------
.check_key:
    cmp eax, KeyPress
    jne .check_button

    ; XLookupString(&event_buf, ascii_buf, 32, &keysym_buf, NULL)
    lea rdi, [rel event_buf]          ; &event.xkey
    lea rsi, [rel ascii_buf]          ; ascii buffer
    mov edx, 32                       ; buffer size
    lea rcx, [rel keysym_buf]         ; &keysym
    xor r8d, r8d                      ; status = NULL
    call XLookupString wrt ..plt
    mov r12d, eax                     ; r12d = ascii length

    ; State (modifier mask) is at offset 80 in XKeyEvent
    mov ecx, [rel event_buf + 80]     ; state

    ; editor_handle_key(KeySym, ascii_buf, ascii_len, state)
    mov rdi, [rel keysym_buf]         ; KeySym
    lea rsi, [rel ascii_buf]          ; ascii string
    mov edx, r12d                     ; ascii length
    ; ecx = state
    call editor_handle_key

    ; If editor_handle_key returned 1, user requested quit (Ctrl+Q)
    cmp eax, 1
    je .exit_loop

    call editor_render
    call x11_flush
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; D. ButtonPress (Mouse click or wheel scroll)
    ; --------------------------------------------------------------------------
.check_button:
    cmp eax, ButtonPress
    jne .check_button_release

    ; Mouse X is at offset 64, Y at offset 68, button at offset 84
    mov edi, [rel event_buf + 84]     ; button index

    ; Check wheel buttons (4 = wheel up, 5 = wheel down)
    cmp edi, 4
    je .mouse_wheel
    cmp edi, 5
    je .mouse_wheel

    ; Left Click (Button 1)
    cmp edi, 1
    jne .event_loop

    mov edi, [rel event_buf + 64]     ; mouse_x
    mov esi, [rel event_buf + 68]     ; mouse_y
    call editor_handle_click
    call editor_render
    call x11_flush
    jmp .event_loop

.mouse_wheel:
    ; edi already has button number (4 or 5)
    call editor_handle_wheel
    call editor_render
    call x11_flush
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; E. ButtonRelease (Mouse release for Drag Selection & Scrollbar Dragging)
    ; --------------------------------------------------------------------------
.check_button_release:
    cmp eax, ButtonRelease
    jne .check_motion

    mov edi, [rel event_buf + 84]     ; button index
    cmp edi, 1
    jne .event_loop

    mov edi, [rel event_buf + 64]     ; mouse_x
    mov esi, [rel event_buf + 68]     ; mouse_y
    call editor_handle_button_release
    call editor_render
    call x11_flush
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; F. MotionNotify (Mouse Dragging for Range Selection & Scrollbar Thumb)
    ; --------------------------------------------------------------------------
.check_motion:
    cmp eax, MotionNotify
    jne .check_selection

    mov edi, [rel event_buf + 64]     ; mouse_x
    mov esi, [rel event_buf + 68]     ; mouse_y
    call editor_handle_mouse_move
    call editor_render
    call x11_flush
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; G. SelectionNotify (XDnD Dropped File URI received)
    ; --------------------------------------------------------------------------
.check_selection:
    cmp eax, SelectionNotify
    jne .check_configure

    ; Selection property is at offset 56 in XSelectionEvent
    mov rdi, [rel event_buf + 56]
    test rdi, rdi
    jz .drop_rejected

    lea rsi, [rel drop_path_buf]
    mov edx, 512
    call x11_get_drop_file_path
    test eax, eax
    jz .drop_rejected

    ; Successfully retrieved dropped file path! Send XdndFinished
    mov rdi, [rel xdnd_source_win]
    mov esi, 1                        ; accept = 1
    mov rdx, [rel xdnd_action_copy_atom]
    call x11_send_xdnd_finished

    ; If a file is already loaded and not scratch buffer, enter Diff Mode!
    cmp dword [rel is_scratch], 0
    jne .drop_replace_file

    ; Open dropped file as file 2 for comparison
    lea rdi, [rel drop_path_buf]
    call file2_open
    test eax, eax
    jnz .drop_replace_file

    mov dword [rel is_diff_mode], 1
    call diff_recompute
    call editor_render
    call x11_flush
    jmp .event_loop

.drop_replace_file:
    call file2_close
    mov dword [rel is_diff_mode], 0
    call file_close
    lea rdi, [rel drop_path_buf]
    call file_open
    test eax, eax
    jz .drop_file_ready
    call file_create_scratch

.drop_file_ready:
    call editor_init
    call editor_render
    call x11_flush
    jmp .event_loop

.drop_rejected:
    mov rdi, [rel xdnd_source_win]
    xor esi, esi                      ; accept = 0
    xor edx, edx
    call x11_send_xdnd_finished
    jmp .event_loop

    ; --------------------------------------------------------------------------
    ; H. ConfigureNotify (Window resize or move)
    ; --------------------------------------------------------------------------
.check_configure:
    cmp eax, ConfigureNotify
    jne .event_loop

    ; Only process ConfigureNotify events intended for our application window
    ; event_buf + 40 is event.xconfigure.window
    mov rax, [rel event_buf + 40]
    cmp rax, [rel win]
    jne .event_loop

    ; event_buf + 56 is event.xconfigure.width
    ; event_buf + 60 is event.xconfigure.height
    mov edi, [rel event_buf + 56]     ; new width
    mov esi, [rel event_buf + 60]     ; new height

    ; Compare with current window dimensions
    cmp edi, [rel win_w]
    jne .do_resize
    cmp esi, [rel win_h]
    je .event_loop                    ; Dimensions unchanged (e.g. window move)

.do_resize:
    call x11_resize
    call editor_update_geometry
    call editor_ensure_visible
    call editor_render
    call x11_flush
    jmp .event_loop

    ; ==========================================================================
    ; Clean Application Shutdown
    ; ==========================================================================
.exit_loop:
    call file2_close
    call file_close
    call x11_cleanup

    xor eax, eax
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.disp_error:
    lea rdi, [rel err_disp_msg]
    call puts wrt ..plt
    call file2_close
    call file_close
    mov eax, 1
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
