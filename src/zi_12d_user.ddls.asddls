@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '12-Dollar Challenge- User Interface View'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_12D_USER as select from z12d_users
{
    key id as Id,
    username as Username,
    @Semantics.systemDateTime.lastChangedAt: true
    created_at as CreatedAt
}
