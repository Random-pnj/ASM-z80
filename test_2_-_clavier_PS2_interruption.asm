; test 2 - clavier PS2 interruption
; Sauvegardé le 
; Émulateur Z80 — Assembleur Complet
;============================================================

; ===============================================================
;  TEST 2 — Clavier PS/2 via interruption (/INT, IM1 -> $0038)
;  CLK -> /INT du Z80 · DATA -> PIO3 Port B bit 0 ($61)
;  Chaque bit PS/2 declenche une interruption ; le gestionnaire
;  reconstitue l'octet (start + 8 bits + parite + stop), puis
;  traduit le scancode Set 2 en caractere ASCII et l'affiche sur
;  le LCD en mode texte 2x16. Majuscules automatiques via Shift.
;  Supporte : a-z, A-Z, 0-9, espace (meme table que le croquis
;  Arduino ps2_fake_keyboard.ino, inversion Y/Z suisse incluse).
; ===============================================================

;--- PIO 1 : LCD -------------------------------------------------
PIO1_DATA_LCD   EQU $20     ; Port A : donnees LCD
PIO1_INST_LCD   EQU $21     ; Port B : controle LCD
PIO1_CTRL_DATA  EQU $22     ; Registre controle Port A
PIO1_CTRL_INST  EQU $23     ; Registre controle Port B

;--- PIO 3 : clavier PS/2 -----------------------------------------
DATAB_3         EQU $61     ; Port B — bit0 = ligne DATA

;--- Signaux controle LCD -----------------------------------------
RS              EQU %00000001
RW              EQU %00000100
EP              EQU %00001010

;--- Modes PIO ------------------------------------------------------
OUTPUT_MODE     EQU $0F
INPUT_MODE      EQU $4F

;--- Constantes PS/2 -----------------------------------------------
PS2_SC_LSHIFT   EQU $12
PS2_SC_BREAK    EQU $F0


;===============================================================
;  RESET
;===============================================================
            ORG     $0000
            JP      START


;===============================================================
;  GESTIONNAIRE D'INTERRUPTION — vecteur $0038 (IM1)
;  Appele une fois PAR BIT PS/2 recu (CLK -> /INT).
;===============================================================
            .ORG    $38

INTERRUPT:
            EX      AF, AF'
            EXX
            CALL    PS2_ISR
            EX      AF, AF'
            EXX
            EI
            RET


;===============================================================
;  PROGRAMME PRINCIPAL
;===============================================================
START:
            LD      A, OUTPUT_MODE
            OUT     (PIO1_CTRL_DATA), A ; Port A LCD en sortie
            OUT     (PIO1_CTRL_INST), A ; Port B LCD en sortie

            XOR     A
            LD      (PS2_PHASE), A      ; etat machine PS/2 = attente start
            LD      (PS2_BREAKFLAG), A  ; pas de break en cours
            LD      (PS2_SHIFTFLAG), A  ; Shift relache

            LD      BC, 100
            CALL    DELAY               ; stabilisation alimentation LCD
            LD      A, $0E              ; mode texte 2x16 (HD44780)
            OUT     (PIO1_DATA_LCD), A
            CALL    ENABLE
            CALL    ENABLE
            CALL    CLEAR_SCREEN
            LD      HL, MSG_READY
            CALL    PRINT_MESSAGE

            IM      1                   ; IM1 : chaque /INT saute a $0038
            EI                          ; autorise les interruptions

MAIN:
            JP      MAIN                ; tout se passe dans l'interruption


;===============================================================
;  RECEPTION PS/2 BIT PAR BIT
;  PS2_PHASE : 0=attend start, 1=8 bits donnees, 2=parite, 3=stop
;===============================================================
PS2_ISR:
            IN      A, (DATAB_3)        ; lit la ligne DATA (bit0)
            AND     1
            LD      B, A                ; B = bit recu

            LD      A, (PS2_PHASE)
            OR      A
            JP      Z, PS2_P_START
            DEC     A
            JP      Z, PS2_P_DATA
            DEC     A
            JP      Z, PS2_P_PARITY
            JP      PS2_P_STOP

