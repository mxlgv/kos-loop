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
__DEBUG_LEVEL__         = 2

include 'inc/proc32.inc'
include 'inc/struct.inc'
include 'inc/macros.inc'
include 'inc/fdo.inc'

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
        xor     eax, eax
        ret
endp


service_name: db 'loop', 0


;include_debug_strings

data fixups
end data

include 'inc/peimport.inc'
