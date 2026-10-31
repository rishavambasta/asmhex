; ==============================================================================
; AsmHex - Ultra-Fast Pure x86_64 Assembly Hexadecimal File Viewer & Editor
; x11_shm.asm - Zero-copy MIT-SHM shared memory X11 window & display pipeline
; ==============================================================================

%include "constants.inc"
%include "macros.inc"

extern XOpenDisplay
extern XCreateSimpleWindow
extern XResizeWindow
extern XSelectInput
extern XMapWindow
extern XStoreName
extern XCreateGC
extern XDefaultScreen
extern XRootWindow
extern XDefaultVisual
extern XDefaultDepth
extern XNextEvent
extern XEventsQueued
extern XPending
extern XLookupString
extern XShmQueryExtension
extern XShmCreateImage
extern XShmAttach
extern XShmPutImage
extern XShmDetach
extern XCreateImage
extern XPutImage
extern XDestroyImage
extern XSync
extern XFlush
extern XInternAtom
extern XSetWMProtocols
extern XDestroyWindow
extern XCloseDisplay
extern XChangeProperty
extern XSendEvent
extern XConvertSelection
extern XGetWindowProperty
extern XFree
extern XAllocSizeHints
extern XSetWMNormalHints
extern shmget
extern shmat
extern shmdt
extern shmctl
extern malloc
extern free

section .data
    IPC_PRIVATE     equ 0
    IPC_CREAT       equ 01000o
    IPC_RMID        equ 0
    ZPixmap         equ 2
    QueuedAlready   equ 0

    del_atom_name:  db "WM_DELETE_WINDOW", 0

    xdnd_version:          dq 5
    str_xdnd_aware:        db "XdndAware", 0
    str_xdnd_enter:        db "XdndEnter", 0
    str_xdnd_position:     db "XdndPosition", 0
    str_xdnd_status:       db "XdndStatus", 0
    str_xdnd_drop:         db "XdndDrop", 0
    str_xdnd_finished:     db "XdndFinished", 0
    str_xdnd_selection:    db "XdndSelection", 0
    str_xdnd_action_copy:  db "XdndActionCopy", 0
    str_text_uri_list:     db "text/uri-list", 0

section .bss
    global disp
    global screen
    global root
    global win
    global gc
    global vis
    global depth
    global wm_del_atom
    global xdnd_aware_atom
    global xdnd_enter_atom
    global xdnd_position_atom
    global xdnd_status_atom
    global xdnd_drop_atom
    global xdnd_finished_atom
    global xdnd_selection_atom
    global xdnd_action_copy_atom
    global text_uri_list_atom
    global ximage
    global shminfo
    global use_shm
    global win_w
    global win_h
    global fb_data
    global fb_pitch

    alignb 16
    disp:           resq 1            ; Display *
    screen:         resd 1            ; int
    root:           resq 1            ; Window
    win:            resq 1            ; Window
    gc:             resq 1            ; GC
    vis:            resq 1            ; Visual *
    depth:          resd 1            ; int
    wm_del_atom:    resq 1            ; Atom

    xdnd_aware_atom:       resq 1
    xdnd_enter_atom:       resq 1
    xdnd_position_atom:    resq 1
    xdnd_status_atom:      resq 1
    xdnd_drop_atom:        resq 1
    xdnd_finished_atom:    resq 1
    xdnd_selection_atom:   resq 1
    xdnd_action_copy_atom: resq 1
    text_uri_list_atom:    resq 1

    ximage:         resq 1            ; XImage *
    ; XShmSegmentInfo (32 bytes):
    ; shmseg (8), shmid (4), pad (4), shmaddr (8), readOnly (4), pad (4)
    alignb 16
    shminfo:        resb 32
    use_shm:        resd 1            ; 1 = SHM active, 0 = fallback XPutImage

    win_w:          resd 1            ; Window width
    win_h:          resd 1            ; Window height
    fb_data:        resq 1            ; Framebuffer pointer
    fb_pitch:       resq 1            ; Bytes per scanline

section .text

