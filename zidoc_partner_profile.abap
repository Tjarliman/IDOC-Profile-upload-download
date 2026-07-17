*&---------------------------------------------------------------------*
*& Report ZIDOC_PARTNER_PROFILE
*&---------------------------------------------------------------------*
*& Upload / Download IDoc Partner Profiles (WE20) as XML.
*& Covers headers (EDPP1), outbound (EDP13), inbound (EDP21),
*& and message control (EDP12) for all partner types.
*&
*& Download: Reads profiles matching selection criteria -> XML file.
*& Upload:   Reads XML file -> imports profiles into target system.
*&
*& Uses CALL TRANSFORMATION id for reliable round-trip serialization
*& of all table fields.
*&---------------------------------------------------------------------*
REPORT zidoc_partner_profile.

TABLES: edp13.

*----------------------------------------------------------------------*
* Type Definitions
*----------------------------------------------------------------------*
TYPES:
  ty_t_edpp1 TYPE STANDARD TABLE OF edpp1 WITH DEFAULT KEY,
  ty_t_edp13 TYPE STANDARD TABLE OF edp13 WITH DEFAULT KEY,
  ty_t_edp21 TYPE STANDARD TABLE OF edp21 WITH DEFAULT KEY,
  ty_t_edp12 TYPE STANDARD TABLE OF edp12 WITH DEFAULT KEY.

TYPES: BEGIN OF ty_export,
         sysid   TYPE c LENGTH 8,
         client  TYPE c LENGTH 3,
         expdate TYPE d,
         exptime TYPE t,
         expuser TYPE c LENGTH 12,
         edpp1   TYPE ty_t_edpp1,
         edp13   TYPE ty_t_edp13,
         edp21   TYPE ty_t_edp21,
         edp12   TYPE ty_t_edp12,
       END OF ty_export.

TYPES: BEGIN OF ty_pkey,
         rcvprn TYPE edp13-rcvprn,
         rcvprt TYPE edp13-rcvprt,
       END OF ty_pkey,
       ty_t_pkeys TYPE SORTED TABLE OF ty_pkey WITH UNIQUE KEY rcvprn rcvprt.

*----------------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b0 WITH FRAME TITLE t_mode.
  PARAMETERS:
    p_down RADIOBUTTON GROUP grp1 DEFAULT 'X' USER-COMMAND uc01,
    p_up   RADIOBUTTON GROUP grp1.
SELECTION-SCREEN END OF BLOCK b0.

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE t_filter.
  SELECT-OPTIONS:
    s_rcvprn FOR edp13-rcvprn MODIF ID dwn,
    s_rcvprt FOR edp13-rcvprt MODIF ID dwn,
    s_mestyp FOR edp13-mestyp MODIF ID dwn,
    s_idoctp FOR edp13-idoctyp MODIF ID dwn.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE t_file.
  PARAMETERS: p_file TYPE string LOWER CASE OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b2.

SELECTION-SCREEN BEGIN OF BLOCK b3 WITH FRAME TITLE t_opt.
  PARAMETERS:
    p_test AS CHECKBOX DEFAULT 'X' MODIF ID upl,
    p_repl AS CHECKBOX DEFAULT ' ' MODIF ID upl.
SELECTION-SCREEN END OF BLOCK b3.

*----------------------------------------------------------------------*
* Initialization
*----------------------------------------------------------------------*
INITIALIZATION.
  t_mode   = 'Mode'.
  t_filter = 'Filters'.
  t_file   = 'File'.
  t_opt    = 'Options'.

*----------------------------------------------------------------------*
* Toggle field visibility based on mode
*----------------------------------------------------------------------*
AT SELECTION-SCREEN OUTPUT.
  LOOP AT SCREEN.
    CASE screen-group1.
      WHEN 'DWN'.
        IF p_up = abap_true.
          screen-active = 0.
        ENDIF.
      WHEN 'UPL'.
        IF p_down = abap_true.
          screen-active = 0.
        ENDIF.
    ENDCASE.
    MODIFY SCREEN.
  ENDLOOP.

*----------------------------------------------------------------------*
* F4 Help for file path
*----------------------------------------------------------------------*
AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.
  PERFORM f4_file_path.

