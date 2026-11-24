      * COBOL のアウトライン解析のサンプル
       IDENTIFICATION DIVISION.
       PROGRAM-ID. SAMPLE.
       ENVIRONMENT DIVISION.
       CONFIGURATION SECTION.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       01  WS-COUNT        PIC 9(4).
       PROCEDURE DIVISION.
       MAIN-PROC SECTION.
       MAIN-START.
           MOVE 0 TO WS-COUNT.
           PERFORM SUB-PROC.
           STOP RUN.
      * コメント行
       SUB-PROC.
           ADD 1 TO WS-COUNT.
       日本語-段落.
           EXIT.
