CLASS lhc_post DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS likePost FOR MODIFY
      IMPORTING keys FOR ACTION Post~likePost RESULT result.

ENDCLASS.

CLASS lhc_post IMPLEMENTATION.

  METHOD likePost.
    READ ENTITIES OF zi_12d_post IN LOCAL MODE
      ENTITY Post
      FIELDS ( Id )
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_posts).

    LOOP AT keys INTO DATA(ls_key).
      SELECT SINGLE id FROM z12d_posts WHERE id = @ls_key-Id INTO @DATA(lv_found_post_id).
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = ls_key-%tky ) TO failed-post.
        APPEND VALUE #(
          %tky = ls_key-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'post not found' )
        ) TO reported-post.
        CONTINUE.
      ENDIF.

      " Use passed UserId parameter
      DATA(lv_user_id) = ls_key-%param-UserId.

      SELECT SINGLE @abap_true FROM z12d_likes
        WHERE user_id = @lv_user_id AND post_id = @ls_key-Id
        INTO @DATA(lv_already_liked).

      IF lv_already_liked = abap_true.
        APPEND VALUE #(
          %tky   = ls_key-%tky
          %param = VALUE #( liked = abap_true already_liked = abap_true post_id = ls_key-Id )
        ) TO result.
      ELSE.
        GET TIME STAMP FIELD DATA(lv_now).
        INSERT z12d_likes FROM @( VALUE #(
          client     = sy-mandt
          user_id    = lv_user_id
          post_id    = ls_key-Id
          created_at = lv_now
        ) ).

        APPEND VALUE #(
          %tky   = ls_key-%tky
          %param = VALUE #( liked = abap_true already_liked = abap_false post_id = ls_key-Id )
        ) TO result.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


CLASS lsc_zi_12d_post DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.

    METHODS adjust_numbers REDEFINITION.

ENDCLASS.

CLASS lsc_zi_12d_post IMPLEMENTATION.

  METHOD adjust_numbers.
    IF mapped-post IS NOT INITIAL.
      CALL FUNCTION 'ENQUEUE_E_TABLE'
        EXPORTING
          mode_rstable   = 'E'
          tabname        = 'Z12D_POSTS'
          _wait          = abap_true
        EXCEPTIONS
          foreign_lock   = 1
          system_failure = 2
          OTHERS         = 3.

      SELECT MAX( id ) FROM z12d_posts INTO @DATA(lv_max_id).

      LOOP AT mapped-post ASSIGNING FIELD-SYMBOL(<ls_mapped_post>).
        IF <ls_mapped_post>-id IS INITIAL.
          lv_max_id += 1.
          <ls_mapped_post>-id = lv_max_id.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
