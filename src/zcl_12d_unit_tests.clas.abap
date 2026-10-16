CLASS zcl_12d_unit_tests DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PUBLIC SECTION.

  PRIVATE SECTION.
    METHODS:
      setup,
      teardown,
      test_create_post_success FOR TESTING,
      test_like_action_first_time FOR TESTING,
      test_like_action_repeat FOR TESTING,
      test_read_post_projection FOR TESTING.
ENDCLASS.

CLASS zcl_12d_unit_tests IMPLEMENTATION.

  METHOD setup.
    " Ensure test user exists in Z12D_USERS
    SELECT SINGLE id FROM z12d_users WHERE username = @sy-uname INTO @DATA(lv_uid).
    IF sy-subrc <> 0.
      GET TIME STAMP FIELD DATA(lv_now).
      INSERT z12d_users FROM @( VALUE #(
        client     = sy-mandt
        id         = 99999
        username   = sy-uname
        created_at = lv_now
      ) ).
    ENDIF.
  ENDMETHOD.

  METHOD teardown.
    ROLLBACK ENTITIES.
  ENDMETHOD.

  METHOD test_create_post_success.
    " Create post via RAP EML
    MODIFY ENTITIES OF zi_12d_post
      ENTITY Post
      CREATE FIELDS ( Body )
      WITH VALUE #( ( %cid = 'CID_TEST_SUCCESS'
                      Body = 'Standard RAP Architecture Post Test' ) )
      MAPPED DATA(lt_mapped)
      FAILED DATA(lt_failed)
      REPORTED DATA(lt_reported).

    cl_abap_unit_assert=>assert_initial(
      act = lt_failed-post
      msg = 'Valid post creation via RAP EML should not fail'
    ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_mapped-post
      msg = 'Mapped table should contain the newly created post'
    ).

    COMMIT ENTITIES.

    " Read back the newly created post
    SELECT SINGLE id FROM z12d_posts
      WHERE body = 'Standard RAP Architecture Post Test'
      INTO @DATA(lv_new_id).

    READ ENTITIES OF zi_12d_post
      ENTITY Post
      FIELDS ( Id Body CreatedAt Author LikeCount )
      WITH VALUE #( ( %tky-Id = lv_new_id ) )
      RESULT DATA(lt_read_posts).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_read_posts
      msg = 'Should be able to read back created post'
    ).

    cl_abap_unit_assert=>assert_equals(
      exp = 'Standard RAP Architecture Post Test'
      act = lt_read_posts[ 1 ]-Body
      msg = 'Body must match created content'
    ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_read_posts[ 1 ]-CreatedAt
      msg = 'CreatedAt must be set automatically by RAP runtime via @Semantics.systemDateTime.lastChangedAt'
    ).
  ENDMETHOD.

  METHOD test_like_action_first_time.
    " Create a post to like
    DATA(lv_post_id) = CONV int8( 99991 ).
    DELETE FROM z12d_likes WHERE post_id = @lv_post_id.
    DELETE FROM z12d_posts WHERE id = @lv_post_id.
    GET TIME STAMP FIELD DATA(lv_now).
    INSERT z12d_posts FROM @( VALUE #( client = sy-mandt id = lv_post_id user_id = 99999 body = 'Post for like test' created_at = lv_now ) ).

    " Execute action likePost via EML with explicit UserId parameter
    MODIFY ENTITIES OF zi_12d_post
      ENTITY Post
      EXECUTE likePost
      FROM VALUE #( ( %tky-Id = lv_post_id
                      %param  = VALUE #( UserId = 99999 ) ) )
      RESULT DATA(lt_result)
      FAILED DATA(lt_failed)
      REPORTED DATA(lt_reported).

    cl_abap_unit_assert=>assert_initial( act = lt_failed-post msg = 'likePost action should not fail' ).
    cl_abap_unit_assert=>assert_not_initial( act = lt_result msg = 'likePost must return result' ).

    DATA(ls_res) = lt_result[ 1 ]-%param.
    cl_abap_unit_assert=>assert_true( act = ls_res-liked msg = 'Liked flag must be true' ).
    cl_abap_unit_assert=>assert_false( act = ls_res-already_liked msg = 'Already liked must be false on first like' ).
    cl_abap_unit_assert=>assert_equals( exp = lv_post_id act = ls_res-post_id msg = 'Post ID must match' ).
  ENDMETHOD.

  METHOD test_like_action_repeat.
    " Ensure post and existing like are present
    DATA(lv_post_id) = CONV int8( 99992 ).
    DELETE FROM z12d_likes WHERE post_id = @lv_post_id.
    DELETE FROM z12d_posts WHERE id = @lv_post_id.
    GET TIME STAMP FIELD DATA(lv_now).
    INSERT z12d_posts FROM @( VALUE #( client = sy-mandt id = lv_post_id user_id = 99999 body = 'Post for repeat like test' created_at = lv_now ) ).

    " First like with explicit UserId parameter
    MODIFY ENTITIES OF zi_12d_post
      ENTITY Post
      EXECUTE likePost
      FROM VALUE #( ( %tky-Id = lv_post_id
                      %param  = VALUE #( UserId = 99999 ) ) )
      RESULT DATA(lt_res1).

    " Second like (repeat) with explicit UserId parameter
    MODIFY ENTITIES OF zi_12d_post
      ENTITY Post
      EXECUTE likePost
      FROM VALUE #( ( %tky-Id = lv_post_id
                      %param  = VALUE #( UserId = 99999 ) ) )
      RESULT DATA(lt_res2).

    cl_abap_unit_assert=>assert_not_initial( act = lt_res2 msg = 'Repeat like must return result' ).
    DATA(ls_res) = lt_res2[ 1 ]-%param.
    cl_abap_unit_assert=>assert_true( act = ls_res-liked msg = 'Liked flag must be true' ).
    cl_abap_unit_assert=>assert_true( act = ls_res-already_liked msg = 'Already liked must be true on repeat like' ).
  ENDMETHOD.

  METHOD test_read_post_projection.
    " Read via Projection View ZC_12D_POST
    SELECT id, body, created_at, author, like_count
      FROM zc_12d_post
      ORDER BY created_at DESC, id DESC
      INTO TABLE @DATA(lt_posts)
      UP TO 20 ROWS.

    cl_abap_unit_assert=>assert_subrc( exp = 0 msg = 'Selecting from ZC_12D_POST should succeed' ).
  ENDMETHOD.

ENDCLASS.

