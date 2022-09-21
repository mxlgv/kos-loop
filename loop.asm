;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                                                              ;;
;; Copyright (C) KolibriOS team 2004-2022. All rights reserved. ;;
;; Distributed under terms of the GNU General Public License    ;;
;;                                                              ;;
;;         Writen by Maxim Logaev (turbocat2001)                ;;
;;                      2022 year                               ;;
;;                                                              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

format PE DLL native
entry START

DEBUG                   = 1
__DEBUG__               = 1
__DEBUG_LEVEL__         = 1


; Loop Driver API.
; Function codes:
;   FN_MOUNT(0)  - mount disk image.
;   FN_UMOUNT(1) - unmount disk image.
;
; To mount, the input is the path to the disk image.
; For unmounting, the input is the path to the disk image
; or the disk name (for example, "loop0").
;
; Returns 0 - if success. Otherwise, an error code.
;

LOOP_IMAGE_PATH_NULL_E  = 1
LOOP_ALLOC_E            = 2
LOOP_BAD_FUNC_E         = 3
LOOP_ALREADY_MOUNTED_E  = 4
LOOP_NO_FREE_SLOT_E     = 5

LOOP_MOUNT   = 0
LOOP_UMOUNT = 1

LOOP_DISK_MAX   = 10
PATH_SIZE       = 4096

include 'inc/proc32.inc'
include 'inc/struct.inc'
include 'inc/macros.inc'
include 'inc/fdo.inc'

struct LOOP_DISK
        Path    dd ?
        Info    DISKMEDIAINFO
ends

struct FILE_INFO
        attr        dd ?
        enc_name    db ?
                    rb 3
        ctime       dd ?
        cdate       dd ?
        atime       dd ?
        adate       dd ?
        mtime       dd ?
        mdate       dd ?
        size        dq ?
        name        rb 520
ends

section '.flat' readable writable executable

proc START c, state, cmdline : dword
        cmp     [state], DRV_ENTRY
        jne     .fail
        invoke  RegService, service_name, service_proc
        ret
  .fail:
        xor     eax, eax
        ret
endp

proc service_proc stdcall, ioctl:dword
        mov     eax, [ioctl + IOCTL.input]
        test    eax, eax
        mov     eax, LOOP_IMAGE_PATH_NULL_E
        jz      .exit

        invoke  strnlen, [ioctl + IOCTL.input], PATH_SIZE
        invoke  Kmalloc
        test    eax, eax
        mov     eax, LOOP_ALLOC_E
        jz      .exit

        cmp     [ioctl + IOCTL.io_code], LOOP_MOUNT
        jnz     .unmount
        call    Mount
        jmp     .exit

  .unmount:
        cmp     [ioctl + IOCTL.io_code], LOOP_UMOUNT
        mov     eax, LOOP_BAD_FUNC
        jnz     .bad_fn
        call    Umount

  .exit:
        ret
endp

; Mount
; Try to mount image to loop
; in:       eax - image path.
proc mount
        call    get_image_info
        test    eax, eax
        jnz     .fail

        ; Validate sector size
        mov     ebx, [file_info + FILE_INFO.size]
        mov     eax, 4096-1

        test    ebx, eax ; is divisible by 4096
        jz      .calc

        shr     eax, 1
        test    ebx, eax ; is divisible by 2048
        jz      .calc

        shr     eax, 2
        test    ebx, eax ; is divisible by 512
        jnz     .bad_sector_size

  .calc:
        inc     eax
        mov     [edx + LOOP_DISK.Info.SectorSize], eax
        mov     eax
        bsf     eax
        shr     ebx, eax
        mov     [edx + LOOP_DISK.Info.Capacity], eax
        xor     eax, eax
        mov     [edx + LOOP_DISK.Info.Capacity], eax
        mov     [edx + LOOP_DISK.Info.Flags], eax

  .bad_sector_size:
        ret