; ------------------------------------------------------------------------------
; x11_init:
; rdi = title string ptr, esi = initial width, edx = initial height
; Returns rax = 0 on success, negative on error
; ------------------------------------------------------------------------------
global x11_init
x11_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte alignment (40 + 8 = 48)

    mov r12, rdi                      ; title
    mov [rel win_w], esi
    mov [rel win_h], edx

    ; XOpenDisplay(NULL)
    xor rdi, rdi
    call XOpenDisplay wrt ..plt
    test rax, rax
    jz .err_open_disp
    mov [rel disp], rax

    ; XDefaultScreen(disp)
    mov rdi, [rel disp]
    call XDefaultScreen wrt ..plt
    mov [rel screen], eax

    ; XRootWindow(disp, screen)
    mov rdi, [rel disp]
    mov esi, [rel screen]
    call XRootWindow wrt ..plt
    mov [rel root], rax

    ; XDefaultVisual(disp, screen)
    mov rdi, [rel disp]
    mov esi, [rel screen]
    call XDefaultVisual wrt ..plt
    mov [rel vis], rax

    ; XDefaultDepth(disp, screen)
    mov rdi, [rel disp]
    mov esi, [rel screen]
    call XDefaultDepth wrt ..plt
    mov [rel depth], eax

    ; Create window: XCreateSimpleWindow(disp, root, 0, 0, width, height, 0, 0, 0)
    mov rdi, [rel disp]
    mov rsi, [rel root]
    xor edx, edx                      ; x = 0
    xor ecx, ecx                      ; y = 0
    mov r8d, [rel win_w]              ; width
    mov r9d, [rel win_h]              ; height
    sub rsp, 8                        ; stack alignment for 3 pushes (8 + 24 = 32)
    push 0                            ; background = black
    push 0                            ; border = black
    push 0                            ; border_width = 0
    call XCreateSimpleWindow wrt ..plt
    add rsp, 32
    mov [rel win], rax

    ; XStoreName(disp, win, title)
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov rdx, r12
    call XStoreName wrt ..plt

    ; Set minimum window size hints (760x360)
    call XAllocSizeHints wrt ..plt
    test rax, rax
    jz .skip_size_hints
    mov rbx, rax                      ; rbx = XSizeHints *
    mov qword [rbx + 0], 16           ; flags = PMinSize (16)
    mov dword [rbx + 24], 760         ; min_width = 760
    mov dword [rbx + 28], 360         ; min_height = 360
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov rdx, rbx
    call XSetWMNormalHints wrt ..plt
    mov rdi, rbx
    call XFree wrt ..plt
