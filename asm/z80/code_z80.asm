; code z80
; Sauvegardé le 22.11.2026 20:02:21
; Émulateur Z80 — github.com/Random-pnj/ASM-z80

; base optimisé avec annotation
; Sauvegardé le 04/03/26 08:04
; Émulateur Z80 — Assembleur Complet
;============================================================

;===============================================================================
;  Z80 BREADBOARD COMPUTER - random_k200_probable.asm
;  LCD 128x64 | Clavier TRS-80 CoCo2 | 4x PIO Z80
;===============================================================================

;--- PIO 1 : LCD 128x64 -------------------------------------------------------
PIO1_DATA_LCD   EQU     $20                     ; Port A : données LCD
PIO1_INST_LCD   EQU     $21                     ; Port B : contrôle LCD
PIO1_CTRL_DATA  EQU     $22                     ; Registre contrôle Port A
PIO1_CTRL_INST  EQU     $23                     ; Registre contrôle Port B

;--- PIO 2 : Clavier ----------------------------------------------------------
DATAA           EQU     $40                     ; Port A : scan lignes (sortie)
DATAB           EQU     $41                     ; Port B : lecture colonnes (entrée)
CTRLA           EQU     $42                     ; Registre contrôle Port A
CTRLB           EQU     $43                     ; Registre contrôle Port B

;--- PIO 3 : Réserve ----------------------------------------------------------
DATAA_3         EQU     $60
DATAB_3         EQU     $61
CTRLA_3         EQU     $62
CTRLB_3         EQU     $63

;--- PIO 4 : Interruptions ----------------------------------------------------
DATAA_4         EQU     $80
DATAB_4         EQU     $81
CTRLA_4         EQU     $82
CTRLB_4         EQU     $83

;--- Modes LCD ----------------------------------------------------------------
GRAPH_MODE      EQU     $3E                     ; Commande init LCD mode graphique 128x64
TEXT_MODE       EQU     $0E                     ; Commande init LCD mode texte 2x16

;--- Signaux contrôle LCD (câblés sur Port B PIO1) ----------------------------
RS              EQU     %00000001               ; Register Select : 0=commande / 1=donnée
RW              EQU     %00000100               ; Read/Write      : 0=écriture / 1=lecture
EP              EQU     %00001010               ; Enable          : front montant valide le bus

;--- Modes PIO ----------------------------------------------------------------
OUTPUT_MODE     EQU     $0F                     ; Mode 0 : 8 bits sortie
INPUT_MODE      EQU     $4F                     ; Mode 1 : 8 bits entrée
BIDIRECTIONAL_MODE  EQU     $8F                 ; Mode 2 : bidirectionnel (Port A seulement)
BIT_CONTROL_MODE    EQU     $CF                 ; Mode 3 : contrôle bit à bit
ENABLE_INTERRUPT    EQU     $83                 ; Active les interruptions PIO
DISABLE_INTERRUPT   EQU     $03                 ; Désactive les interruptions PIO

;--- Divers -------------------------------------------------------------------
CHAR_BUFFER_SIZE    EQU     40                  ; Taille max du buffer de saisie clavier


;===============================================================================
;  RESET — vecteur $0000
;===============================================================================

            JP      RAM_CLEAN               ; Au reset, saute vers l'initialisation


;===============================================================================
;  INITIALISATION
;===============================================================================

; Remise à zéro de la RAM de travail ($10 dans chaque octet)
RAM_CLEAN:
            LD      HL, DEBUT_RAM           ; HL pointe sur le début de la RAM
            LD      A, $10                  ; Valeur de remplissage
RAM_CLEAN1:
            LD      (HL), A                 ; Écrit $10 dans l'octet courant
            INC     HL                      ; Passe à l'octet suivant
            DJNZ    RAM_CLEAN1              ; Répète B fois (B=256 au départ)

; Copie les valeurs initiales (INIT_REG) vers la RAM de travail (DEBUT_RAM)
INISIALISATION_WORKSPACE:
            LD      HL, INIT_REG            ; HL = source (table en ROM)
            LD      DE, DEBUT_RAM           ; DE = destination (RAM)
            LD      BC, INIT_REG_END-INIT_REG  ; BC = nombre d'octets à copier
            LDIR                            ; Copie BC octets de HL vers DE (auto-incrémente)

; Active le mode interruption 1 (vecteur fixe $0038)
INITIALISATION_INTERUPT:
            IM      1                       ; Mode IRQ 1 : saut automatique vers $0038
            EI                              ; Autorise les interruptions masquables
            JP      INISIALISATION_PERIFERIQUE  ; Continue l'init


;===============================================================================
;  GESTIONNAIRE D'INTERRUPTION — vecteur $0038 (IRQ mode 1)
;===============================================================================

.ORG    $38                 ; Le Z80 saute ici sur chaque IRQ

