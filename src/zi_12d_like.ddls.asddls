@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '12-Dollar Challenge- Like Interface View'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_12D_LIKE as select from z12d_likes
{
    key user_id as UserId,
    key post_id as PostId,
    @Semantics.systemDateTime.lastChangedAt: true
    created_at as CreatedAt
}
