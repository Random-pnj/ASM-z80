; test
; Sauvegardé le 22.11.2026 18:08:57
; Émulateur Z80 — github.com/Random-pnj/ASM-z80

INTERUPT_ROUTINE:
            NOP
            NOP
            IN      a, ($aa)
            OR      a, b00000001
            LD      (char_in), a
            RETI


.org 40
char_in:    DB      00