INTERRUPT:
            EX      AF, AF'             ; Sauvegarde A et flags dans le banc alternatif
            EXX                             ; Sauvegarde BC, DE, HL dans les registres alternatifs
            CALL    INTERUPT_ROUTINE        ; Appelle le traitement IRQ
            EX      AF, AF'             ; Restaure A et flags
            EXX                             ; Restaure BC, DE, HL
            EI                              ; Réarme le flip-flop IRQ (désactivé à l'entrée)
            RET                             ; Retour d'interruption

; Traitement IRQ : incrémente COUNTER et l'affiche en décimal sur LCD
INTERUPT_ROUTINE:
            LD      HL, (COUNTER)           ; Charge le compteur 16 bits depuis la RAM
            INC     HL                      ; Incrémente de 1
            LD      (COUNTER), HL           ; Sauvegarde le nouveau compteur en RAM
            CALL    CLEAR_SCREEN            ; Efface l'écran LCD
            LD      HL, DECIMAL_OUT_BUFFER  ; HL = adresse du buffer de sortie décimal
            LD      DE, (COUNTER)           ; DE = valeur à convertir
            CALL    BIN_TO_DEC              ; Convertit DE en chaîne ASCII décimale dans le buffer
            LD      HL, DECIMAL_OUT_BUFFER+1  ; Saute le premier octet (longueur) pour pointer sur les chiffres
            CALL    PRINT_MESSAGE           ; Affiche la chaîne sur le LCD
            LD      BC, 100                 ; Valeur de délai = 100 ms
            CALL    DELAY                   ; Pause pour stabilité affichage
            RETI                            ; Retour IRQ et réarme IFF1


;===============================================================================
;  VECTEUR NMI — $0066 (interruption non masquable)
;===============================================================================

.ORG    $66                 ; Le Z80 saute ici sur un NMI

NMI:
            JP      NMI_INSTRUCTION         ; Saut vers le handler NMI

; Handler NMI : envoie $AA sur le LCD (signal de diagnostic)
NMI_INSTRUCTION:
            LD      A, $AA                  ; Valeur test ($AA = 10101010b, facile à voir sur LED)
            OUT     (PIO1_DATA_LCD), A      ; Envoie sur le port données LCD
            EI                              ; Réarme les interruptions
            RET                             ; Retour NMI


;===============================================================================
;  TABLE VALEURS INITIALES RAM (copiée vers $0900 au démarrage par LDIR)
;===============================================================================

INIT_REG:
            DB      $AA                     ; WRKSPC        : marqueur de RAM initialisée
            DB      $00                     ; KEYBOARD_PTR  : pointeur position clavier
            DB      $00                     ; CARRIAGE_RET  : octet retour chariot
            DB      $00, $80                ; LCD_AC_X      : adresse X curseur graphique (poids faible, poids fort)
            DB      $00, $80                ; LCD_AC_Y      : adresse Y curseur graphique
            DB      $00, $00                ; POS_X         : position X texte
            DB      $00, $08                ; POS_Y         : position Y texte
            DB      $00, $08                ; MEM_POINTER   : pointeur pour PRINT_MEM
            DB      $00                     ; ROW           : ligne courante
            DB      $08                     ; COLUMN        : colonne courante
            DB      $AA                     ; PIO_TEST      : octet tournant pour diagnostic
            DB      GRAPH_MODE              ; DISPLAY_MODE  : mode actif ($0E=texte / $3E=graphique)
            DB      $00, $00                ; COUNTER       : compteur IRQ 16 bits
            DB      $00, $00                ; COUNTER_2     : compteur secondaire
            DB      $00, $00                ; BUFPTR        : pointeur courant dans buffer BIN>DEC
            DB      $00                     ; CURLEN        : longueur courante du buffer BIN>DEC
            DB      $00                     ; NGFLAG        : signe du nombre (0=positif, <>0=négatif)
            DB      0, 0, 0, 0, 0, 0, 0, 0  ; DECIMAL_OUT_BUFFER : buffer sortie décimale (8 octets)
            DB      $00, $00                ; DISPLAY       : compteur de passes affichage graphique
            DB      $00, $00                ; KEY_BUFFER    : dernière touche lue
            DB      "12345", $00            ; MEM_BUFFER    : buffer mémoire de test (chaîne + terminateur)
            DB      $00, $00                ; BIT_BUFFER    : buffer de bits divers
            DB      $00                     ; CURSEUR_ADR   : adresse curseur texte LCD (0 à $40)
            DB      $00                     ; CHAR_POS      : index courant dans CHAR_BUFFER (0 à 39)
INIT_REG_END:


;===============================================================================
;  INITIALISATION DES PÉRIPHÉRIQUES
;===============================================================================

INISIALISATION_PERIFERIQUE:
            CALL    SETPIO1                 ; Configure PIO1 pour le LCD
            CALL    SETPIO2                 ; Configure PIO2 pour le clavier
            JP      INISIALISATION_ECRAN_LCD_GRAPH  ; Lance l'init LCD graphique

; PIO1 : Port A et B en sortie (données LCD + signaux contrôle)
SETPIO1:
            LD      A, OUTPUT_MODE          ; Charge le mot de contrôle mode sortie ($0F)
            OUT     (PIO1_CTRL_DATA), A     ; Configure Port A en sortie (données vers LCD)
            LD      A, OUTPUT_MODE          ; Même valeur pour Port B
            OUT     (PIO1_CTRL_INST), A     ; Configure Port B en sortie (RS/RW/EN vers LCD)
            RET

; PIO2 : Port A en sortie (active les lignes clavier), Port B en entrée (lit les colonnes)
SETPIO2:
            LD      A, OUTPUT_MODE          ; Mode sortie pour Port A
            OUT     (CTRLA), A              ; Port A = sortie : envoie les masques de scan
            LD      A, INPUT_MODE           ; Mode entrée pour Port B
            OUT     (CTRLB), A              ; Port B = entrée : reçoit l'état des colonnes
            RET

; PIO3 : même config que PIO2 (port de réserve, non utilisé)
SETPIO3:
            LD      A, OUTPUT_MODE
            OUT     (CTRLA_3), A
            LD      A, INPUT_MODE
            OUT     (CTRLB_3), A
            RET

; Diagnostic : fait tourner un bit sur PIO1 (visible sur LED ou oscilloscope)
TEST_PIO:
            LD      A, (PIO_TEST)           ; Charge la valeur courante du registre de test
            RLC     A                       ; Rotation à gauche : le bit tourne de D0 à D7
            LD      (PIO_TEST), A           ; Sauvegarde la nouvelle valeur
            OUT     (PIO1_DATA_LCD), A      ; Envoie sur Port A (données)
            OUT     (PIO1_INST_LCD), A      ; Envoie sur Port B (contrôle)
            RET


;===============================================================================
;  BOUCLE PRINCIPALE
;===============================================================================

PROGRAMME:
            NOP                             ; Pas d'opération (point d'entrée propre)
            NOP
            NOP
; Tombe dans KEYIN pour lire le clavier


;===============================================================================
;  CLAVIER MATRICIEL TRS-80 / CoCo2  (matrice 8 lignes x 8 colonnes)
;===============================================================================

; Lit une touche et exécute l'action correspondante
; HL = table de caractères active (KEY_MAP ou KEY_MAP_UPPER)
KEYIN:
            LD      HL, KEY_MAP             ; Charge l'adresse de la table minuscules par défaut

KEY_IN:
            LD      BC, 175                 ; Durée anti-rebond = 175 ms
            CALL    DELAY                   ; Attend la fin du rebond mécanique

            LD      E, 00000001b            ; Masque de scan : bit 0 = ligne 0 active
            LD      C, DATAB                ; C = adresse Port B pour l'instruction IN (C)
            LD      D, 0                    ; D = compteur de ligne (index X)
            LD      B, 0                    ; B = stockera la valeur lue sur Port B

; Boucle de scan : active une ligne, lit les colonnes, recommence si rien
KEY_KEY:
            LD      A, E                    ; Charge le masque de ligne courant
            OUT     DATAA, A                ; Envoie le masque sur Port A → active la ligne
            RLC     E                       ; Décale le masque d'un bit vers la gauche (ligne suivante)
            IN      A, (C)                  ; Lit Port B : 0 = colonne inactive, 1 = touche pressée
            LD      B, A                    ; Sauvegarde l'état des colonnes dans B
            ADD     A, 0                    ; Met à jour les flags sans modifier A
            JR      Z, KEY_KEY              ; Si A=0 (aucune touche) → continue le scan

; Calcul de l'index de colonne dans D (D = numéro_ligne × 8)
            XOR     A                       ; A = 0, efface aussi les flags
            LD      C, A                    ; C = 0 (compteur de colonne)
X_COUNT:
            INC     D                       ; Incrémente l'index de ligne
            RRC     E                       ; Rotation droite sur E pour retrouver le bit de ligne actif
            JR      NC, X_COUNT             ; Continue tant que le bit carry n'est pas sorti (bit actif)
            DEC     D                       ; Ajuste (on a incrémenté une fois de trop)
            RLC     D                       ; Décale D de 3 bits à gauche = multiplie par 8
            RLC     D
            RLC     D                       ; D = numéro_ligne × 8 = offset dans la table

; Calcul de l'index de colonne dans C
Y_COUNT:
            INC     C                       ; Incrémente l'index de colonne
            RRC     B                       ; Rotation droite sur B (état colonnes)
            JR      NC, Y_COUNT             ; Continue tant que le bit actif n'est pas trouvé
            DEC     C                       ; Ajuste (un de trop)

; Lecture du caractère dans la table à l'index (D + C)
            ADD     A, D                    ; A = offset ligne
            ADD     A, C                    ; A = offset ligne + colonne = index dans la table
            ADD     A, L                    ; A = index + base basse de HL (table)
            LD      L, A                    ; Met à jour L → HL pointe sur le caractère
            LD      A, (HL)                 ; Charge le caractère de la table en A

; Test des touches spéciales (flèches de navigation)
            CP      $F1                     ; Est-ce la flèche HAUT ?
            JP      Z, UP                   ; Oui → gère le déplacement vers le haut
            CP      $F2                     ; Est-ce la flèche BAS ?
            JP      Z, DOWN
            CP      $F3                     ; Est-ce la flèche GAUCHE ?
            JP      Z, LEFT
            CP      $F4                     ; Est-ce la flèche DROITE ?
            JP      Z, RIGHT

            JP      SANS_NOMBRE             ; Pas une flèche → teste les autres touches

; Raccourcis numériques (touches 1-9 lancent des programmes)
            CP      "1"                     ; Touche "1" → mode texte LCD
            JP      Z, INISIALISATION_ECRAN_LCD_TEXT
            CP      "2"                     ; Touche "2" → mode graphique LCD
            JP      Z, INISIALISATION_ECRAN_LCD_GRAPH
            CP      "3"
            JP      Z, PROG_3
            CP      "4"
            JP      Z, PROG_4
            CP      "5"
            JP      Z, PROG_5
            CP      "6"
            JP      Z, PROG_6
            CP      "7"
            JP      Z, PROG_7
            CP      "8"
            JP      Z, PROG_8
            CP      "9"
            JP      Z, PROG_9

