; test _ interupte de isolation bit
; Sauvegardé le 22/11/26 14:08
; Émulateur Z80 — Assembleur Complet
;============================================================

;--- Modes PIO ----------------------------------------------------------------
OUTPUT_MODE     EQU     $0F                     ; Mode 0 : 8 bits sortie
INPUT_MODE      EQU     $4F                     ; Mode 1 : 8 bits entrée
BIDIRECTIONAL_MODE  EQU     $8F                 ; Mode 2 : bidirectionnel (Port A seulement)
BIT_CONTROL_MODE    EQU     $CF                 ; Mode 3 : contrôle bit à bit
ENABLE_INTERRUPT    EQU     $83                 ; Active les interruptions PIO
DISABLE_INTERRUPT   EQU     $03                 ; Désactive les interruptions PIO

;--- Divers -------------------------------------------------------------------
CHAR_BUFFER_SIZE    EQU     40                  ; Taille max du buffer de saisie clavier
PIO1_DATA_LCD   EQU     $20                     ; Port A : données LCD
PIO1_INST_LCD   EQU     $21                     ; Port B : contrôle LCD
PIO1_CTRL_DATA  EQU     $22                     ; Registre contrôle Port A
PIO1_CTRL_INST  EQU     $23                     ; Registre contrôle Port B
SETPIO1:
            LD      A, OUTPUT_MODE          ; Charge le mot de contrôle mode sortie ($0F)
            OUT     (PIO1_CTRL_DATA), A     ; Configure Port A en sortie (données vers LCD)
            LD      A, OUTPUT_MODE          ; Même valeur pour Port B
            OUT     (PIO1_CTRL_INST), A     ; Configure Port B en sortie (RS/RW/EN vers LCD)

int:
            LD      b, 8

INTERUPT_ROUTINE:
            NOP
            NOP
            LD      a, (char_in)
            SLA     a
            LD      c, a
            IN      a, ($aa)
            AND     00000001b
            OR      c


            LD      (char_in), a
            OUT     (PIO1_DATA_LCD), A

            DJNZ    INTERUPT_ROUTINE



            LD      (char_in), a
            RETI


.org 40
char_in:    DB      00