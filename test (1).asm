; test
; Sauvegardé le 22/11/26 13:13
; Émulateur Z80 — Assembleur Complet
;============================================================

INTERUPT_ROUTINE:
            NOP
            NOP
            IN      a, ($aa)
            OR      a, b00000001
            LD      (char_in), a
            RETI


.org 40
char_in:    DB      00