SANS_NOMBRE:
            CP      $0D                     ; Touche Entrée (CR) ?
            JP      Z, ENTER_PRESSED
            CP      $1B                     ; Touche Escape ?
            JP      Z, CLEAR_PRESSED
            CP      $08                     ; Touche Backspace ?
            JP      Z, BREAK_PRESSED
            CP      $0F                     ; Touche Shift ?
            JP      Z, SHIFT_PRESSED

; Caractère ordinaire → stocke dans CHAR_BUFFER et affiche sur LCD
            EX      AF, AF'             ; Sauvegarde A (le caractère) dans le banc alternatif
            LD      HL, CHAR_POS            ; HL pointe sur la variable de position dans le buffer
            LD      A, (HL)                 ; Charge la position courante
            CP      CHAR_BUFFER_SIZE        ; La position atteint-elle la limite (40) ?
            JP      Z, PROGRAMME            ; Oui → buffer plein, ignore le caractère
            INC     (HL)                    ; Incrémente la position dans le buffer
            LD      HL, CHAR_BUFFER         ; HL = adresse de base du buffer
            ADD     A, L                    ; A = offset dans le buffer
            LD      L, A                    ; HL pointe sur la case courante du buffer
            EX      AF, AF'             ; Restaure A (le caractère)
            LD      (HL), A                 ; Stocke le caractère dans le buffer
            CALL    PRINT_CHAR              ; Affiche le caractère sur le LCD
            LD      HL, KEY_MAP             ; Recharge la table minuscules (reset après Shift)
            JP      PROGRAMME               ; Retour à la boucle principale


;===============================================================================
;  MINI-CALCULATRICE (ENTER) — syntaxe : "N + M" ou "N - M"  (chiffres simples)
;===============================================================================

ENTER_PRESSED:
NUMBER:
            LD      HL, CHAR_BUFFER         ; HL pointe sur le début du buffer de saisie
            LD      A, (HL)                 ; Charge le premier caractère

IS_NUMBER:
            CP      " "                     ; Est-ce un espace ?
            JP      Z, NEXT_CHAR            ; Oui → l'ignore et passe au suivant
            CP      $40                     ; Est-ce '@' ou plus (caractère invalide) ?
            JP      Z, ABORD                ; Oui → abandonne l'analyse
            CP      "0"                     ; Est-ce inférieur à '0' ?
            JP      C, ABORD                ; Oui → pas un chiffre, abandonne
            SUB     $30                     ; Soustrait $30 : convertit ASCII '0'-'9' en valeur 0-9
            LD      B, A                    ; Sauvegarde le premier opérande dans B

NEXT_CHAR1:
            INC     HL                      ; Passe au caractère suivant dans le buffer
            LD      A, (HL)                 ; Charge ce caractère
            CP      " "                     ; Est-ce un espace ?
            CALL    Z, NEXT_CHAR1           ; Oui → saute les espaces (appel récursif)
            CP      "+"                     ; Est-ce un '+' ?
            JP      Z, ADDITION             ; Oui → va effectuer l'addition
            CP      "-"                     ; Est-ce un '-' ?
            JP      Z, SOUSTRCTION          ; Oui → va effectuer la soustraction
            INC     HL                      ; Passe au caractère suivant
            JP      IS_NUMBER               ; Recommence l'analyse

; Addition : calcule B + C et affiche le résultat
ADDITION:
            INC     HL                      ; Passe après le '+'
            LD      A, (HL)                 ; Charge le caractère suivant
            CP      " "                     ; Espace ?
            JP      Z, ADDITION             ; Oui → saute les espaces
            CP      $40                     ; Caractère invalide ?
            JP      Z, ABORD
            CP      "0"                     ; Inférieur à '0' ?
            JP      C, ABORD
            SUB     $30                     ; Convertit ASCII → valeur
            LD      C, A                    ; C = deuxième opérande
            LD      A, B                    ; A = premier opérande
            ADD     A, C                    ; A = B + C
            ADD     A, $30                  ; Reconvertit en ASCII
            PUSH    AF                      ; Sauvegarde le résultat
            CALL    CLEAR_SCREEN            ; Efface l'écran avant d'afficher
            POP     AF                      ; Restaure le résultat
            CALL    PRINT_CHAR              ; Affiche le caractère résultat sur LCD
            JP      PROGRAMME

; Soustraction : calcule B - C et affiche le résultat
SOUSTRCTION:
            INC     HL                      ; Passe après le '-'
            LD      A, (HL)
            CP      " "
            JP      Z, SOUSTRCTION          ; Saute les espaces
            CP      $40
            JP      Z, ABORD
            CP      "0"
            JP      C, ABORD
            SUB     $30                     ; Convertit ASCII → valeur
            LD      C, A                    ; C = deuxième opérande
            LD      A, B                    ; A = premier opérande
            SUB     C                       ; A = B - C
            ADD     A, $30                  ; Reconvertit en ASCII
            PUSH    AF
            CALL    CLEAR_SCREEN
            POP     AF
            CALL    PRINT_CHAR
            JP      PROGRAMME

NEXT_CHAR:
            INC     HL                      ; Avance d'un caractère dans le buffer
            JP      IS_NUMBER               ; Recommence l'analyse

ABORD:
            RET                             ; Fin de l'analyse sans résultat


;===============================================================================
;  HANDLERS TOUCHES SPÉCIALES
;===============================================================================

; ESCAPE : efface l'écran et retourne au programme
CLEAR_PRESSED:
            CALL    CLEAR_SCREEN            ; Efface le LCD et vide le buffer
            JP      PROGRAMME

; BACKSPACE : affiche le contenu mémoire au pointeur MEM_POINTER
BREAK_PRESSED:
            CALL    PRINT_MEM               ; Lance l'affichage hexadécimal mémoire
            JP      PROGRAMME

; SHIFT : bascule sur la table des majuscules et symboles
SHIFT_PRESSED:
            LD      HL, KEY_MAP_UPPER       ; Charge l'adresse de la table majuscules
            JP      KEY_IN                  ; Repart en lecture clavier avec la nouvelle table

; Flèche HAUT : avance MEM_POINTER de 8 octets (affichage mémoire suivant)
UP:
            LD      HL, (MEM_POINTER)       ; Charge le pointeur mémoire courant
            LD      DE, $08                 ; Déplacement = 8 octets
            ADD     HL, DE                  ; Avance HL de 8
            LD      (MEM_POINTER), HL       ; Sauvegarde le nouveau pointeur
            RET

; Flèche BAS : recule MEM_POINTER de 8 octets
DOWN:
            LD      HL, (MEM_POINTER)
            LD      DE, $08
            SBC     HL, DE                  ; Recule HL de 8 (soustraction 16 bits)
            LD      (MEM_POINTER), HL
            RET

; Flèche GAUCHE : décrémente la position X du curseur texte
LEFT:
            LD      HL, POS_X               ; HL pointe sur la variable POS_X
            DEC     (HL)                    ; Décrémente la valeur en mémoire
            CALL    CURSOR_LCD              ; Met à jour la position curseur sur LCD
            RET

; Flèche DROITE : incrémente la position X du curseur texte
RIGHT:
            LD      HL, POS_X
            INC     (HL)
            CALL    CURSOR_LCD
            RET


;===============================================================================
;  PROGRAMMES NUMÉROTÉS (touches 1-9)
;===============================================================================

