; MakeArray
; Sauvegardé le 22.11.2026 18:10:25
; Émulateur Z80 — github.com/Random-pnj/ASM-z80

MakeArray:                                          ; this is the label indicating the beginning of the routine
            LD      a, 1                            ; A holds the value of the first element
            LD      b, OtherStuff-Numbers           ; B is the number of times we want our loop to execute
            LD      hl, Numbers                     ; HL now holds the address of the first element
ArrayLoop:                                          ; the label marking the beginning of the loop
            LD      (hl), a                         ; storing the current element at its proper place
            INC     hl                              ; increasing HL by 1, so that it points to the next element
            ADD     a, 1                            ; increasing A by 2, giving the value of the next element
            DJNZ    ArrayLoop                       ; the end of the loop; this instruction decreases B, checks
; if it is zero, and jumps to the label given if it isn’t;
; when B is zero, execution continues after DJNZ
            HALT                                    ; returning from the subroutine; explained a bit later
            ORG     $10
Numbers:                                            ; this is the label that identifies our array
            DS      50, $aa                         ; initially the array will be full of zeroes$55
OtherStuff:                                         ; just some kind of other data not used now
            DB      $55                             ; this is the byte that immediately follows our array