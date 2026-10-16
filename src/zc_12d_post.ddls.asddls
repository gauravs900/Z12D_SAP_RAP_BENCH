@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '12Dollar Challenge- Post Projection View'
@Metadata.allowExtensions: true
@Search.searchable: true
define root view entity ZC_12D_POST
  provider contract transactional_query
  as projection on ZI_12D_POST
{
  key Id,
      UserId,
      @Search.defaultSearchElement: true
      @Search.fuzzinessThreshold: 0.8
      Body,
      CreatedAt,
      Author,
      LikeCount,

      /* Associations */
      _Author,
      _Likes
}