; PROG 1/2/3 : balayage vertical qui efface l'écran graphique ligne par ligne
PROG_1:
PROG_2:
PROG_3:
            LD      A, $80                  ; $80 = adresse Y départ (ligne 0 demi-page haute)
            LD      (LCD_AC_Y), A           ; Initialise le registre Y
            LD      A, $80                  ; $80 = adresse X départ (demi-page haute)
            LD      (LCD_AC_X), A           ; Initialise le registre X
            XOR     A                       ; A = 0
            LD      HL, DISPLAY             ; HL pointe sur le compteur de passes
            LD      (HL), A                 ; Remet le compteur à 0

GRAPHIQUE_MODE11:
            CALL    SET_ADRESSE             ; Envoie les coordonnées X et Y au LCD
            CALL    LIGNE1                  ; Envoie 16 octets nuls (efface la ligne)
            PUSH    HL                      ; Sauvegarde HL (pointeur données)
            LD      HL, LCD_AC_Y            ; HL pointe sur le registre Y
            INC     (HL)                    ; Passe à la ligne suivante (Y+1)
            LD      A, (LCD_AC_Y)           ; Recharge Y pour le comparer
            CP      $80+32                  ; A-t-on atteint la ligne 32 (fin demi-page) ?
            POP     HL                      ; Restaure HL
            LD      BC, 1                   ; Délai = 1 ms
            CALL    DELAY
            JP      NZ, GRAPHIQUE_MODE11    ; Non → continue la boucle

SUITE1:
            LD      A, $80                  ; Remet Y à 0 (ligne 0)
            LD      (LCD_AC_Y), A
            LD      A, $88                  ; $88 = adresse X demi-page basse
            LD      (LCD_AC_X), A           ; Passe à la demi-page basse de l'écran
            PUSH    HL
            LD      HL, DISPLAY             ; HL pointe sur le compteur de passes
            INC     (HL)                    ; Incrémente le compteur
            LD      A, (HL)                 ; Charge la valeur
            CP      2                       ; A-t-on fait 2 passes (haut + bas) ?
            POP     HL
            JP      NZ, GRAPHIQUE_MODE11    ; Non → refait une passe sur la demi-page basse
            JP      PROGRAMME