endp

; Adds the image path to an empty "slot".
; in:       eax - image path.
; out:      eax - error code.
;           ebx - slot number
; destroy:  ecx, edi
proc add_to_slot
        push    eax

        ; We are looking for a mounted file with the same name.
        mov     ebx, loop_slots
  .find_already_use:
        invoke  strncmp [ebx], ecx
        cmp     eax, -1
        jz      .found
        add     ebx, 4
        cmp     ebx, loop_slots.end
        jnz     .find_already_use

        mov     eax, LOOP_ALREADY_MOUNTED_E
        ret

        ; Looking for a free slot
        xor     eax, eax
        mov     edi, loop_slots
        mov     ecx, (loop_slots.end-loop_slots)/4
        repnz   scasd

        mov     eax, LOOP_NO_FREE_SLOT_E
        jnz     .exit

        ; Write a file path pointer to a slot
        pop     eax
        mov     [edi], eax

        mov     ebx, edi
        sub     ebx, loop_slots

  .exit:
        ret

endp


; in eax - file path.
; out: eax- fs error
proc get_image_info
        xor     ebx, ebx
        push    ebx         ; path
        push    ebx         ; path
        push    file_info   ; file info buffer ptr
        push    ebx         ; reserved
        push    ebx         ; flags
        push    ebx         ; reserved
        push    5           ; file info subfunc no

        mov     dword [esp + 21], path
        mov     ebx, esp
        call    [FS_Service]

        add     esp, 28
        ret
endp

proc loop_querymedia stdcall, pdata: dword, mediainfo: dword
        push    ecx edx
        mov     eax, [mediainfo]
        ;mov     edx, [pdata]
        mov     [eax + DISKMEDIAINFO.Flags], 0
        mov     [eax + DISKMEDIAINFO.SectorSize], 512
        mov     ecx, 262017
        mov     dword [eax + DISKMEDIAINFO.Capacity], ecx
        mov     dword [eax + DISKMEDIAINFO.Capacity + 4], 0
        pop     edx ecx
        xor     eax, eax
        ret
endp


proc loop_read stdcall user_data: dword, buffer: dword, startsector: qword, numsectors_ptr:dword

        pushad
        mov     eax, [numsectors_ptr]
        mov     eax, [eax]

       ; DEBUGF  1, "loop_read: buffer = 0x%x, startsector = 0x%x:%x, numsectors = %u\n", [buffer], [startsector], [startsector + 4], eax

        imul    eax, 512
        mov     ebx, dword[startsector]
        imul    ebx, 512

        mov     dword [file_api + 0], 0
        mov     dword [file_api + 4], ebx
        mov     dword [file_api + 8], 0
        mov     dword [file_api + 12], eax
        mov     eax, [buffer]
        mov     dword [file_api + 16], eax
        mov     byte  [file_api + 20], 0
        mov     eax, [user_data]
        mov     [file_api + 21], eax

        mov     ebx, file_api

        call    [FS_Service]

       DEBUGF  1, "FS_Service result EAX=%d EBX=%d\n", eax, ebx


;        mov     eax, [buffer]
;        mov     ebx, 512
;        add     ebx, eax

;     .lp:
;        DEBUGF 1, "%x\n", [eax]
;        add     eax, 4
;        cmp     eax,ebx
;        jnz      .lp

        popad

        xor     eax, eax
        ret
endp

service_name: db 'loop', 0

align 4
loop_callbacks:
    dd  loop_callbacks.end - loop_callbacks
    dd  0   ; no close function
    dd  0   ; no closemedia function
    dd  loop_querymedia
    dd  loop_read
    dd  0   ; no read function
    dd  0   ; no flush function
    dd  0   ; use default cache size
.end:

loop_disks LOOP_DISK LOOP_DISK_MAX
file_info FILE_INFO

include_debug_strings

data fixups
end data

include 'inc/peimport.inc'