.skip_size_hints:

    ; Setup WM_DELETE_WINDOW atom
    mov rdi, [rel disp]
    lea rsi, [rel del_atom_name]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel wm_del_atom], rax

    mov rdi, [rel disp]
    mov rsi, [rel win]
    lea rdx, [rel wm_del_atom]
    mov ecx, 1
    call XSetWMProtocols wrt ..plt

    ; Setup XDnD Atoms
    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_aware]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_aware_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_enter]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_enter_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_position]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_position_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_status]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_status_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_drop]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_drop_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_finished]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_finished_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_selection]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_selection_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_xdnd_action_copy]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel xdnd_action_copy_atom], rax

    mov rdi, [rel disp]
    lea rsi, [rel str_text_uri_list]
    xor edx, edx
    call XInternAtom wrt ..plt
    mov [rel text_uri_list_atom], rax

    ; Set XdndAware property (version 5) on win
    ; XChangeProperty(disp, win, property, type, format, mode, data, nelements)
    push qword 1                      ; nelements = 1
    lea rax, [rel xdnd_version]
    push rax                          ; data pointer
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov rdx, [rel xdnd_aware_atom]
    mov ecx, 4                        ; XA_ATOM = 4
    mov r8d, 32                       ; 32-bit format
    xor r9d, r9d                      ; PropModeReplace = 0
    call XChangeProperty wrt ..plt
    add rsp, 16

    ; XSelectInput with Mouse Button Release and Motion events for Drag Selection & Scrollbar
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov edx, ExposureMask | KeyPressMask | ButtonPressMask | ButtonReleaseMask | Button1MotionMask | StructureNotifyMask
    call XSelectInput wrt ..plt

    ; Create GC
    mov rdi, [rel disp]
    mov rsi, [rel win]
    xor edx, edx
    xor ecx, ecx
    call XCreateGC wrt ..plt
    mov [rel gc], rax

    ; Allocate Framebuffer (MIT-SHM or Fallback)
    call x11_create_framebuffer
    test eax, eax
    jnz .err_fb

    ; XMapWindow(disp, win)
    mov rdi, [rel disp]
    mov rsi, [rel win]
    call XMapWindow wrt ..plt

    ; XSync(disp, 0)
    mov rdi, [rel disp]
    xor esi, esi
    call XSync wrt ..plt

    xor eax, eax                      ; Success
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.err_open_disp:
    mov rax, -1
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.err_fb:
    mov rax, -2
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_create_framebuffer:
; Allocates backbuffer via XShm or XCreateImage
; ------------------------------------------------------------------------------
global x11_create_framebuffer
x11_create_framebuffer:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8                        ; 16-byte alignment (24 + 8 = 32)

    ; Test if XShm extension is supported
    mov rdi, [rel disp]
    call XShmQueryExtension wrt ..plt
    test eax, eax
    jz .fallback_alloc

    ; Try XShmCreateImage
    mov rdi, [rel disp]
    mov rsi, [rel vis]
    mov edx, [rel depth]
    mov ecx, ZPixmap
    xor r8d, r8d                      ; data = NULL
    lea r9, [rel shminfo]
    mov eax, [rel win_h]
    push rax                          ; height (8 bytes)
    mov eax, [rel win_w]
    push rax                          ; width (8 bytes)
    call XShmCreateImage wrt ..plt
    add rsp, 16

    test rax, rax
    jz .fallback_alloc
    mov [rel ximage], rax

    ; Image total size = bytes_per_line * height
    ; bytes_per_line is at offset 44, height is at offset 4
    mov edx, [rax + 44]               ; bytes_per_line
    mov ecx, [rax + 4]                ; height
    imul rdx, rcx                     ; total buffer bytes

    ; shmget(IPC_PRIVATE, size, IPC_CREAT | 0777)
    mov rdi, IPC_PRIVATE
    mov rsi, rdx
    mov edx, IPC_CREAT | 0777o
    call shmget wrt ..plt
    cmp eax, 0
    jl .fallback_alloc
    mov [rel shminfo + 8], eax        ; shmid

    ; shmat(shmid, NULL, 0)
    mov edi, eax
    xor esi, esi
    xor edx, edx
    call shmat wrt ..plt
    cmp rax, -1
    je .fallback_alloc
    mov [rel shminfo + 16], rax       ; shmaddr

    ; ximage->data = shmaddr
    mov rbx, [rel ximage]
    mov [rbx + 16], rax
    mov [rel fb_data], rax

    ; fb_pitch = ximage->bytes_per_line
    mov eax, [rbx + 44]
    mov [rel fb_pitch], rax

    ; shminfo.readOnly = 0
    mov dword [rel shminfo + 24], 0

    ; XShmAttach(disp, &shminfo)
    mov rdi, [rel disp]
    lea rsi, [rel shminfo]
    call XShmAttach wrt ..plt

    ; XSync(disp, 0)
    mov rdi, [rel disp]
    xor esi, esi
    call XSync wrt ..plt

    ; shmctl(shminfo.shmid, IPC_RMID, 0) -> mark for auto destruction on exit
    mov edi, [rel shminfo + 8]
    mov esi, IPC_RMID
    xor edx, edx
    call shmctl wrt ..plt

    mov dword [rel use_shm], 1
    xor eax, eax
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.fallback_alloc:
    ; Fallback to standard malloc + XCreateImage
    mov eax, [rel win_w]
    mov ecx, [rel win_h]
    imul rax, rcx
    shl rax, 2                        ; width * height * 4
    mov rdi, rax
    call malloc wrt ..plt
    test rax, rax
    jz .alloc_fail
    mov [rel fb_data], rax

    ; XCreateImage(disp, vis, depth, ZPixmap, 0, data, w, h, 32, 0)
    mov rdi, [rel disp]
    mov rsi, [rel vis]
    mov edx, [rel depth]
    mov ecx, ZPixmap
    xor r8d, r8d                      ; offset = 0
    mov r9, [rel fb_data]             ; data
    push 0                            ; bytes_per_line = 0 (auto)
    push 32                           ; bitmap_pad = 32
    mov eax, [rel win_h]
    push rax                          ; height
    mov eax, [rel win_w]
    push rax                          ; width
    call XCreateImage wrt ..plt
    add rsp, 32

    test rax, rax
    jz .alloc_fail
    mov [rel ximage], rax

    ; fb_pitch = ximage->bytes_per_line
    mov edx, [rax + 44]
    mov [rel fb_pitch], rdx

    mov dword [rel use_shm], 0
    xor eax, eax
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.alloc_fail:
    mov rax, -1
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_flush:
; Flushes the rendered backbuffer to screen
; ------------------------------------------------------------------------------
global x11_flush
x11_flush:
    push rbp
    mov rbp, rsp                      ; rsp % 16 == 0

    cmp dword [rel use_shm], 1
    jne .flush_putimage

    ; XShmPutImage(disp, win, gc, ximage, 0, 0, 0, 0, width, height, False)
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov rdx, [rel gc]
    mov rcx, [rel ximage]
    xor r8d, r8d                      ; src_x = 0
    xor r9d, r9d                      ; src_y = 0
    sub rsp, 8                        ; pad so 5 pushes + pad = 48 (0 mod 16)
    push 0                            ; arg 11: send_event = False
    mov eax, [rel win_h]
    push rax                          ; arg 10: src_height
    mov eax, [rel win_w]
    push rax                          ; arg 9: src_width
    push 0                            ; arg 8: dst_y = 0
    push 0                            ; arg 7: dst_x = 0
    call XShmPutImage wrt ..plt
    add rsp, 48
    jmp .do_xflush