; Envoie 16 octets nuls sur la ligne graphique courante (efface une ligne)
LIGNE1:
            LD      B, 16                   ; Compteur = 16 octets par ligne graphique
            XOR     A                       ; A = 0 (octet d'effacement)
            OUT     (PIO1_DATA_LCD), A      ; Envoie l'octet nul sur le bus données
            INC     HL                      ; Avance HL (même si non utilisé ici, pour la cohérence)
            CALL    DATAENABLE              ; Génère l'impulsion Enable avec RS=1 (données)
            DJNZ    LIGNE1+2                ; Décrémente B, recommence si B≠0 (saute les 2 premières instr.)
            RET

; PROG 4 : affiche le sprite 8x1 octets
PROG_4:
            CALL    PRINT_SPRITE            ; Lance l'affichage du sprite
            JP      PROGRAMME

PROG_5:
PROG_6:
PROG_7:
PROG_8:
PROG_9:
            JP      PROGRAMME               ; Réservés pour extensions futures


;===============================================================================
;  INITIALISATION LCD
;===============================================================================

MESSAGE:    DB      "Random K2000", $00     ; Message d'accueil (mode texte)
ENTER_PRESSED_MESSAGE: DB      "Enter pressed", $00
BREAK_PRESSED_MESSAGE: DB      "Break pressed", $00
PRINT_MEM_MESSAGE: DB      "ADRESSE:  $", $00  ; En-tête affichage mémoire

; Init LCD en mode texte 2x16 caractères
INISIALISATION_ECRAN_LCD_TEXT:
            LD      BC, 100                 ; Attente 100 ms pour stabilisation alimentation LCD
            CALL    DELAY
            LD      A, TEXT_MODE            ; Charge la commande d'init mode texte ($0E)
            OUT     (PIO1_DATA_LCD), A      ; Envoie la commande sur le bus données
            CALL    ENABLE                  ; 1ère impulsion Enable (LCD nécessite 2 fois)
            CALL    ENABLE                  ; 2ème impulsion Enable
            CALL    CLEAR_SCREEN            ; Efface l'écran
            LD      BC, 10
            CALL    DELAY                   ; Petite pause après effacement
            LD      HL, MESSAGE             ; HL pointe sur le message d'accueil
            CALL    PRINT_MESSAGE           ; Affiche "Random K2000"
            JP      PROGRAMME

; Init LCD en mode graphique 128x64
INISIALISATION_ECRAN_LCD_GRAPH:
            LD      BC, 100
            CALL    DELAY
            LD      A, GRAPH_MODE           ; Charge la commande d'init mode graphique ($3E)
            OUT     (PIO1_DATA_LCD), A
            CALL    ENABLE
            CALL    ENABLE
            JP      GRAPHIQUE_MODE          ; Lance directement l'affichage du bitmap


;===============================================================================
;  AFFICHAGE GRAPHIQUE 128x64
;===============================================================================

; Affiche BITMAP1 sur l'écran complet
; Organisation : 2 demi-pages (X=$80 haut, X=$88 bas) × 32 lignes × 16 octets
GRAPHIQUE_MODE:
            LD      A, $80                  ; Y de départ = ligne 0
            LD      (LCD_AC_Y), A
            LD      A, $80                  ; X = demi-page haute
            LD      (LCD_AC_X), A
            XOR     A                       ; A = 0
            LD      HL, DISPLAY             ; HL → compteur de passes
            LD      (HL), A                 ; Remet à 0 (commence par la demi-page haute)
            LD      HL, BITMAP1             ; HL pointe sur les données du bitmap en ROM

GRAPHIQUE_MODE1:
            CALL    SET_ADRESSE             ; Positionne le curseur graphique (Y puis X)
            CALL    LIGNE                   ; Envoie 16 octets du bitmap vers le LCD
            PUSH    HL                      ; Sauvegarde HL (avancé de 16 par LIGNE)
            LD      HL, LCD_AC_Y            ; HL pointe sur le registre Y
            INC     (HL)                    ; Passe à la ligne suivante
            LD      A, (LCD_AC_Y)
            CP      $80+32                  ; Fin de la demi-page (32 lignes) ?
            POP     HL
            LD      BC, 1
            CALL    DELAY
            JP      NZ, GRAPHIQUE_MODE1     ; Non → ligne suivante

SUITE:
            LD      A, $80                  ; Retour ligne 0
            LD      (LCD_AC_Y), A
            LD      A, $88                  ; Passe à la demi-page basse (X=$88)
            LD      (LCD_AC_X), A
            PUSH    HL
            LD      HL, DISPLAY
            INC     (HL)                    ; Incrémente le compteur de passes
            LD      A, (HL)
            CP      2                       ; 2 passes effectuées = bitmap complet affiché ?
            POP     HL
            JP      NZ, GRAPHIQUE_MODE1     ; Non → affiche la demi-page basse
            JP      PROGRAMME

; Envoie 16 octets depuis (HL) vers le LCD (une ligne graphique = 128 pixels / 8 = 16 octets)
LIGNE:
            LD      B, 16                   ; 16 octets par ligne graphique
            LD      A, (HL)                 ; Charge l'octet depuis le bitmap en ROM
            OUT     (PIO1_DATA_LCD), A      ; Envoie l'octet sur le bus données LCD
            INC     HL                      ; Avance le pointeur vers l'octet suivant
            CALL    DATAENABLE              ; Valide l'octet avec impulsion Enable (RS=1)
            DJNZ    LIGNE+2                 ; Décrémente B, recommence en sautant LD B,16
            RET

; Envoie les coordonnées X et Y au contrôleur LCD graphique KS0108
SET_ADRESSE:
            LD      A, (LCD_AC_Y)           ; Charge l'adresse Y ($80-$9F = lignes 0-31)
            OUT     (PIO1_DATA_LCD), A      ; Envoie Y sur le bus
            CALL    ENABLE                  ; Valide avec Enable (RS=0 = commande)
            LD      A, (LCD_AC_X)           ; Charge l'adresse X ($80=haut / $88=bas)
            OUT     (PIO1_DATA_LCD), A      ; Envoie X sur le bus
            CALL    ENABLE                  ; Valide avec Enable
            RET

; Affiche le sprite SPRITE (8 octets) à la position LCD_AC_Y=$80, X=$81
PRINT_SPRITE:
            LD      A, $80                  ; Y de départ = ligne 0
            LD      (LCD_AC_Y), A
            LD      A, $81                  ; X de départ = page 1
            LD      (LCD_AC_X), A
            LD      HL, SPRITE              ; HL pointe sur les données du sprite
            LD      B, 8                    ; 8 octets = 8 lignes du sprite

PRINT_SPRITE1:
            CALL    SET_ADRESSE             ; Positionne le curseur sur la ligne courante
            LD      DE, HL                  ; Sauvegarde HL dans DE
            INC     DE                      ; DE pointe sur l'octet suivant du sprite
            LD      A, (HL)                 ; Charge l'octet courant du sprite
            OUT     (PIO1_DATA_LCD), A      ; Envoie l'octet sur le LCD
            CALL    DATAENABLE              ; Valide avec Enable en mode donnée
            LD      HL, LCD_AC_Y            ; HL pointe sur le registre Y
            INC     (HL)                    ; Passe à la ligne suivante (Y+1)
            LD      HL, (LCD_AC_Y)          ; Recharge Y dans HL (pour vérification éventuelle)
            EX      DE, HL                  ; Restaure HL = pointeur sprite (DE → HL)
            DJNZ    PRINT_SPRITE1           ; Recommence pour les 8 octets
            RET


;===============================================================================
;  SOUS-ROUTINES LCD
;===============================================================================

; Affiche une chaîne de caractères terminée par $00
PRINT_MESSAGE:
            LD      A, (HL)                 ; Charge le caractère courant depuis la chaîne
            CALL    BFLAG                   ; Attend que le LCD soit prêt (Busy Flag = 0)
            OUT     (PIO1_DATA_LCD), A      ; Envoie le caractère sur le bus données
            CALL    DATAENABLE              ; Génère l'impulsion Enable avec RS=1 (données)
            INC     HL                      ; Avance au caractère suivant
            LD      A, (HL)                 ; Pré-charge pour tester le terminateur
            OR      A                       ; Met à jour le flag Z (Z=1 si A=0)
            JP      NZ, PRINT_MESSAGE       ; Si pas terminateur → continue
            RET

; Affiche le caractère ASCII contenu dans A
PRINT_CHAR:
            OUT     (PIO1_DATA_LCD), A      ; Envoie le caractère sur le bus données LCD
            CALL    DATAENABLE              ; Génère l'impulsion Enable (RS=1)
            RET

; Affiche un espace (commodité)
SPACE:
            LD      A, " "                  ; Code ASCII espace = $20
            CALL    PRINT_CHAR
            RET

; Envoie une commande (instruction) au LCD — RS=0, impulsion Enable
LCD_INST:
            OUT     (PIO1_DATA_LCD), A      ; Envoie la commande sur le bus
            CALL    BFLAG                   ; Attend que le LCD soit prêt
            CALL    ENABLE                  ; Génère l'impulsion Enable (RS=0 = commande)
            RET

; Efface l'écran LCD, remet CHAR_POS à 0 et vide le CHAR_BUFFER
CLEAR_SCREEN:
            CALL    BFLAG                   ; Attend que le LCD soit libre
            LD      A, $01                  ; Commande HD44780 "Clear Display"
            OUT     (PIO1_DATA_LCD), A      ; Envoie la commande
            CALL    ENABLE                  ; Impulsion Enable pour exécuter la commande
            LD      BC, 100                 ; Clear Display est lente (~1.5 ms) → attend 100 ms
            CALL    DELAY
            LD      HL, CHAR_POS            ; HL pointe sur la variable de position clavier
            XOR     A                       ; A = 0
            LD      (HL), A                 ; Remet la position à 0
            CALL    CHAR_BUFFER_CLS         ; Efface les 40 octets du buffer de saisie
            RET

; Remplit CHAR_BUFFER de 40 octets à 0 (efface la saisie en cours)
CHAR_BUFFER_CLS:
            XOR     A                       ; A = 0 (valeur d'effacement)
            LD      B, CHAR_BUFFER_SIZE     ; B = 40 (nombre d'octets à effacer)
            LD      HL, CHAR_BUFFER         ; HL pointe sur le début du buffer
CHAR_BUFFER_CLS1:
            LD      (HL), A                 ; Écrit 0 dans l'octet courant
            INC     HL                      ; Passe à l'octet suivant
            DJNZ    CHAR_BUFFER_CLS1        ; Répète 40 fois
            RET

; Retour curseur en position 0 sans effacer le contenu (Home)
RET_HOME:
            CALL    BFLAG                   ; Attend que le LCD soit libre
            LD      A, $02                  ; Commande HD44780 "Return Home"
            OUT     (PIO1_DATA_LCD), A
            CALL    ENABLE
            LD      BC, 1                   ; Délai minimal
            CALL    DELAY
            RET

; Positionne le curseur texte à l'adresse (CURSEUR_ADR) — limite = $40 (2×20 maxi)
CURSOR_LCD:
            CALL    BFLAG
            LD      C, $80                  ; Commande HD44780 "Set DDRAM Address" = $80 + offset
            LD      A, (CURSEUR_ADR)        ; Charge l'offset curseur (0 à $40)
            CP      $41                     ; L'offset dépasse la fin de l'écran ?
            JR      NC, TESTFAILED          ; Oui (A > $40) → remet à 0
            JR      Z, TESTFAILED           ; Oui (A = $41) → remet à 0
CURS:
            ADD     A, C                    ; Calcule $80 + offset = adresse DDRAM
            OUT     (PIO1_DATA_LCD), A      ; Envoie la commande Set DDRAM Address
            CALL    ENABLE                  ; Valide la commande
            LD      BC, 1
            CALL    DELAY
            RET
TESTFAILED:
            XOR     A                       ; Remet l'offset à 0 (début de l'écran)
            LD      (CURSEUR_ADR), A
            JP      CURS                    ; Repositionne en 0


;===============================================================================
;  SIGNAUX DE CONTRÔLE LCD (Enable / BusyFlag / DataEnable)
;===============================================================================

; Attend que le LCD ne soit plus occupé (Busy Flag bit 7 = 0)
; Bascule temporairement Port A en entrée pour lire le status
BFLAG:
            EX      AF, AF'             ; Sauvegarde AF dans le banc alternatif
            EXX                             ; Sauvegarde BC, DE, HL
            LD      A, INPUT_MODE           ; Charge le mot de contrôle mode entrée
            OUT     (PIO1_CTRL_DATA), A     ; Bascule Port A en entrée (pour lire BF)
            LD      A, RW                   ; RW=1 (lecture), RS=0 (registre statut), E=0
            OUT     (PIO1_INST_LCD), A      ; Envoie sur Port B
            LD      A, RW|EP                ; RW=1, E=1 : front montant Enable
            OUT     (PIO1_INST_LCD), A
            LD      A, RW                   ; RW=1, E=0 : front descendant Enable
            OUT     (PIO1_INST_LCD), A
            NOP                             ; Temps de propagation
            NOP
            NOP
BUSY1:
            IN      A, (PIO1_DATA_LCD)      ; Lit le registre de statut du LCD
            BIT     7, A                    ; Teste le Busy Flag (bit 7 : 1=occupé, 0=prêt)
            JR      NZ, BUSY1               ; LCD occupé → recommence
            XOR     A                       ; A = 0 : remet RW, RS, E à 0
            OUT     (PIO1_INST_LCD), A      ; Relâche les signaux de contrôle
            LD      A, OUTPUT_MODE          ; Recharge le mode sortie
            OUT     (PIO1_CTRL_DATA), A     ; Rebascule Port A en sortie
            EX      AF, AF'             ; Restaure AF
            EXX                             ; Restaure BC, DE, HL
            RET

; Génère une impulsion Enable pour une commande LCD (RS=0)
ENABLE:
            CALL    BFLAG                   ; Attend BF=0
            XOR     A                       ; RS=0, RW=0, E=0
            OUT     (PIO1_INST_LCD), A      ; Applique les signaux
            CALL    BFLAG                   ; Attend encore (sécurité)
            LD      A, EP                   ; E=1 : front montant
            OUT     (PIO1_INST_LCD), A      ; Le LCD lit la commande sur ce front
            XOR     A                       ; E=0 : front descendant
            OUT     (PIO1_INST_LCD), A      ; Fin de l'impulsion Enable
            RET

; Génère une impulsion Enable pour une donnée LCD (RS=1)
DATAENABLE:
            LD      A, RS                   ; RS=1, RW=0, E=0
            OUT     (PIO1_INST_LCD), A      ; Sélectionne le registre données
            CALL    BFLAG                   ; Attend BF=0
            LD      A, RS|EP                ; RS=1, E=1 : front montant Enable
            OUT     (PIO1_INST_LCD), A      ; Le LCD lit la donnée sur ce front
            LD      A, RS                   ; RS=1, E=0 : front descendant
            OUT     (PIO1_INST_LCD), A      ; Fin de l'impulsion
            RET


;===============================================================================
;  AFFICHAGE MÉMOIRE (touche BACKSPACE)
;===============================================================================

; Affiche 8 octets en hexadécimal à partir de (MEM_POINTER)
; Format : "ADRESSE: $XXXX  YY YY YY YY YY YY YY YY"
; Après affichage attend une touche (UP/DOWN pour naviguer de 8 en 8)
PRINT_MEM:
            CALL    CLEAR_SCREEN            ; Efface l'écran
            LD      HL, PRINT_MEM_MESSAGE   ; Charge l'en-tête "ADRESSE: $"
            CALL    PRINT_MESSAGE           ; Affiche l'en-tête

; Affiche l'octet haut de l'adresse (H)
            LD      HL, (MEM_POINTER)       ; Charge l'adresse 16 bits
            LD      A, H                    ; Prend l'octet haut
            CALL    BN2HEX                  ; Convertit en 2 chiffres hex → H=chiffre1, L=chiffre2
            LD      A, H                    ; Premier chiffre hex
            CALL    PRINT_CHAR
            LD      A, L                    ; Deuxième chiffre hex
            CALL    PRINT_CHAR

; Affiche l'octet bas de l'adresse (L)
            LD      HL, (MEM_POINTER)
            LD      A, L                    ; Prend l'octet bas
            CALL    BN2HEX
            LD      A, H
            CALL    PRINT_CHAR
            LD      A, L
            CALL    PRINT_CHAR

; Prépare le buffer de conversion et ajoute des espaces séparateurs
            LD      HL, DECIMAL_OUT_BUFFER  ; Pointe sur le buffer
            LD      B, 8                    ; 8 octets à effacer
            CALL    CLEAR_BUFFER            ; Remet le buffer à 0
            CALL    SPACE                   ; Espace séparateur
            CALL    SPACE

; Affiche 8 octets consécutifs en hexadécimal
            LD      HL, (MEM_POINTER)
            CALL    PRINT_BYTE              ; Affiche (HL) en hex + espace, INC HL
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE
            CALL    PRINT_BYTE

            CALL    KEYIN                   ; Attend une touche (UP/DOWN → navigue)
            JP      PRINT_MEM               ; Ré-affiche avec la nouvelle adresse

; Affiche l'octet (HL) en hex + espace, puis INC HL
PRINT_BYTE:
            PUSH    HL                      ; Sauvegarde HL
            LD      A, (HL)                 ; Charge l'octet à afficher
            CALL    BN2HEX                  ; Convertit → H=nibble haut ASCII, L=nibble bas ASCII
            LD      A, H                    ; Premier chiffre hex
            CALL    PRINT_CHAR
            LD      A, L                    ; Deuxième chiffre hex
            CALL    PRINT_CHAR
            CALL    SPACE                   ; Espace entre les octets
            POP     HL                      ; Restaure HL
            INC     HL                      ; Avance au prochain octet
            RET

; Remplit B octets à 0 à partir de (HL)
CLEAR_BUFFER:
            XOR     A                       ; A = 0
            LD      (HL), A                 ; Écrit 0
            INC     HL                      ; Octet suivant
            DJNZ    CLEAR_BUFFER            ; Répète B fois
            RET


;===============================================================================
;  CONVERSIONS NUMÉRIQUES
;===============================================================================

; Convertit l'octet dans A en deux caractères ASCII hexadécimaux
; Résultat : H = nibble haut ASCII (ex: 'A'), L = nibble bas ASCII (ex: 'F')
BN2HEX:
            LD      B, A                    ; Sauvegarde la valeur originale dans B
            AND     $F0                     ; Isole les 4 bits hauts (masque les 4 bas)
            RRCA                            ; Décale le nibble haut vers les bits 0-3
            RRCA                            ; (4 rotations droite = divise par 16)
            RRCA
            RRCA
            CALL    NASCII                  ; Convertit nibble 0-15 en ASCII '0'-'F'
            LD      H, A                    ; Stocke le premier chiffre hex dans H
            LD      A, B                    ; Recharge la valeur originale
            AND     $0F                     ; Isole les 4 bits bas
            CALL    NASCII                  ; Convertit nibble 0-15 en ASCII
            LD      L, A                    ; Stocke le deuxième chiffre hex dans L
            RET

; Convertit un nibble (valeur 0-15) en caractère ASCII ('0'-'9' ou 'A'-'F')
NASCII:
            CP      10                      ; Valeur < 10 ?
            JR      C, NAS1                 ; Oui → c'est un chiffre '0'-'9'
            ADD     A, 7                    ; Non → ajuste pour 'A'-'F' (car 'A' - '0' - 10 = 7)
NAS1:
            ADD     A, "0"                  ; Ajoute le code ASCII de '0' ($30)
            RET                             ; Retourne le caractère ASCII dans A

; Convertit un entier 16 bits (DE) en chaîne décimale ASCII dans le buffer (HL)
; Algorithme : extraction successive des chiffres par division par 10 (rotation 16 bits)
BIN_TO_DEC:
            LD      (BUFPTR), HL            ; Sauvegarde le pointeur de buffer
            EX      DE, HL                  ; HL = valeur à convertir (DE → HL)
            XOR     A                       ; A = 0
            LD      (CURLEN), A             ; Longueur courante du buffer = 0
            LD      A, H                    ; Charge l'octet haut pour tester le signe
            LD      (NGFLAG), A             ; Sauvegarde l'indicateur de signe
            OR      A                       ; Met à jour le flag S (négatif si bit 7 = 1)
            JP      P, CNVERT               ; Positif (bit 7=0) → conversion directe

; Valeur négative : calcul de la valeur absolue (complément à 2)
            EX      DE, HL                  ; DE = valeur négative
            LD      HL, 0                   ; HL = 0
            OR      A                       ; Efface carry
            SBC     HL, DE                  ; HL = 0 - DE (valeur absolue)

; Boucle de conversion : extrait les chiffres décimaux par division par 10
CNVERT:
            LD      E, 0                    ; E = reste de la division (initialisé à 0)
            LD      B, 16                   ; 16 bits à traiter
            OR      A                       ; Efface le carry avant la boucle
DVLOOP:
            RL      L                       ; Décale L à gauche, MSB → carry
            RL      H                       ; Décale H à gauche, carry → LSB
            RL      E                       ; Décale le reste, carry → LSB
            LD      A, E                    ; A = reste courant
            SUB     10                      ; Soustrait 10 (test si reste >= 10)
            CCF                             ; Inverse le carry (si soustraction OK → carry=1)
            JR      NC, DECCNT              ; Carry=0 → reste < 10, garde E intact
            LD      E, A                    ; Carry=1 → reste >= 10, met à jour E = E - 10
DECCNT:
            DJNZ    DVLOOP                  ; Répète pour les 16 bits
            RL      L                       ; Récupère le dernier bit du quotient
            RL      H

CHINS:
            LD      A, E                    ; A = chiffre des unités (reste final)
            ADD     A, "0"                  ; Convertit en ASCII
            CALL    INSERT                  ; Insère le chiffre en tête du buffer
            LD      A, H                    ; Teste si le quotient est nul
            OR      L
            JR      NZ, CNVERT              ; Non → un autre chiffre à extraire

EXIT:
            LD      A, (NGFLAG)             ; Recharge l'indicateur de signe
            OR      A
            JP      P, POS                  ; Positif → fin sans signe
            LD      A, "-"                  ; Négatif → insère le signe moins
            CALL    INSERT
POS:
            RET

; Insère le caractère A en tête du buffer (décale les caractères existants d'une position)
INSERT:
            PUSH    HL                      ; Sauvegarde HL
            PUSH    AF                      ; Sauvegarde A (le caractère à insérer)
            LD      HL, (BUFPTR)            ; HL = pointeur courant dans le buffer
            LD      D, H                    ; DE = HL + 1 (destination du décalage)
            LD      E, L
            INC     DE
            LD      (BUFPTR), DE            ; Avance le pointeur de 1
            LD      A, (CURLEN)             ; Charge la longueur courante
            OR      A                       ; Longueur = 0 ?
            JR      Z, EXITMR               ; Oui → pas de décalage nécessaire
            LD      C, A                    ; BC = longueur (B=0 déjà)
            LD      B, 0
            LDDR                            ; Décale BC octets de (HL) vers (DE) en décrémentant (crée la place)
EXITMR:
            LD      A, (CURLEN)             ; Recharge la longueur
            INC     A                       ; Incrémente la longueur
            LD      (CURLEN), A             ; Sauvegarde la nouvelle longueur
            LD      (HL), A                 ; Écrit la longueur en première case du buffer (octet 0)
            EX      DE, HL                  ; HL = BUFPTR + 1 (position d'insertion)
            POP     AF                      ; Restaure A (le caractère)
            LD      (HL), A                 ; Écrit le caractère en tête
            POP     HL                      ; Restaure HL
            RET


;===============================================================================
;  TEMPORISATION
;===============================================================================

; Tempo logicielle — BC = durée en millisecondes (~4000 cycles d'horloge par ms)
DELAY:
            PUSH    AF                      ; Sauvegarde AF
            PUSH    HL                      ; Sauvegarde HL
            LD      DE,-1                   ; DE = -1 (valeur de décrémentation)
LOOP1:
            LD      HL, 172                 ; HL = 172 (calibré pour ~1 ms à la fréquence du CPU)
LOOP2:
            ADD     HL, DE                  ; Décrémente HL (HL = HL - 1)
            JR      C, LOOP2                ; Carry = débordement → pas encore à 0, continue
            DEC     BC                      ; Décrémente le compteur de ms
            LD      A, B                    ; Teste si BC = 0
            OR      C                       ; A = B OR C
            JP      NZ, LOOP1               ; BC ≠ 0 → continue pour une autre ms
            POP     HL                      ; Restaure HL
            POP     AF                      ; Restaure AF
            RET


;===============================================================================
;  DONNÉES GRAPHIQUES — BITMAP 128x64
;  3 répétitions × 20 lignes × 16 octets = 960 octets
;===============================================================================

BITMAP1:
            DB      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
            DB      $FF, $FF, $FF, $AA, $AA, $52, $FF, $F0, $E7, $09, $C8, $24, $90, $66, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $44, $9F, $FF, $C0, $11, $03, $E0, $00, $40, $79, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $F6, $FF, $FC, $02, $01, $08, $64, $A0, $08, $B5, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $FF, $FF, $C0, $21, $50, $02, $A0, $10, $00, $FE, $FF, $FF
            DB      $FE, $FF, $FF, $FF, $FF, $FE, $24, $08, $02, $42, $10, $02, $45, $FF, $FF, $BF
            DB      $FF, $3B, $FF, $FF, $FF, $F8, $01, $20, $00, $14, $6A, $80, $01, $FF, $FA, $E8
            DB      $D6, $DF, $FF, $FF, $FF, $FE, $80, $00, $0F, $E7, $E8, $48, $00, $7F, $80, $35
            DB      $DB, $9F, $FF, $FF, $FF, $7F, $E8, $01, $7C, $17, $84, $45, $48, $7F, $E0, $3A
            DB      $FE, $C3, $FF, $FF, $F8, $97, $FD, $2B, $F0, $02, $A3, $34, $2F, $9C, $10, $78
            DB      $FF, $2C, $7F, $7F, $CA, $02, $FF, $8F, $10, $07, $08, $9B, $93, $60, $00, $C6
            DB      $FD, $B6, $2F, $B7, $29, $50, $02, $FD, $D4, $3F, $A3, $FF, $EA, $80, $00, $80
            DB      $FF, $CF, $31, $FC, $A5, $20, $20, $BC, $66, $CF, $E0, $40, $7A, $A0, $01, $08
            DB      $FF, $20, $FF, $F7, $40, $95, $4A, $7F, $7C, $E1, $DC, $00, $16, $00, $02, $20
            DB      $FF, $F7, $7F, $68, $2A, $24, $22, $ED, $BE, $5D, $8E, $00, $1B, $50, $08, $00
            DB      $FF, $B9, $3F, $A5, $09, $93, $A8, $74, $78, $87, $C7, $80, $1D, $61, $30, $00
            DB      $FD, $F7, $DF, $91, $40, $4B, $20, $7F, $66, $78, $03, $F9, $00, $15, $70, $00
            DB      $FF, $FF, $BF, $4A, $35, $6F, $ED, $61, $6B, $98, $A4, $24, $AA, $40, $60, $00
            DB      $FF, $D6, $FE, $A4, $CB, $7F, $B8, $3F, $DE, $6A, $0A, $92, $24, $8B, $E0, $00
            DB      $FF, $77, $FE, $AA, $2A, $BF, $C4, $FF, $FA, $15, $E4, $0A, $AA, $A8, $C0, $00

            DB      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
            DB      $FF, $FF, $FF, $AA, $AA, $52, $FF, $F0, $E7, $09, $C8, $24, $90, $66, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $44, $9F, $FF, $C0, $11, $03, $E0, $00, $40, $79, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $F6, $FF, $FC, $02, $01, $08, $64, $A0, $08, $B5, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $FF, $FF, $C0, $21, $50, $02, $A0, $10, $00, $FE, $FF, $FF
            DB      $FE, $FF, $FF, $FF, $FF, $FE, $24, $08, $02, $42, $10, $02, $45, $FF, $FF, $BF
            DB      $FF, $3B, $FF, $FF, $FF, $F8, $01, $20, $00, $14, $6A, $80, $01, $FF, $FA, $E8
            DB      $D6, $DF, $FF, $FF, $FF, $FE, $80, $00, $0F, $E7, $E8, $48, $00, $7F, $80, $35
            DB      $DB, $9F, $FF, $FF, $FF, $7F, $E8, $01, $7C, $17, $84, $45, $48, $7F, $E0, $3A
            DB      $FE, $C3, $FF, $FF, $F8, $97, $FD, $2B, $F0, $02, $A3, $34, $2F, $9C, $10, $78
            DB      $FF, $2C, $7F, $7F, $CA, $02, $FF, $8F, $10, $07, $08, $9B, $93, $60, $00, $C6
            DB      $FD, $B6, $2F, $B7, $29, $50, $02, $FD, $D4, $3F, $A3, $FF, $EA, $80, $00, $80
            DB      $FF, $CF, $31, $FC, $A5, $20, $20, $BC, $66, $CF, $E0, $40, $7A, $A0, $01, $08
            DB      $FF, $20, $FF, $F7, $40, $95, $4A, $7F, $7C, $E1, $DC, $00, $16, $00, $02, $20
            DB      $FF, $F7, $7F, $68, $2A, $24, $22, $ED, $BE, $5D, $8E, $00, $1B, $50, $08, $00
            DB      $FF, $B9, $3F, $A5, $09, $93, $A8, $74, $78, $87, $C7, $80, $1D, $61, $30, $00
            DB      $FD, $F7, $DF, $91, $40, $4B, $20, $7F, $66, $78, $03, $F9, $00, $15, $70, $00
            DB      $FF, $FF, $BF, $4A, $35, $6F, $ED, $61, $6B, $98, $A4, $24, $AA, $40, $60, $00
            DB      $FF, $D6, $FE, $A4, $CB, $7F, $B8, $3F, $DE, $6A, $0A, $92, $24, $8B, $E0, $00
            DB      $FF, $77, $FE, $AA, $2A, $BF, $C4, $FF, $FA, $15, $E4, $0A, $AA, $A8, $C0, $00

            DB      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
            DB      $FF, $FF, $FF, $AA, $AA, $52, $FF, $F0, $E7, $09, $C8, $24, $90, $66, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $44, $9F, $FF, $C0, $11, $03, $E0, $00, $40, $79, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $F6, $FF, $FC, $02, $01, $08, $64, $A0, $08, $B5, $7F, $FF
            DB      $FF, $FF, $FF, $FF, $FF, $FF, $C0, $21, $50, $02, $A0, $10, $00, $FE, $FF, $FF
            DB      $FE, $FF, $FF, $FF, $FF, $FE, $24, $08, $02, $42, $10, $02, $45, $FF, $FF, $BF
            DB      $FF, $3B, $FF, $FF, $FF, $F8, $01, $20, $00, $14, $6A, $80, $01, $FF, $FA, $E8
            DB      $D6, $DF, $FF, $FF, $FF, $FE, $80, $00, $0F, $E7, $E8, $48, $00, $7F, $80, $35
            DB      $DB, $9F, $FF, $FF, $FF, $7F, $E8, $01, $7C, $17, $84, $45, $48, $7F, $E0, $3A
            DB      $FE, $C3, $FF, $FF, $F8, $97, $FD, $2B, $F0, $02, $A3, $34, $2F, $9C, $10, $78
            DB      $FF, $2C, $7F, $7F, $CA, $02, $FF, $8F, $10, $07, $08, $9B, $93, $60, $00, $C6
            DB      $FD, $B6, $2F, $B7, $29, $50, $02, $FD, $D4, $3F, $A3, $FF, $EA, $80, $00, $80
            DB      $FF, $CF, $31, $FC, $A5, $20, $20, $BC, $66, $CF, $E0, $40, $7A, $A0, $01, $08
            DB      $FF, $20, $FF, $F7, $40, $95, $4A, $7F, $7C, $E1, $DC, $00, $16, $00, $02, $20
            DB      $FF, $F7, $7F, $68, $2A, $24, $22, $ED, $BE, $5D, $8E, $00, $1B, $50, $08, $00
            DB      $FF, $B9, $3F, $A5, $09, $93, $A8, $74, $78, $87, $C7, $80, $1D, $61, $30, $00
            DB      $FD, $F7, $DF, $91, $40, $4B, $20, $7F, $66, $78, $03, $F9, $00, $15, $70, $00
            DB      $FF, $FF, $BF, $4A, $35, $6F, $ED, $61, $6B, $98, $A4, $24, $AA, $40, $60, $00
            DB      $FF, $D6, $FE, $A4, $CB, $7F, $B8, $3F, $DE, $6A, $0A, $92, $24, $8B, $E0, $00
            DB      $FF, $77, $FE, $AA, $2A, $BF, $C4, $FF, $FA, $15, $E4, $0A, $AA, $A8, $C0, $00

SPRITE:
            DB      $DF, $DF, $D8, $FF, $FF, $1B, $FB, $FB  ; 8 octets = sprite 8 pixels de large


;===============================================================================
;  TABLE CLAVIER (org $0880)
;  Codes spéciaux : $F1=haut $F2=bas $F3=gauche $F4=droite
;  $0D=Enter  $1B=Esc  $08=BS  $0F=Shift
;===============================================================================

.ORG    $0880

KEY_MAP:  ; Table minuscules / symboles
            DB      "????????"              ; Ligne 0 : touches non assignées
            DB      "@abcdefg"              ; Ligne 1
            DB      "hijklmno"              ; Ligne 2
            DB      "pqrstuvw"              ; Ligne 3
            DB      "xyz", $F1, $F2, $F3, $F4, " "  ; Ligne 4 : xyz, flèches, espace
            DB      "01234567"              ; Ligne 5
            DB      "89:;,-./"              ; Ligne 6
            DB      $0D, $1B, $08, "????", $0F  ; Ligne 7 : Enter, Esc, BS, Shift

KEY_MAP_UPPER:  ; Table majuscules / symboles shift
            DB      "????????"
            DB      "@ABCDEFG"
            DB      "HIJKLMNO"
            DB      "PQRSTUVW"
            DB      "XYZ", $5B, $5C, $5D, $5E, " "
            DB      $00, "!", $22, "#", "$", "%", "&", "'"
            DB      "()#+<=>?"
            DB      $0D, $1B, $08, "????", $0F


;===============================================================================
;  VARIABLES RAM (org $0900) — initialisées par LDIR depuis INIT_REG
;===============================================================================

.ORG    $0900

DEBUT_RAM:  DB      $AA                     ; Marqueur init ($AA = RAM initialisée)
DEBUT_RAM_1: DB      $00                    ; Pointeur clavier
DEBUT_RAM_2: DB      $00                    ; Retour chariot
LCD_AC_X:   DB      $00, $80                ; Adresse X curseur graphique (2 octets)
LCD_AC_Y:   DB      $00, $80                ; Adresse Y curseur graphique (2 octets)
POS_X:      DB      $00, $00                ; Position X texte
POS_Y:      DB      $00, $08                ; Position Y texte
MEM_POINTER: DB      $00, $08               ; Pointeur PRINT_MEM (navigation mémoire)
ROW:        DB      $00                     ; Ligne courante
COLUMN:     DB      $08                     ; Colonne courante
PIO_TEST:   DB      $AA                     ; Octet tournant pour diagnostic PIO
DISPLAY_MODE: DB      GRAPH_MODE            ; Mode LCD actif ($0E=texte / $3E=graphique)
COUNTER:    DB      $00, $00                ; Compteur IRQ 16 bits (incrémenté à chaque IRQ)
COUNTER_2_BYTE: DB      $00, $00            ; Compteur secondaire
BUFPTR:     DB      $00, $00                ; Pointeur courant buffer BIN>DEC
CURLEN:     DB      $00                     ; Longueur courante buffer BIN>DEC
NGFLAG:     DB      $00                     ; Indicateur signe BIN>DEC (0=positif)
DECIMAL_OUT_BUFFER: DB      0, 0, 0, 0, 0, 0, 0, 0  ; Buffer sortie décimale (8 octets)
DISPLAY:    DB      $00, $00                ; Compteur de passes affichage graphique
KEY_BUFFER: DB      $00, $00                ; Dernière touche lue
MEM_BUFFER: DB      "12345", $00            ; Buffer mémoire de test
BIT_BUFFER: DB      $00, $00                ; Buffer de bits
CURSEUR_ADR: DB      $00                    ; Adresse curseur texte (0 à $40)
CHAR_POS:   DB      $00                     ; Index courant dans CHAR_BUFFER (0 à 39)

.ORG    $0940
CHAR_BUFFER:
            DS      40, $00                 ; 40 octets : buffer de saisie clavier

;===============================================================================
;  FIN
;===============================================================================