PS2_P_START:
            XOR     A
            LD      (PS2_SHIFT), A
            LD      (PS2_BITNUM), A
            LD      A, 1
            LD      (PS2_PHASE), A
            RET

PS2_P_DATA:
            ; accumulation LSB-first : SHIFT = (SHIFT>>1) | (bit<<7)
            LD      A, (PS2_SHIFT)
            SRL     A
            LD      (PS2_SHIFT), A
            LD      A, B
            OR      A
            JR      Z, PS2_PD_SKIP
            LD      A, (PS2_SHIFT)
            SET     7, A
            LD      (PS2_SHIFT), A
PS2_PD_SKIP:
            LD      A, (PS2_BITNUM)
            INC     A
            LD      (PS2_BITNUM), A
            CP      8
            JR      NZ, PS2_PD_RET
            LD      A, 2
            LD      (PS2_PHASE), A
PS2_PD_RET:
            RET

PS2_P_PARITY:
            ; parite non verifiee dans ce test (demo de reception)
            LD      A, 3
            LD      (PS2_PHASE), A
            RET

PS2_P_STOP:
            XOR     A
            LD      (PS2_PHASE), A      ; pret pour le prochain octet
            LD      A, (PS2_SHIFT)
            CALL    PS2_HANDLE_BYTE
            RET


;===============================================================
;  TRAITEMENT D'UN OCTET PS/2 COMPLET (make/break/shift/affichage)
;===============================================================
PS2_HANDLE_BYTE:
            LD      C, A                ; conserve l'octet
            LD      A, (PS2_BREAKFLAG)
            OR      A
            JR      Z, PS2_HB_NOTBREAK

            ; cet octet est le scancode qu'on relache (apres un $F0)
            XOR     A
            LD      (PS2_BREAKFLAG), A
            LD      A, C
            CP      PS2_SC_LSHIFT
            JR      NZ, PS2_HB_DONE
            XOR     A
            LD      (PS2_SHIFTFLAG), A  ; Shift relache
            JR      PS2_HB_DONE

PS2_HB_NOTBREAK:
            LD      A, C
            CP      PS2_SC_BREAK
            JR      NZ, PS2_HB_MAKE
            LD      A, 1
            LD      (PS2_BREAKFLAG), A  ; prochain octet = relachement
            JR      PS2_HB_DONE

PS2_HB_MAKE:
            LD      A, C
            CP      PS2_SC_LSHIFT
            JR      NZ, PS2_HB_CHAR
            LD      A, 1
            LD      (PS2_SHIFTFLAG), A  ; Shift maintenu
            JR      PS2_HB_DONE

PS2_HB_CHAR:
            CALL    PS2_SC_TO_ASCII     ; C=scancode -> A=caractere (0 si inconnu)
            OR      A
            JR      Z, PS2_HB_DONE
            CALL    PRINT_CHAR          ; affiche le caractere recu sur le LCD

PS2_HB_DONE:
            RET


;===============================================================
;  TABLE SCANCODE SET 2 -> ASCII  (C=scancode -> A=caractere)
;  Majuscule automatique si PS2_SHIFTFLAG actif et lettre a-z.
;===============================================================
PS2_SC_TO_ASCII:
            LD      HL, PS2_TABLE
PS2_SCAN_LOOP:
            LD      A, (HL)
            OR      A
            JR      Z, PS2_SCAN_NOTFOUND
            CP      C
            JR      Z, PS2_SCAN_FOUND
            INC     HL
            INC     HL
            JR      PS2_SCAN_LOOP

PS2_SCAN_FOUND:
            INC     HL
            LD      A, (HL)             ; caractere de base (minuscule/chiffre/espace)
            LD      B, A
            LD      A, (PS2_SHIFTFLAG)
            OR      A
            JR      Z, PS2_SCAN_RET
            LD      A, B
            CP      $61                 ; 'a'
            JR      C, PS2_SCAN_RET     ; < 'a' -> pas une lettre, pas de majuscule
            CP      $7B                 ; 'z'+1
            JR      NC, PS2_SCAN_RET
            SUB     $20                 ; 'a'-'z' -> 'A'-'Z'
            RET
