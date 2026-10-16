CLASS zcl_12d_seed_data_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
    INTERFACES if_abap_parallel.
    INTERFACES if_serializable_object.

    CLASS-DATA:
      gv_users_count TYPE i VALUE 50000,
      gv_posts_count TYPE i VALUE 500000,
      gv_likes_count TYPE i VALUE 2000000,
      gv_batch_size  TYPE i VALUE 25000.

    DATA:
      mv_quarter TYPE i,
      mv_likes   TYPE i.

    METHODS constructor
      IMPORTING
        iv_quarter TYPE i DEFAULT 0.

    CLASS-METHODS:
      run_quarter
        IMPORTING
          io_out     TYPE REF TO if_oo_adt_classrun_out OPTIONAL
          iv_quarter TYPE i
          iv_clear   TYPE abap_bool DEFAULT abap_true
        EXPORTING
          ev_likes   TYPE i.

  PRIVATE SECTION.
    TYPES:
      tt_int8   TYPE STANDARD TABLE OF int8 WITH EMPTY KEY,
      tt_i      TYPE STANDARD TABLE OF i WITH EMPTY KEY,
      tt_string TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    CONSTANTS:
      co_2_to_32     TYPE int8 VALUE 4294967296,
      co_2_to_32_dec TYPE decfloat34 VALUE '4294967296.0',
      co_end_ms      TYPE int8 VALUE 1767225600000,
      co_day_ms      TYPE int8 VALUE 86400000.

    CLASS-DATA:
      gv_a               TYPE int8 VALUE 42,
      gt_post_created_at TYPE tt_int8.

    CLASS-METHODS:
      rand
        RETURNING
          VALUE(rv_val) TYPE decfloat34,

      rand_int
        IMPORTING
          iv_lo         TYPE i
          iv_hi         TYPE i
        RETURNING
          VALUE(rv_val) TYPE i,

      pick
        IMPORTING
          it_arr        TYPE tt_string
        RETURNING
          VALUE(rv_val) TYPE string,

      expo
        IMPORTING
          iv_mean       TYPE decfloat34
        RETURNING
          VALUE(rv_val) TYPE decfloat34,

      sentence
        IMPORTING
          it_words      TYPE tt_string
          it_punct      TYPE tt_string
        RETURNING
          VALUE(rv_val) TYPE string,

      post_body
        IMPORTING
          it_openers    TYPE tt_string
          it_words      TYPE tt_string
          it_punct      TYPE tt_string
        RETURNING
          VALUE(rv_val) TYPE string,

      ms_to_timestamp
        IMPORTING
          iv_ms        TYPE int8
        RETURNING
          VALUE(rv_ts) TYPE abp_lastchange_tstmpl,

      init_arrays
        EXPORTING
          et_adj   TYPE tt_string
          et_noun  TYPE tt_string
          et_open  TYPE tt_string
          et_words TYPE tt_string
          et_punct TYPE tt_string,

      generate_users
        IMPORTING
          io_out TYPE REF TO if_oo_adt_classrun_out OPTIONAL,

      generate_posts_chunk
        IMPORTING
          io_out  TYPE REF TO if_oo_adt_classrun_out OPTIONAL
          iv_from TYPE i
          iv_to   TYPE i
          iv_seed TYPE int8,

      generate_likes_chunk
        IMPORTING
          io_out    TYPE REF TO if_oo_adt_classrun_out OPTIONAL
          iv_from   TYPE i
          iv_to     TYPE i
          iv_seed_a TYPE int8
          iv_seed_b TYPE int8
        EXPORTING
          ev_likes  TYPE i.

ENDCLASS.



