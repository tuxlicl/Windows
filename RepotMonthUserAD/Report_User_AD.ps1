#Script para generar remporte mensual de cuentas den AD scada, este script tiene una mejora significativa ya que dentro de los campos que 
#entrega, se agrego la fecha de expiración de la password y de los grupos AD que tiene asociado, lo que permite una mejora auditoría del mismo
#Modificado el 03-09-2024 por Claudio Aliste R. Ingeniero de Infraestructura TI

$RemoteDir = "C:\" #unidad en donde se guardara el reporte
$csv = "C:\AD_SCADA_Reportes\Reporte_Mensual_SCADA\Reporte_AD_SCADA_$(get-date -f dd-MM-yyyy).csv" #ruta y formanto en el cual se guardara el reporte.
Set-Content $csv -Value "Type,Base,Status"
$data = Import-Csv $csv

get-aduser -Filter * -Properties Name, SamAccountName, UserPrincipalName, Description, Office, Homepage, Enabled, Created, PasswordLastSet, LastLogonDate, AccountExpirationDate, PasswordNeverExpires, MemberOf, msDS-UserPasswordExpiryTimeComputed |
Select-Object Name, SamAccountName, UserPrincipalName, Description, Office, Homepage, Enabled,
@{Name='Created';Expression={$_.Created.ToString("dd\/MM\/yyyy HH:mm")}},
@{Name='PasswordLastSet';Expression={$_.PasswordLastSet.ToString("dd\/MM\/yyyy HH:mm")}},
@{Name='LastLogonDate';Expression={$_.LastLogonDate.ToString("dd\/MM\/yyyy HH:mm")}},
@{Name='AccountExpirationDate';Expression={$_.AccountExpirationDate.ToString("dd\/MM\/yyyy HH:mm")}},
@{Name='PasswordExpiryDate';Expression={if($_.PasswordNeverExpires -eq $false) { [datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed").ToString("dd\/MM\/yyyy HH:mm") } else { "Never Expires" }}},
@{Name='Groups';Expression={
    if ($_.MemberOf) {
        $_.MemberOf | ForEach-Object {
            ($_ -split ',')[0] -replace '^CN=', ''
        }
    } else {
        "No Groups"
    }
}},
PasswordNeverExpires | 
Export-Csv $csv -Encoding UTF8 -NoTypeInformation

Copy-Item $csv $RemoteDir