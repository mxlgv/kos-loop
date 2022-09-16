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

;LOOP_DBG_LVL = 2

include 'inc/proc32.inc'
include 'inc/struct.inc'
include 'inc/macros.inc'
include 'inc/fdo.inc'

section '.flat' readable writable executable


struct  DISKMEDIAINFO
        Flags           dd ?
; Combination of DISK_MEDIA_* bits.
        SectorSize      dd ?
; Size of the sector.
        Capacity        dq ?
; Size of the media in sectors.
ends

proc START c, state, cmdline : dword
        cmp     [state], DRV_ENTRY
        jne     .fail

        invoke  DiskAdd, loop_callbacks, loop_name, test_file, 0
        test    eax, eax
        jz      .disk_add_fail

        push    ecx
        invoke  DiskMediaChanged, eax, 1
        pop     ecx

        invoke  RegService, service_name, service_proc
        ret

  .disk_add_fail:
        DEBUGF  1, "Failed to add disk\n"

  .fail:
        xor     eax, eax
        ret
endp


proc service_proc stdcall, ioctl:dword
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

       ; DEBUGF  1, "FS_Service result EAX=%d EBX=%d\n", eax, ebx


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

my_buff: rb 512
         rd 0

proc loop_querymedia stdcall, pdata: dword, mediainfo: dword
        push    ecx edx
        mov     eax, [mediainfo]
        ;mov     edx, [pdata]
        mov     [eax + DISKMEDIAINFO.Flags], 0
        mov     [eax + DISKMEDIAINFO.SectorSize], 512
        mov     ecx, 2880
        mov     dword [eax + DISKMEDIAINFO.Capacity], ecx
        mov     dword [eax + DISKMEDIAINFO.Capacity + 4], 0
        pop     edx ecx
        xor     eax, eax
        ret
endp

file_api: rd 10

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


loop_name: db 'loop0', 0
test_file: db '/tmp0/1/test.img', 0

include_debug_strings

data fixups
end data

include 'inc/peimport.inc'