*----------------------------------------------------------------------*
* Main
*----------------------------------------------------------------------*
START-OF-SELECTION.
  IF p_down = abap_true.
    PERFORM download.
  ELSE.
    PERFORM upload.
  ENDIF.


*&---------------------------------------------------------------------*
*& Form F4_FILE_PATH
*&---------------------------------------------------------------------*
FORM f4_file_path.
  DATA: lv_fullpath TYPE string,
        lv_filename TYPE string,
        lv_path     TYPE string,
        lv_action   TYPE i,
        lt_files    TYPE filetable,
        lv_rc       TYPE i.

  IF p_down = abap_true.
    cl_gui_frontend_services=>file_save_dialog(
      EXPORTING
        default_extension = 'xml'
        default_file_name = |partner_profiles_{ sy-sysid }|
        file_filter       = 'XML (*.xml)|*.xml|All (*.*)|*.*'
      CHANGING
        filename    = lv_filename
        path        = lv_path
        fullpath    = lv_fullpath
        user_action = lv_action ).
  ELSE.
    cl_gui_frontend_services=>file_open_dialog(
      EXPORTING
        file_filter = 'XML (*.xml)|*.xml|All (*.*)|*.*'
      CHANGING
        file_table  = lt_files
        rc          = lv_rc
        user_action = lv_action ).
    IF lv_rc > 0.
      READ TABLE lt_files INDEX 1 ASSIGNING FIELD-SYMBOL(<file>).
      IF sy-subrc = 0.
        lv_fullpath = <file>-filename.
      ENDIF.
    ENDIF.
  ENDIF.

  IF lv_action = cl_gui_frontend_services=>action_ok
     AND lv_fullpath IS NOT INITIAL.
    p_file = lv_fullpath.
  ENDIF.
ENDFORM.