.flush_putimage:
    ; XPutImage(disp, win, gc, ximage, 0, 0, 0, 0, width, height)
    mov rdi, [rel disp]
    mov rsi, [rel win]
    mov rdx, [rel gc]
    mov rcx, [rel ximage]
    xor r8d, r8d
    xor r9d, r9d
    mov eax, [rel win_h]
    push rax                          ; height
    mov eax, [rel win_w]
    push rax                          ; width
    push 0                            ; dest_y
    push 0                            ; dest_x
    call XPutImage wrt ..plt
    add rsp, 32

.do_xflush:
    mov rdi, [rel disp]
    call XFlush wrt ..plt             ; rsp is 0 mod 16!
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_destroy_framebuffer:
; Safely detaches SHM, frees malloc backbuffer, and destroys XImage
; ------------------------------------------------------------------------------
global x11_destroy_framebuffer
x11_destroy_framebuffer:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8                        ; 16-byte stack alignment

    cmp dword [rel use_shm], 1
    jne .destroy_fallback

    ; SHM path
    mov rax, [rel ximage]
    test rax, rax
    jz .destroy_shm_addr

    ; XShmDetach(disp, &shminfo)
    mov rdi, [rel disp]
    lea rsi, [rel shminfo]
    call XShmDetach wrt ..plt

    ; XSync(disp, 0)
    mov rdi, [rel disp]
    xor esi, esi
    call XSync wrt ..plt

.destroy_shm_addr:
    ; shmdt(shminfo.shmaddr)
    mov rdi, [rel shminfo + 16]
    test rdi, rdi
    jz .destroy_shm_img
    call shmdt wrt ..plt
    mov qword [rel shminfo + 16], 0

.destroy_shm_img:
    mov rax, [rel ximage]
    test rax, rax
    jz .destroy_done
    ; Clear ximage->data before XDestroyImage so it doesn't free() shmaddr
    mov qword [rax + 16], 0
    mov rdi, rax
    call XDestroyImage wrt ..plt
    mov qword [rel ximage], 0
    mov qword [rel fb_data], 0
    mov dword [rel shminfo + 8], 0
    jmp .destroy_done

.destroy_fallback:
    ; Fallback malloc path
    mov rdi, [rel fb_data]
    test rdi, rdi
    jz .destroy_fb_img
    call free wrt ..plt
    mov qword [rel fb_data], 0

.destroy_fb_img:
    mov rax, [rel ximage]
    test rax, rax
    jz .destroy_done
    mov qword [rax + 16], 0
    mov rdi, rax
    call XDestroyImage wrt ..plt
    mov qword [rel ximage], 0

.destroy_done:
    add rsp, 8
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_resize:
; Resizes framebuffer to new width (edi) and height (esi)
; edi = new_w, esi = new_h
; Returns eax = 0 on success, negative on error
; ------------------------------------------------------------------------------
global x11_resize
x11_resize:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8                        ; 16-byte alignment

    ; Clamp minimum dimensions
    cmp edi, 400
    jge .w_ok
    mov edi, 400
