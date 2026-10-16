@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '12-Dollar Challenge- Like Count per Post'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_12D_POST_LIKECOUNT
  as select from z12d_likes
{
  key post_id  as PostId,
      count(*) as LikeCount
}
group by
  post_id