*&---------------------------------------------------------------------*
*& Form DOWNLOAD
*&---------------------------------------------------------------------*
FORM download.
  DATA: ls_export  TYPE ty_export,
        lt_edpp1   TYPE ty_t_edpp1,
        lt_edp13   TYPE ty_t_edp13,
        lt_edp21   TYPE ty_t_edp21,
        lt_edp12   TYPE ty_t_edp12,
        lt_pkeys   TYPE ty_t_pkeys,
        ls_pkey    TYPE ty_pkey,
        lv_xml     TYPE xstring,
        lt_bin     TYPE TABLE OF raw255,
        lv_bin_len TYPE i.

  " Select outbound parameters
  SELECT * FROM edp13
    INTO TABLE lt_edp13
    WHERE rcvprn IN s_rcvprn
      AND rcvprt IN s_rcvprt
      AND mestyp IN s_mestyp
      AND idoctyp IN s_idoctp.

  " Select inbound parameters
  SELECT * FROM edp21
    INTO TABLE lt_edp21
    WHERE sndprn IN s_rcvprn
      AND sndprt IN s_rcvprt
      AND mestyp IN s_mestyp.

  " Select message control (output determination)
  SELECT * FROM edp12
    INTO TABLE lt_edp12
    WHERE rcvprn IN s_rcvprn
      AND rcvprt IN s_rcvprt
      AND mestyp IN s_mestyp.

  IF lt_edp13 IS INITIAL AND lt_edp21 IS INITIAL AND lt_edp12 IS INITIAL.
    MESSAGE 'No partner profiles found for the given selection' TYPE 'S' DISPLAY LIKE 'W'.
    RETURN.
  ENDIF.

  " Select partner profile headers
  SELECT * FROM edpp1
    INTO TABLE lt_edpp1
    WHERE parnum IN s_rcvprn
      AND partyp IN s_rcvprt.

  " Build export structure
  ls_export-sysid   = sy-sysid.
  ls_export-client  = sy-mandt.
  ls_export-expdate = sy-datum.
  ls_export-exptime = sy-uzeit.
  ls_export-expuser = sy-uname.
  ls_export-edpp1   = lt_edpp1.
  ls_export-edp13   = lt_edp13.
  ls_export-edp21   = lt_edp21.
  ls_export-edp12   = lt_edp12.

  " Serialize to XML (UTF-8)
  TRY.
      CALL TRANSFORMATION id
        SOURCE data = ls_export
        RESULT XML lv_xml.
    CATCH cx_transformation_error INTO DATA(lx_err).
      WRITE: / 'XML serialization error:' COLOR COL_NEGATIVE, lx_err->get_text( ).
      RETURN.
  ENDTRY.

  " Write binary XML to file
  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING buffer        = lv_xml
    IMPORTING output_length = lv_bin_len
    TABLES    binary_tab    = lt_bin.

  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      filename     = p_file
      filetype     = 'BIN'
      bin_filesize = lv_bin_len
    TABLES
      data_tab     = lt_bin
    EXCEPTIONS
      OTHERS       = 1.

  IF sy-subrc <> 0.
    WRITE: / 'Error writing file.' COLOR COL_NEGATIVE.
    RETURN.
  ENDIF.

  " Count unique partners
  LOOP AT lt_edp13 ASSIGNING FIELD-SYMBOL(<o>).
    ls_pkey-rcvprn = <o>-rcvprn.
    ls_pkey-rcvprt = <o>-rcvprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.
  LOOP AT lt_edp21 ASSIGNING FIELD-SYMBOL(<i>).
    ls_pkey-rcvprn = <i>-sndprn.
    ls_pkey-rcvprt = <i>-sndprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.
  LOOP AT lt_edp12 ASSIGNING FIELD-SYMBOL(<m>).
    ls_pkey-rcvprn = <m>-rcvprn.
    ls_pkey-rcvprt = <m>-rcvprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.

  " Output summary
  ULINE.
  WRITE: / 'Download completed successfully' COLOR COL_POSITIVE.
  ULINE.
  WRITE: / 'System / Client:',    15 sy-sysid, '/', sy-mandt.
  WRITE: / 'Partners:',           15 lines( lt_pkeys ).
  WRITE: / 'Headers    (EDPP1):', 15 lines( lt_edpp1 ).
  WRITE: / 'Outbound   (EDP13):', 15 lines( lt_edp13 ).
  WRITE: / 'Inbound    (EDP21):', 15 lines( lt_edp21 ).
  WRITE: / 'Msg Control(EDP12):', 15 lines( lt_edp12 ).
  SKIP.
  WRITE: / 'File:', p_file.

  " List exported partners
  SKIP.
  WRITE: / 'Partner', 15 'Type', 20 'Outbound', 30 'Inbound', 40 'MsgCtrl'.
  ULINE.
  DATA: lv_out_cnt TYPE i,
        lv_in_cnt  TYPE i,
        lv_mc_cnt  TYPE i.
  LOOP AT lt_pkeys INTO ls_pkey.
    CLEAR: lv_out_cnt, lv_in_cnt, lv_mc_cnt.
    LOOP AT lt_edp13 TRANSPORTING NO FIELDS
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
      lv_out_cnt = lv_out_cnt + 1.
    ENDLOOP.
    LOOP AT lt_edp21 TRANSPORTING NO FIELDS
      WHERE sndprn = ls_pkey-rcvprn AND sndprt = ls_pkey-rcvprt.
      lv_in_cnt = lv_in_cnt + 1.
    ENDLOOP.
    LOOP AT lt_edp12 TRANSPORTING NO FIELDS
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
      lv_mc_cnt = lv_mc_cnt + 1.
    ENDLOOP.
    WRITE: / ls_pkey-rcvprn, 15 ls_pkey-rcvprt,
             20 lv_out_cnt, 30 lv_in_cnt, 40 lv_mc_cnt.
  ENDLOOP.
ENDFORM.