.w_ok:
    cmp esi, 200
    jge .h_ok
    mov esi, 200
.h_ok:

    ; If dimensions are unchanged, do nothing
    cmp edi, [rel win_w]
    jne .do_realloc
    cmp esi, [rel win_h]
    je .resize_done

.do_realloc:
    mov r12d, edi                     ; r12d = new_w
    mov r13d, esi                     ; r13d = new_h

    ; 1. Destroy existing framebuffer
    call x11_destroy_framebuffer

    ; 2. Update dimensions
    mov [rel win_w], r12d
    mov [rel win_h], r13d

    ; 3. Allocate new framebuffer
    call x11_create_framebuffer
    test eax, eax
    jnz .resize_fail

.resize_done:
    xor eax, eax
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.resize_fail:
    mov rax, -1
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_set_window_size:
; Requests X11 window resize via XResizeWindow, flushes display
; edi = new_width, esi = new_height
; ------------------------------------------------------------------------------
global x11_set_window_size
x11_set_window_size:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    sub rsp, 8

    mov r12d, edi                     ; new_width
    mov r13d, esi                     ; new_height

    mov rax, [rel disp]
    test rax, rax
    jz .sw_done

    mov rsi, [rel win]
    test rsi, rsi
    jz .sw_done

    ; XResizeWindow(disp, win, width, height)
    mov rdi, rax
    ; rsi is win
    mov edx, r12d
    mov ecx, r13d
    call XResizeWindow wrt ..plt

    mov rdi, [rel disp]
    call XFlush wrt ..plt

.sw_done:
    add rsp, 8
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_cleanup:
; Detaches SHM, frees resources, closes display
; ------------------------------------------------------------------------------
global x11_cleanup
x11_cleanup:
    push rbp
    mov rbp, rsp

    call x11_destroy_framebuffer

    mov rdi, [rel disp]
    test rdi, rdi
    jz .skip_close

    mov rsi, [rel win]
    test rsi, rsi
    jz .skip_win
    call XDestroyWindow wrt ..plt
.skip_win:

    mov rdi, [rel disp]
    call XCloseDisplay wrt ..plt
    mov qword [rel disp], 0
    mov qword [rel win], 0

