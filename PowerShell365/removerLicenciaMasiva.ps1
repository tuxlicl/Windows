# Conectarse a Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"

$usersList = Import-CSV -Path "E:\nombrearchivo.lcsv"
$e5Sku = Get-MgSubscribedSku -All | Where SkuPartNumber -eq 'NombreDeLaLicencia'
foreach($user in $usersList) {
  Set-MgUserLicense -UserId $user.UserPrincipalName -RemoveLicenses @($e5Sku.SkuId) -AddLicenses @{}
}