*&---------------------------------------------------------------------*
*& Form UPLOAD
*&---------------------------------------------------------------------*
FORM upload.
  DATA: lt_bin     TYPE TABLE OF raw255,
        lv_len     TYPE i,
        lv_xml     TYPE xstring,
        ls_import  TYPE ty_export,
        lt_pkeys   TYPE ty_t_pkeys,
        ls_pkey    TYPE ty_pkey,
        lv_out_cnt TYPE i,
        lv_in_cnt  TYPE i.

  " 1. Read file
  CALL FUNCTION 'GUI_UPLOAD'
    EXPORTING
      filename   = p_file
      filetype   = 'BIN'
    IMPORTING
      filelength = lv_len
    TABLES
      data_tab   = lt_bin
    EXCEPTIONS
      OTHERS     = 1.

  IF sy-subrc <> 0.
    WRITE: / 'Error reading file.' COLOR COL_NEGATIVE.
    RETURN.
  ENDIF.

  " 2. Convert binary to xstring
  CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
    EXPORTING input_length = lv_len
    IMPORTING buffer       = lv_xml
    TABLES    binary_tab   = lt_bin
    EXCEPTIONS OTHERS      = 1.

  IF sy-subrc <> 0.
    WRITE: / 'Error converting file content.' COLOR COL_NEGATIVE.
    RETURN.
  ENDIF.

  " 3. Deserialize XML
  TRY.
      CALL TRANSFORMATION id
        SOURCE XML lv_xml
        RESULT data = ls_import.
    CATCH cx_transformation_error INTO DATA(lx_err).
      WRITE: / 'XML parse error:' COLOR COL_NEGATIVE, lx_err->get_text( ).
      RETURN.
  ENDTRY.

  " 4. Adjust client to current system
  LOOP AT ls_import-edpp1 ASSIGNING FIELD-SYMBOL(<h>).
    <h>-mandt = sy-mandt.
  ENDLOOP.
  LOOP AT ls_import-edp13 ASSIGNING FIELD-SYMBOL(<o>).
    <o>-mandt = sy-mandt.
  ENDLOOP.
  LOOP AT ls_import-edp21 ASSIGNING FIELD-SYMBOL(<i>).
    <i>-mandt = sy-mandt.
  ENDLOOP.
  LOOP AT ls_import-edp12 ASSIGNING FIELD-SYMBOL(<m>).
    <m>-mandt = sy-mandt.
  ENDLOOP.

  " 5. Collect unique partners
  LOOP AT ls_import-edp13 ASSIGNING <o>.
    ls_pkey-rcvprn = <o>-rcvprn.
    ls_pkey-rcvprt = <o>-rcvprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.
  LOOP AT ls_import-edp21 ASSIGNING <i>.
    ls_pkey-rcvprn = <i>-sndprn.
    ls_pkey-rcvprt = <i>-sndprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.
  LOOP AT ls_import-edp12 ASSIGNING <m>.
    ls_pkey-rcvprn = <m>-rcvprn.
    ls_pkey-rcvprt = <m>-rcvprt.
    INSERT ls_pkey INTO TABLE lt_pkeys.
  ENDLOOP.

  " 6. Display summary
  ULINE.
  WRITE: / 'File:', p_file.
  ULINE.
  WRITE: / 'Source system / client:', ls_import-sysid, '/', ls_import-client.
  WRITE: / 'Exported:',              ls_import-expdate, ls_import-exptime,
           'by', ls_import-expuser.
  WRITE: / 'Partners:',           15 lines( lt_pkeys ).
  WRITE: / 'Headers    (EDPP1):', 15 lines( ls_import-edpp1 ).
  WRITE: / 'Outbound   (EDP13):', 15 lines( ls_import-edp13 ).
  WRITE: / 'Inbound    (EDP21):', 15 lines( ls_import-edp21 ).
  WRITE: / 'Msg Control(EDP12):', 15 lines( ls_import-edp12 ).
  SKIP.

  " 7. Per-partner analysis
  WRITE: / 'Partner', 15 'Type', 20 'Imp Out', 30 'Imp In', 40 'Imp MC',
           50 'Exist Out', 60 'Exist In', 70 'Exist MC'.
  ULINE.
  LOOP AT lt_pkeys INTO ls_pkey.
    CLEAR: lv_out_cnt, lv_in_cnt.

    DATA: lv_imp_out TYPE i,
          lv_imp_in  TYPE i,
          lv_imp_mc  TYPE i,
          lv_mc_cnt  TYPE i.
    CLEAR: lv_imp_out, lv_imp_in, lv_imp_mc.
    LOOP AT ls_import-edp13 TRANSPORTING NO FIELDS
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
      lv_imp_out = lv_imp_out + 1.
    ENDLOOP.
    LOOP AT ls_import-edp21 TRANSPORTING NO FIELDS
      WHERE sndprn = ls_pkey-rcvprn AND sndprt = ls_pkey-rcvprt.
      lv_imp_in = lv_imp_in + 1.
    ENDLOOP.
    LOOP AT ls_import-edp12 TRANSPORTING NO FIELDS
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
      lv_imp_mc = lv_imp_mc + 1.
    ENDLOOP.

    " Count existing entries in target system
    SELECT COUNT(*) FROM edp13
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
    lv_out_cnt = sy-dbcnt.
    SELECT COUNT(*) FROM edp21
      WHERE sndprn = ls_pkey-rcvprn AND sndprt = ls_pkey-rcvprt.
    lv_in_cnt = sy-dbcnt.
    SELECT COUNT(*) FROM edp12
      WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
    lv_mc_cnt = sy-dbcnt.

    WRITE: / ls_pkey-rcvprn, 15 ls_pkey-rcvprt,
             20 lv_imp_out, 30 lv_imp_in, 40 lv_imp_mc,
             50 lv_out_cnt, 60 lv_in_cnt, 70 lv_mc_cnt.

    IF lv_out_cnt > 0 OR lv_in_cnt > 0 OR lv_mc_cnt > 0.
      WRITE: 80 '* exists' COLOR COL_TOTAL.
    ELSE.
      WRITE: 80 '  new' COLOR COL_POSITIVE.
    ENDIF.
  ENDLOOP.
  SKIP.

  " 8. Test mode — stop here
  IF p_test = abap_true.
    WRITE: / 'TEST MODE - no database changes were made.' COLOR COL_TOTAL.
    WRITE: / 'Uncheck "Test Mode" and re-run to apply changes.'.
    RETURN.
  ENDIF.

  " 9. Replace mode: delete existing entries for affected partners
  IF p_repl = abap_true.
    LOOP AT lt_pkeys INTO ls_pkey.
      DELETE FROM edpp1
        WHERE parnum = ls_pkey-rcvprn AND partyp = ls_pkey-rcvprt.
      DELETE FROM edp13
        WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
      DELETE FROM edp21
        WHERE sndprn = ls_pkey-rcvprn AND sndprt = ls_pkey-rcvprt.
      DELETE FROM edp12
        WHERE rcvprn = ls_pkey-rcvprn AND rcvprt = ls_pkey-rcvprt.
    ENDLOOP.
    WRITE: / 'Existing entries deleted for affected partners (Replace mode).' COLOR COL_TOTAL.
  ENDIF.

  " 10. Import partner profile headers
  IF ls_import-edpp1 IS NOT INITIAL.
    MODIFY edpp1 FROM TABLE ls_import-edpp1.
    IF sy-subrc = 0.
      WRITE: / 'Headers     (EDPP1) imported:' COLOR COL_POSITIVE, lines( ls_import-edpp1 ), 'entries.'.
    ELSE.
      WRITE: / 'Error importing partner profile headers.' COLOR COL_NEGATIVE.
    ENDIF.
  ENDIF.

  " 11. Import outbound parameters
  IF ls_import-edp13 IS NOT INITIAL.
    MODIFY edp13 FROM TABLE ls_import-edp13.
    IF sy-subrc = 0.
      WRITE: / 'Outbound    (EDP13) imported:' COLOR COL_POSITIVE, lines( ls_import-edp13 ), 'entries.'.
    ELSE.
      WRITE: / 'Error importing outbound parameters.' COLOR COL_NEGATIVE.
    ENDIF.
  ENDIF.

  " 12. Import inbound parameters
  IF ls_import-edp21 IS NOT INITIAL.
    MODIFY edp21 FROM TABLE ls_import-edp21.
    IF sy-subrc = 0.
      WRITE: / 'Inbound     (EDP21) imported:' COLOR COL_POSITIVE, lines( ls_import-edp21 ), 'entries.'.
    ELSE.
      WRITE: / 'Error importing inbound parameters.' COLOR COL_NEGATIVE.
    ENDIF.
  ENDIF.

  " 13. Import message control
  IF ls_import-edp12 IS NOT INITIAL.
    MODIFY edp12 FROM TABLE ls_import-edp12.
    IF sy-subrc = 0.
      WRITE: / 'Msg Control (EDP12) imported:' COLOR COL_POSITIVE, lines( ls_import-edp12 ), 'entries.'.
    ELSE.
      WRITE: / 'Error importing message control entries.' COLOR COL_NEGATIVE.
    ENDIF.
  ENDIF.

  COMMIT WORK AND WAIT.
  SKIP.
  WRITE: / 'Import completed successfully.' COLOR COL_POSITIVE.
ENDFORM.