.skip_close:
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_send_xdnd_status:
; Sends XdndStatus ClientMessage back to the drag source window
; rdi = target_window, esi = accept (1 or 0), rdx = action_atom
; ------------------------------------------------------------------------------
global x11_send_xdnd_status
x11_send_xdnd_status:
    push rbp
    mov rbp, rsp
    sub rsp, 208                      ; 192 bytes for XClientMessageEvent aligned to 16
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8                        ; 16-byte alignment (40 + 8 = 48)

    mov r12, rdi                      ; target_win
    mov r13d, esi                     ; accept
    mov r14, rdx                      ; action

    ; Zero out event buffer
    lea rdi, [rbp - 208]
    xor eax, eax
    mov ecx, 24                       ; 24 * 8 = 192 bytes
    rep stosq

    ; Setup XClientMessageEvent
    lea rbx, [rbp - 208]
    mov dword [rbx + 0], ClientMessage ; type = 33
    mov rax, r12
    mov [rbx + 32], rax               ; window = target_win
    mov rax, [rel xdnd_status_atom]
    mov [rbx + 40], rax               ; message_type = XdndStatus
    mov dword [rbx + 48], 32          ; format = 32

    ; data.l[0] = our window
    mov rax, [rel win]
    mov [rbx + 56], rax
    ; data.l[1] = accept flags (bit 0 = accept: 1/0, bit 1 = 0: want position events)
    movzx eax, r13b
    and eax, 1
    mov [rbx + 64], rax
    ; data.l[2] = 0 (empty rectangle)
    mov qword [rbx + 72], 0
    ; data.l[3] = 0
    mov qword [rbx + 80], 0
    ; data.l[4] = action
    mov [rbx + 88], r14

    ; XSendEvent(disp, target_win, False, NoEventMask, event)
    mov rdi, [rel disp]
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    mov r8, rbx
    call XSendEvent wrt ..plt

    mov rdi, [rel disp]
    call XFlush wrt ..plt

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 208
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_send_xdnd_finished:
; Sends XdndFinished ClientMessage to the drag source window
; rdi = target_window, esi = accept (1 or 0), rdx = action_atom
; ------------------------------------------------------------------------------
global x11_send_xdnd_finished
x11_send_xdnd_finished:
    push rbp
    mov rbp, rsp
    sub rsp, 208
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8

    mov r12, rdi                      ; target_win
    mov r13d, esi                     ; accept
    mov r14, rdx                      ; action

    lea rdi, [rbp - 208]
    xor eax, eax
    mov ecx, 24
    rep stosq

    lea rbx, [rbp - 208]
    mov dword [rbx + 0], ClientMessage
    mov rax, r12
    mov [rbx + 32], rax
    mov rax, [rel xdnd_finished_atom]
    mov [rbx + 40], rax
    mov dword [rbx + 48], 32

    mov rax, [rel win]
    mov [rbx + 56], rax
    movzx eax, r13b
    and eax, 1
    mov [rbx + 64], rax
    mov [rbx + 72], r14

    mov rdi, [rel disp]
    mov rsi, r12
    xor edx, edx
    xor ecx, ecx
    mov r8, rbx
    call XSendEvent wrt ..plt

    mov rdi, [rel disp]
    call XFlush wrt ..plt

    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 208
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_convert_xdnd_drop:
; Requests conversion of dropped data to text/uri-list
; rdi = timestamp
; ------------------------------------------------------------------------------
global x11_convert_xdnd_drop
x11_convert_xdnd_drop:
    push rbp
    mov rbp, rsp
    push rbx
    sub rsp, 8

    ; XConvertSelection(disp, xdnd_selection, text_uri_list, xdnd_selection, win, time)
    mov r9, rdi                       ; time
    mov rdi, [rel disp]
    mov rsi, [rel xdnd_selection_atom]
    mov rdx, [rel text_uri_list_atom]
    mov rcx, [rel xdnd_selection_atom]
    mov r8, [rel win]
    call XConvertSelection wrt ..plt

    add rsp, 8
    pop rbx
    pop rbp
    ret

; ------------------------------------------------------------------------------
; x11_get_drop_file_path:
; Reads dropped URI data from window property and decodes it to a local file path
; rdi = property (from SelectionNotify), rsi = out_buf, edx = max_len
; Returns rax = 1 on success, 0 on failure
; ------------------------------------------------------------------------------
global x11_get_drop_file_path
x11_get_drop_file_path:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 96 + 8                   ; 96 bytes for local vars + stack args, +8 align (48 + 96 = 144)

    test rdi, rdi
    jz .gfp_fail

    mov r12, rsi                      ; out_buf
    mov r13d, edx                     ; max_len
    dec r13d                          ; reserve 1 byte for null terminator

    ; Stack layout relative to rbp:
    ; rbp - 48: actual_type (8)
    ; rbp - 56: actual_format (8)
    ; rbp - 64: nitems (8)
    ; rbp - 72: bytes_after (8)
    ; rbp - 80: prop_data (8)

    ; Stack arguments for XGetWindowProperty:
    ; [rsp + 0]:  req_type = 0 (AnyPropertyType)
    ; [rsp + 8]:  actual_type_return = rbp - 48
    ; [rsp + 16]: actual_format_return = rbp - 56
    ; [rsp + 24]: nitems_return = rbp - 64
    ; [rsp + 32]: bytes_after_return = rbp - 72
    ; [rsp + 40]: prop_return = rbp - 80

    mov qword [rsp + 0], 0            ; AnyPropertyType
    lea rax, [rbp - 48]
    mov [rsp + 8], rax
    lea rax, [rbp - 56]
    mov [rsp + 16], rax
    lea rax, [rbp - 64]
    mov [rsp + 24], rax
    lea rax, [rbp - 72]
    mov [rsp + 32], rax
    lea rax, [rbp - 80]
    mov [rsp + 40], rax

    mov rsi, [rel win]
    mov rdx, rdi                      ; property
    mov rdi, [rel disp]
    xor ecx, ecx                      ; long_offset = 0
    mov r8d, 1024                     ; long_length = 1024
    mov r9d, 1                        ; delete = True (1)
    call XGetWindowProperty wrt ..plt

    test eax, eax
    jnz .gfp_fail

    mov rsi, [rbp - 80]               ; prop_data
    test rsi, rsi
    jz .gfp_fail

    mov rax, [rbp - 64]               ; nitems
    test rax, rax
    jz .gfp_free_fail

    ; r14 = end pointer (prop_data + nitems)
    mov r14, rsi
    add r14, rax

    ; rsi = prop_data string
    ; Parse URI into r12 (out_buf)