PS2_SCAN_RET:
            LD      A, B
            RET
PS2_SCAN_NOTFOUND:
            XOR     A
            RET

PS2_TABLE:
            DB      $1C,"a", $32,"b", $21,"c", $23,"d", $24,"e", $2B,"f", $34,"g", $33,"h"
            DB      $43,"i", $3B,"j", $42,"k", $4B,"l", $3A,"m", $31,"n", $44,"o", $4D,"p"
            DB      $15,"q", $2D,"r", $1B,"s", $2C,"t", $3C,"u", $2A,"v", $1D,"w", $22,"x"
            DB      $1A,"y", $35,"z"    ; inversion clavier suisse Y/Z
            DB      $45,"0", $16,"1", $1E,"2", $26,"3", $25,"4", $2E,"5", $36,"6", $3D,"7"
            DB      $3E,"8", $46,"9", $29," "
            DB      $00                 ; terminateur


;===============================================================
;  SOUS-ROUTINES LCD (identiques au programme de base)
;===============================================================
PRINT_MESSAGE:
            LD      A, (HL)
            OUT     (PIO1_DATA_LCD), A
            CALL    DATAENABLE
            INC     HL
            LD      A, (HL)
            OR      A
            JP      NZ, PRINT_MESSAGE
            RET

PRINT_CHAR:
            OUT     (PIO1_DATA_LCD), A
            CALL    DATAENABLE
            RET

CLEAR_SCREEN:
            CALL    BFLAG
            LD      A, $01
            OUT     (PIO1_DATA_LCD), A
            CALL    ENABLE
            LD      BC, 100
            CALL    DELAY
            RET

BFLAG:
            EX      AF, AF'
            EXX
            LD      A, INPUT_MODE
            OUT     (PIO1_CTRL_DATA), A
            LD      A, RW
            OUT     (PIO1_INST_LCD), A
            LD      A, RW|EP
            OUT     (PIO1_INST_LCD), A
            LD      A, RW
            OUT     (PIO1_INST_LCD), A
            NOP
            NOP
            NOP
BUSY1:
            IN      A, (PIO1_DATA_LCD)
            BIT     7, A
            JR      NZ, BUSY1
            XOR     A
            OUT     (PIO1_INST_LCD), A
            LD      A, OUTPUT_MODE
            OUT     (PIO1_CTRL_DATA), A
            EX      AF, AF'
            EXX
            RET

ENABLE:
            CALL    BFLAG
            XOR     A
            OUT     (PIO1_INST_LCD), A
            CALL    BFLAG
            LD      A, EP
            OUT     (PIO1_INST_LCD), A
            XOR     A
            OUT     (PIO1_INST_LCD), A
            RET

DATAENABLE:
            LD      A, RS
            OUT     (PIO1_INST_LCD), A
            CALL    BFLAG
            LD      A, RS|EP
            OUT     (PIO1_INST_LCD), A
            LD      A, RS
            OUT     (PIO1_INST_LCD), A
            RET

DELAY:
            PUSH    AF
            PUSH    HL
            LD      DE, -1
LOOP1:
            LD      HL, 172
LOOP2:
            ADD     HL, DE
            JR      C, LOOP2
            DEC     BC
            LD      A, B
            OR      C
            JP      NZ, LOOP1
            POP     HL
            POP     AF
            RET


;===============================================================
;  MESSAGE ET VARIABLES
;===============================================================
MSG_READY:      DB  "PS2 pret - tapez", $00

PS2_PHASE:      DB  $00     ; 0=start,1=data,2=parite,3=stop
PS2_SHIFT:      DB  $00     ; octet en construction
PS2_BITNUM:     DB  $00     ; compteur de bits data (0-7)
PS2_BREAKFLAG:  DB  $00     ; 1 = prochain octet = relachement ($F0 recu)
PS2_SHIFTFLAG:  DB  $00     ; 1 = touche Shift actuellement maintenue