CLASS zcl_12d_seed_data_loader IMPLEMENTATION.

  METHOD constructor.
    mv_quarter = iv_quarter.
  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.
    out->write( '=== 12-Dollar Challenge: Seed Data Generator (CL_ABAP_PARALLEL) ===' ).
    GET TIME STAMP FIELD DATA(lv_start_ts).

    out->write( 'Clearing all database tables...' ).
    DELETE FROM z12d_likes.
    DELETE FROM z12d_posts.
    DELETE FROM z12d_users.
    COMMIT WORK.
    out->write( 'Database tables cleared successfully.' ).

    DATA lt_tasks TYPE cl_abap_parallel=>t_in_inst_tab.
    lt_tasks = VALUE #(
      ( NEW zcl_12d_seed_data_loader( iv_quarter = 1 ) )
      ( NEW zcl_12d_seed_data_loader( iv_quarter = 2 ) )
      ( NEW zcl_12d_seed_data_loader( iv_quarter = 3 ) )
      ( NEW zcl_12d_seed_data_loader( iv_quarter = 4 ) )
    ).

    out->write( 'Spawning 4 Parallel Workers via CL_ABAP_PARALLEL...' ).

    TRY.
        NEW cl_abap_parallel( p_num_tasks = 4 )->run_inst(
          EXPORTING
            p_in_tab  = lt_tasks
          IMPORTING
            p_out_tab = DATA(lt_results)
        ).

        LOOP AT lt_results ASSIGNING FIELD-SYMBOL(<ls_res>).
          IF <ls_res>-inst IS INITIAL.
            out->write( |  [✗] Worker { sy-tabix } failed: { <ls_res>-message }| ).
          ELSE.
            DATA(lo_worker) = CAST zcl_12d_seed_data_loader( <ls_res>-inst ).
            out->write( |  [✓] Quarter { lo_worker->mv_quarter } complete ({ lo_worker->mv_likes } likes).| ).
          ENDIF.
        ENDLOOP.

      CATCH cx_root INTO DATA(lx_parallel).
        out->write( |CL_ABAP_PARALLEL error: { lx_parallel->get_text( ) }| ).
        out->write( 'Running sequential fallback...' ).
        run_quarter( io_out = out iv_quarter = 1 iv_clear = abap_false ).
        run_quarter( io_out = out iv_quarter = 2 iv_clear = abap_false ).
        run_quarter( io_out = out iv_quarter = 3 iv_clear = abap_false ).
        run_quarter( io_out = out iv_quarter = 4 iv_clear = abap_false ).
    ENDTRY.

    GET TIME STAMP FIELD DATA(lv_end_ts).
    DATA(lv_diff) = CONV i( lv_end_ts - lv_start_ts ).
    out->write( |=== All 4 Parallel Workers Finished in { lv_diff } seconds ===| ).
    out->write( 'You can now run SAP/test/test.sh or SAP/K6_LOAD_TEST.js!' ).
  ENDMETHOD.


  METHOD if_abap_parallel~do.
    TRY.
        run_quarter(
          EXPORTING
            iv_quarter = mv_quarter
            iv_clear   = abap_false
          IMPORTING
            ev_likes   = mv_likes
        ).
      CATCH cx_root.
        " Avoid unhandled short dump in worker work process
    ENDTRY.
  ENDMETHOD.


  METHOD run_quarter.
    DATA: lv_from   TYPE i,
          lv_to     TYPE i,
          lv_seed_p TYPE int8,
          lv_seed_a TYPE int8,
          lv_seed_b TYPE int8.

    GET TIME STAMP FIELD DATA(lv_start_ts).
    IF io_out IS BOUND.
      io_out->write( |--- Starting Quarter { iv_quarter } / 4 ---| ).
    ENDIF.

    CASE iv_quarter.
      WHEN 1.
        lv_from   = 1.
        lv_to     = 125000.
        lv_seed_p = 2993894106.
        lv_seed_a = 1195910855.
        lv_seed_b = 3975335431.

        IF iv_clear = abap_true.
          DELETE FROM z12d_users.
          DELETE FROM z12d_posts WHERE id <= 125000.
          DELETE FROM z12d_likes WHERE post_id <= 125000.
          COMMIT WORK.
        ENDIF.

        generate_users( io_out = io_out ).

      WHEN 2.
        lv_from   = 125001.
        lv_to     = 250000.
        lv_seed_p = 946865081.
        lv_seed_a = 1890766999.
        lv_seed_b = 3214022539.

        IF iv_clear = abap_true.
          DELETE FROM z12d_posts WHERE id > 125000 AND id <= 250000.
          DELETE FROM z12d_likes WHERE post_id > 125000 AND post_id <= 250000.
          COMMIT WORK.
        ENDIF.

      WHEN 3.
        lv_from   = 250001.
        lv_to     = 375000.
        lv_seed_p = 2371730770.
        lv_seed_a = 2585623143.
        lv_seed_b = 1414756547.

        IF iv_clear = abap_true.
          DELETE FROM z12d_posts WHERE id > 250000 AND id <= 375000.
          DELETE FROM z12d_likes WHERE post_id > 250000 AND post_id <= 375000.
          COMMIT WORK.
        ENDIF.

      WHEN 4.
        lv_from   = 375001.
        lv_to     = 500000.
        lv_seed_p = 3415693395.
        lv_seed_a = 3280479287.
        lv_seed_b = 2877147656.

        IF iv_clear = abap_true.
          DELETE FROM z12d_posts WHERE id > 375000.
          DELETE FROM z12d_likes WHERE post_id > 375000.
          COMMIT WORK.
        ENDIF.

      WHEN OTHERS.
        IF io_out IS BOUND.
          io_out->write( |Invalid quarter: { iv_quarter }. Must be 1, 2, 3, or 4.| ).
        ENDIF.
        RETURN.
    ENDCASE.

    CLEAR gt_post_created_at.
    generate_posts_chunk(
      io_out  = io_out
      iv_from = lv_from
      iv_to   = lv_to
      iv_seed = lv_seed_p
    ).

    generate_likes_chunk(
      EXPORTING
        io_out    = io_out
        iv_from   = lv_from
        iv_to     = lv_to
        iv_seed_a = lv_seed_a
        iv_seed_b = lv_seed_b
      IMPORTING
        ev_likes  = ev_likes
    ).

    FREE gt_post_created_at.

    GET TIME STAMP FIELD DATA(lv_end_ts).
    DATA(lv_diff) = CONV i( lv_end_ts - lv_start_ts ).
    IF io_out IS BOUND.
      io_out->write( |--- Quarter { iv_quarter } Complete in { lv_diff } seconds ---| ).
    ENDIF.
  ENDMETHOD.


  METHOD rand.
    " Fully inlined mulberry32 PRNG (0 sub-method calls for maximum speed)
    DATA: lv_xa TYPE x LENGTH 8,
          lv_xb TYPE x LENGTH 8,
          lv_xr TYPE x LENGTH 8.

    DATA: lv_a_hi TYPE int8,
          lv_a_lo TYPE int8,
          lv_b_hi TYPE int8,
          lv_b_lo TYPE int8,
          lv_mid  TYPE int8,
          lv_lo   TYPE int8.

    gv_a = ( gv_a + 1831565813 ) MOD co_2_to_32.
    DATA(lv_t) = gv_a.

    " Step 1: t = Math.imul(t ^ (t >>> 15), t | 1)
    lv_xa = lv_t.
    lv_xb = lv_t DIV 32768.
    lv_xr = lv_xa BIT-XOR lv_xb.
    DATA(lv_t1) = CONV int8( lv_xr ).

    lv_xb = 1.
    lv_xr = lv_xa BIT-OR lv_xb.
    DATA(lv_t2) = CONV int8( lv_xr ).

    lv_a_hi = lv_t1 DIV 65536.
    lv_a_lo = lv_t1 MOD 65536.
    lv_b_hi = lv_t2 DIV 65536.
    lv_b_lo = lv_t2 MOD 65536.
    lv_mid  = ( ( ( lv_a_hi * lv_b_lo ) + ( lv_a_lo * lv_b_hi ) ) MOD 65536 ) * 65536.
    lv_lo   = lv_a_lo * lv_b_lo.
    lv_t    = ( lv_mid + lv_lo ) MOD co_2_to_32.

    " Step 2: t ^= (t + Math.imul(t ^ (t >>> 7), t | 61)) >>> 0
    lv_xa = lv_t.
    lv_xb = lv_t DIV 128.
    lv_xr = lv_xa BIT-XOR lv_xb.
    DATA(lv_u1) = CONV int8( lv_xr ).

    lv_xb = 61.
    lv_xr = lv_xa BIT-OR lv_xb.
    DATA(lv_u2) = CONV int8( lv_xr ).

    lv_a_hi = lv_u1 DIV 65536.
    lv_a_lo = lv_u1 MOD 65536.
    lv_b_hi = lv_u2 DIV 65536.
    lv_b_lo = lv_u2 MOD 65536.
    lv_mid  = ( ( ( lv_a_hi * lv_b_lo ) + ( lv_a_lo * lv_b_hi ) ) MOD 65536 ) * 65536.
    lv_lo   = lv_a_lo * lv_b_lo.
    DATA(lv_term) = ( lv_t + ( ( lv_mid + lv_lo ) MOD co_2_to_32 ) ) MOD co_2_to_32.

    lv_xa = lv_t.
    lv_xb = lv_term.
    lv_xr = lv_xa BIT-XOR lv_xb.
    lv_t  = CONV int8( lv_xr ).

    " Step 3: res = (t ^ (t >>> 14)) >>> 0
    lv_xa = lv_t.
    lv_xb = lv_t DIV 16384.
    lv_xr = lv_xa BIT-XOR lv_xb.
    DATA(lv_res) = CONV int8( lv_xr ).

    rv_val = CONV decfloat34( lv_res ) / co_2_to_32_dec.
  ENDMETHOD.


  METHOD rand_int.
    DATA(lv_range) = CONV decfloat34( iv_hi - iv_lo + 1 ).
    DATA(lv_r)     = rand( ).
    rv_val = iv_lo + floor( lv_r * lv_range ).
  ENDMETHOD.


  METHOD pick.
    DATA(lv_idx) = 1 + floor( rand( ) * lines( it_arr ) ).
    rv_val = it_arr[ lv_idx ].
  ENDMETHOD.


  METHOD expo.
    DATA(lv_r)   = rand( ).
    DATA(lv_arg) = 1 - lv_r.
    IF lv_arg <= 0.
      lv_arg = '0.0000000001'.
    ENDIF.
    rv_val = -1 * iv_mean * log( lv_arg ).
  ENDMETHOD.


  METHOD sentence.
    DATA(lv_n)     = rand_int( iv_lo = 4 iv_hi = 14 ).
    DATA(lv_word)  = pick( it_words ).
    DATA(lv_first) = to_upper( lv_word(1) ).
    DATA(lv_rest)  = lv_word+1.
    DATA(lv_s)     = |{ lv_first }{ lv_rest }|.

    DO lv_n - 1 TIMES.
      lv_s = |{ lv_s } { pick( it_words ) }|.
    ENDDO.

    rv_val = |{ lv_s }{ pick( it_punct ) }|.
  ENDMETHOD.


  METHOD post_body.
    DATA: lv_body TYPE string.

    IF rand( ) < '0.25'.
      lv_body = pick( it_openers ).
    ENDIF.

    DATA(lv_sentences) = rand_int( iv_lo = 1 iv_hi = 3 ).
    DO lv_sentences TIMES.
      IF lv_body IS INITIAL.
        lv_body = sentence( it_words = it_words it_punct = it_punct ).
      ELSE.
        lv_body = |{ lv_body } { sentence( it_words = it_words it_punct = it_punct ) }|.
      ENDIF.
    ENDDO.

    IF strlen( lv_body ) > 500.
      lv_body = |{ lv_body(497) }...|.
    ENDIF.

    rv_val = lv_body.
  ENDMETHOD.


  METHOD ms_to_timestamp.
    DATA: lv_date TYPE d VALUE '19700101',
          lv_time TYPE t.

    DATA(lv_sec)    = iv_ms DIV 1000.
    DATA(lv_rem_ms) = iv_ms MOD 1000.

    DATA(lv_days)     = CONV i( lv_sec DIV 86400 ).
    DATA(lv_time_sec) = CONV i( lv_sec MOD 86400 ).

    lv_date = lv_date + lv_days.
    lv_time = lv_time_sec.

    DATA(lv_ms3) = |{ lv_rem_ms WIDTH = 3 ALIGN = RIGHT PAD = '0' }|.

    rv_ts = CONV timestampl( |{ lv_date }{ lv_time }.{ lv_ms3 }| ).
  ENDMETHOD.


  METHOD init_arrays.
    et_adj = VALUE #(
      ( `quiet` ) ( `brave` ) ( `clever` ) ( `sunny` ) ( `rusty` )
      ( `swift` ) ( `lazy` ) ( `mellow` ) ( `sharp` ) ( `wild` )
      ( `cosmic` ) ( `tiny` ) ( `golden` ) ( `silver` ) ( `happy` )
      ( `grumpy` ) ( `curious` ) ( `lucky` ) ( `salty` ) ( `zesty` )
    ).

    et_noun = VALUE #(
      ( `otter` ) ( `falcon` ) ( `badger` ) ( `comet` ) ( `river` )
      ( `maple` ) ( `pixel` ) ( `walrus` ) ( `ember` ) ( `glacier` )
      ( `lantern` ) ( `meadow` ) ( `nebula` ) ( `orchid` ) ( `pebble` )
      ( `quartz` ) ( `raven` ) ( `sparrow` ) ( `thistle` ) ( `willow` )
    ).

    et_open = VALUE #(
      ( `Hot take:` ) ( `TIL` ) ( `Unpopular opinion:` ) ( `Note to self:` ) ( `PSA:` )
      ( `Okay so` ) ( `Update:` ) ( `Honestly,` ) ( `Reminder:` ) ( `Question:` )
    ).

    et_punct = VALUE #(
      ( `.` ) ( `.` ) ( `.` ) ( `!` ) ( `?` ) ( `...` )
    ).

    DATA(lv_words_str) =
      `the a an and but or so because while after before just really very kind of sort of maybe probably definitely ` &&
      `server database request latency cache index query benchmark droplet cpu memory disk network throughput users ` &&
      `coffee morning weekend project deploy release bug feature test rewrite refactor commit branch merge review ` &&
      `thinking building shipping learning reading writing debugging measuring watching waiting running walking ` &&
      `fast slow small big cheap simple boring clever weird surprising honest careful lucky tired ready done broken ` &&
      `today tonight tomorrow yesterday again finally never always sometimes usually rarely once twice ` &&
      `this that these those here there everywhere nowhere something nothing everything anything someone ` &&
      `nginx node postgres typescript express linux ubuntu systemd load steal swap kernel socket keepalive pool`.

    SPLIT lv_words_str AT ` ` INTO TABLE et_words.
    DELETE et_words WHERE table_line IS INITIAL.
  ENDMETHOD.


  METHOD generate_users.
    DATA: lt_batch TYPE STANDARD TABLE OF z12d_users WITH EMPTY KEY.

    IF io_out IS BOUND.
      io_out->write( 'Generating 50,000 Users...' ).
    ENDIF.

    init_arrays(
      IMPORTING
        et_adj   = DATA(lt_adj)
        et_noun  = DATA(lt_noun)
        et_open  = DATA(lt_open)
        et_words = DATA(lt_words)
        et_punct = DATA(lt_punct)
    ).

    gv_a = 42.

    DATA(lv_base) = co_end_ms - ( 730 * co_day_ms ).
    DATA(lv_span) = CONV decfloat34( 365 * co_day_ms ).

    DO gv_users_count TIMES.
      DATA(lv_id) = CONV int8( sy-index ).
      DATA(lv_user) = |{ pick( lt_adj ) }_{ pick( lt_noun ) }_{ lv_id }|.
      DATA(lv_r) = rand( ).
      DATA(lv_ms) = lv_base + CONV int8( floor( lv_r * lv_span ) ).

      APPEND VALUE #(
        client     = sy-mandt
        id         = lv_id
        username   = lv_user
        created_at = ms_to_timestamp( lv_ms )
      ) TO lt_batch.

      IF lines( lt_batch ) >= gv_batch_size.
        INSERT z12d_users FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
        COMMIT WORK.
        CLEAR lt_batch.
      ENDIF.
    ENDDO.

    IF lt_batch IS NOT INITIAL.
      INSERT z12d_users FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
      COMMIT WORK.
      CLEAR lt_batch.
    ENDIF.

    IF io_out IS BOUND.
      io_out->write( |  -> { gv_users_count } Users inserted successfully.| ).
    ENDIF.
  ENDMETHOD.


  METHOD generate_posts_chunk.
    DATA: lt_batch TYPE STANDARD TABLE OF z12d_posts WITH EMPTY KEY.

    IF io_out IS BOUND.
      io_out->write( |Generating Posts { iv_from } to { iv_to }...| ).
    ENDIF.

    init_arrays(
      IMPORTING
        et_adj   = DATA(lt_adj)
        et_noun  = DATA(lt_noun)
        et_open  = DATA(lt_open)
        et_words = DATA(lt_words)
        et_punct = DATA(lt_punct)
    ).

    gv_a = iv_seed.

    DATA(lv_post_start) = co_end_ms - ( 365 * co_day_ms ).
    DATA(lv_step)       = CONV decfloat34( 365 * co_day_ms ) / gv_posts_count.

    DATA(lv_count) = iv_to - iv_from + 1.

    DO lv_count TIMES.
      DATA(lv_local_idx) = sy-index - 1.
      DATA(lv_post_id)   = iv_from + lv_local_idx.
      DATA(lv_global_idx) = lv_post_id - 1.

      DATA(lv_r1) = rand( ).
      DATA(lv_r2) = rand( ).
      DATA(lv_user_id) = CONV int8( 1 + floor( gv_users_count * lv_r1 * lv_r2 ) ).

      DATA(lv_r3) = rand( ).
      DATA(lv_created_ms) = CONV int8( floor( lv_post_start + ( lv_global_idx * lv_step ) + ( lv_r3 * lv_step * '0.9' ) ) ).
      APPEND lv_created_ms TO gt_post_created_at.

      DATA(lv_body) = post_body(
        it_openers = lt_open
        it_words   = lt_words
        it_punct   = lt_punct
      ).

      APPEND VALUE #(
        client     = sy-mandt
        id         = CONV int8( lv_post_id )
        user_id    = lv_user_id
        body       = lv_body
        created_at = ms_to_timestamp( lv_created_ms )
      ) TO lt_batch.

      IF lines( lt_batch ) >= gv_batch_size.
        INSERT z12d_posts FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
        COMMIT WORK.
        CLEAR lt_batch.
        IF io_out IS BOUND AND lv_post_id MOD 50000 = 0.
          io_out->write( |  -> { lv_post_id } posts generated...| ).
        ENDIF.
      ENDIF.
    ENDDO.

    IF lt_batch IS NOT INITIAL.
      INSERT z12d_posts FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
      COMMIT WORK.
      CLEAR lt_batch.
    ENDIF.

    IF io_out IS BOUND.
      io_out->write( |  -> Posts { iv_from } to { iv_to } inserted successfully.| ).
    ENDIF.
  ENDMETHOD.


  METHOD generate_likes_chunk.
    DATA: lt_batch    TYPE STANDARD TABLE OF z12d_likes WITH EMPTY KEY,
          lt_per_post TYPE STANDARD TABLE OF i WITH EMPTY KEY,
          lt_seen     TYPE STANDARD TABLE OF i WITH EMPTY KEY.

    DATA(lv_count) = iv_to - iv_from + 1.
    IF io_out IS BOUND.
      io_out->write( |Generating Likes for posts { iv_from } to { iv_to }...| ).
    ENDIF.

    gv_a = iv_seed_a.

    DATA(lv_mean_per_post) = CONV decfloat34( gv_likes_count ) / gv_posts_count.
    DATA(lv_popular_mean)  = lv_mean_per_post * 20.
    DATA(lv_normal_mean)   = ( lv_mean_per_post - '0.01' * lv_popular_mean + '0.5' ) / '0.99'.
    DATA(lv_cap)           = 800.

    " Phase A: Determine like count for this quarter
    DO lv_count TIMES.
      DATA(lv_is_pop) = COND decfloat34( WHEN rand( ) < '0.01' THEN lv_popular_mean ELSE lv_normal_mean ).
      DATA(lv_cnt)    = floor( expo( lv_is_pop ) ).
      IF lv_cnt > lv_cap.
        lv_cnt = lv_cap.
      ENDIF.
      APPEND lv_cnt TO lt_per_post.
    ENDDO.

    gv_a = iv_seed_b.

    DATA(lv_seven_days)  = CONV decfloat34( 7 * co_day_ms ).
    DATA(lv_total_likes) = 0.

    " Phase B: Generate likes
    DO lv_count TIMES.
      DATA(lv_local_idx) = sy-index.
      DATA(lv_post_id)   = iv_from + lv_local_idx - 1.
      DATA(lv_likes_cnt) = lt_per_post[ lv_local_idx ].
      IF lv_likes_cnt <= 0.
        CONTINUE.
      ENDIF.

      DATA(lv_base_ms) = gt_post_created_at[ lv_local_idx ].
      CLEAR lt_seen.

      DO lv_likes_cnt TIMES.
        DATA(lv_uid) = rand_int( iv_lo = 1 iv_hi = gv_users_count ).
        WHILE line_exists( lt_seen[ table_line = lv_uid ] ).
          lv_uid = rand_int( iv_lo = 1 iv_hi = gv_users_count ).
        ENDWHILE.
        APPEND lv_uid TO lt_seen.

        DATA(lv_like_ms) = lv_base_ms + CONV int8( floor( rand( ) * lv_seven_days ) ).

        APPEND VALUE #(
          client     = sy-mandt
          user_id    = CONV int8( lv_uid )
          post_id    = CONV int8( lv_post_id )
          created_at = ms_to_timestamp( lv_like_ms )
        ) TO lt_batch.

        lv_total_likes += 1.

        IF lines( lt_batch ) >= gv_batch_size.
          INSERT z12d_likes FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
          COMMIT WORK.
          CLEAR lt_batch.
          IF io_out IS BOUND AND lv_total_likes MOD 100000 = 0.
            io_out->write( |  -> { lv_total_likes } likes generated...| ).
          ENDIF.
        ENDIF.
      ENDDO.
    ENDDO.

    IF lt_batch IS NOT INITIAL.
      INSERT z12d_likes FROM TABLE @lt_batch ACCEPTING DUPLICATE KEYS.
      COMMIT WORK.
      CLEAR lt_batch.
    ENDIF.

    ev_likes = lv_total_likes.
    IF io_out IS BOUND.
      io_out->write( |  -> { lv_total_likes } Likes inserted for quarter.| ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.