.gfp_skip_ws:
    cmp rsi, r14
    jae .gfp_finish
    mov al, [rsi]
    cmp al, ' '
    je .gfp_inc_ws
    cmp al, 9
    je .gfp_inc_ws
    cmp al, 10
    je .gfp_inc_ws
    cmp al, 13
    je .gfp_inc_ws
    jmp .gfp_check_proto
.gfp_inc_ws:
    inc rsi
    jmp .gfp_skip_ws

.gfp_check_proto:
    ; Check if starts with "file://"
    mov rax, r14
    sub rax, rsi
    cmp rax, 7
    jb .gfp_parse_chars
    cmp dword [rsi], 0x656C6966       ; "file"
    jne .gfp_parse_chars
    cmp word [rsi + 4], 0x2F3A        ; ":/"
    jne .gfp_parse_chars
    cmp byte [rsi + 6], '/'
    jne .gfp_parse_chars
    add rsi, 7                        ; skip "file://"

    ; Check if starts with "localhost/"
    mov rax, r14
    sub rax, rsi
    cmp rax, 10
    jb .gfp_parse_chars
    cmp dword [rsi], 0x61636F6C       ; "loca"
    jne .gfp_parse_chars
    cmp dword [rsi + 4], 0x736F686C   ; "lhos"
    jne .gfp_parse_chars
    cmp word [rsi + 8], 0x2F74        ; "t/"
    jne .gfp_parse_chars
    add rsi, 9                        ; leaves leading '/'

.gfp_parse_chars:
    xor ecx, ecx                      ; ecx = output index
.gfp_loop:
    cmp rsi, r14
    jae .gfp_finish
    mov al, [rsi]
    test al, al
    jz .gfp_finish
    cmp al, 10
    je .gfp_finish
    cmp al, 13
    je .gfp_finish

    ; Check percent-encoded %XX
    cmp al, '%'
    jne .gfp_normal_char

    lea rax, [rsi + 2]
    cmp rax, r14
    jae .gfp_normal_char

    movzx eax, byte [rsi + 1]
    test al, al
    jz .gfp_normal_char
    movzx edx, byte [rsi + 2]
    test dl, dl
    jz .gfp_normal_char

    ; Hex char to nibble (al)
    sub al, '0'
    cmp al, 9
    jbe .gfp_h1_ok
    sub al, ('A' - '0')
    cmp al, 5
    jbe .gfp_h1_alpha
    sub al, ('a' - 'A')
    cmp al, 5
    ja .gfp_normal_char
.gfp_h1_alpha:
    add al, 10
.gfp_h1_ok:
    ; Hex char to nibble (dl)
    sub dl, '0'
    cmp dl, 9
    jbe .gfp_h2_ok
    sub dl, ('A' - '0')
    cmp dl, 5
    jbe .gfp_h2_alpha
    sub dl, ('a' - 'A')
    cmp dl, 5
    ja .gfp_normal_char
.gfp_h2_alpha:
    add dl, 10
.gfp_h2_ok:
    shl al, 4
    or al, dl
    mov [r12 + rcx], al
    inc rcx
    add rsi, 3
    cmp ecx, r13d
    jl .gfp_loop
    jmp .gfp_finish

.gfp_normal_char:
    mov [r12 + rcx], al
    inc rcx
    inc rsi
    cmp ecx, r13d
    jl .gfp_loop

.gfp_finish:
    mov byte [r12 + rcx], 0

    ; Free prop_data: XFree(prop_data)
    mov rdi, [rbp - 80]
    call XFree wrt ..plt

    test ecx, ecx
    jz .gfp_fail
    mov eax, 1                        ; Success!
    jmp .gfp_ret

.gfp_free_fail:
    mov rdi, [rbp - 80]
    call XFree wrt ..plt

.gfp_fail:
    xor eax, eax                      ; Failure

.gfp_ret:
    add rsp, 96 + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
