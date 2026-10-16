@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '12$ Challenge- Post Root Interface View'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZI_12D_POST
  as select from z12d_posts
  association [0..1] to ZI_12D_POST_LIKECOUNT as _LikeCount on $projection.Id = _LikeCount.PostId
  association [0..*] to ZI_12D_LIKE           as _Likes     on $projection.Id = _Likes.PostId
  association [0..1] to ZI_12D_USER           as _Author    on $projection.UserId = _Author.Id
{
  key id                                                       as Id,
      user_id                                                  as UserId,
      body                                                     as Body,
      @Semantics.systemDateTime.lastChangedAt: true
      created_at                                               as CreatedAt,
      _Author.Username                                         as Author,
      coalesce( _LikeCount.LikeCount, cast( 0 as abap.int8 ) ) as LikeCount,

      /* Associations */
      _Author,
      _Likes
}
