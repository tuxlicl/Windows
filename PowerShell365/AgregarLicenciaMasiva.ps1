# Conectarse a Microsoft Graph
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All"

#es importante crear un archivo .csv con los siguientes encabezados "UserPrincipalName,LicenseSkuId" y guardarlo en la ruta E:\nombrearchivo.csv

# Importar usuarios desde CSV
$usuarios = Import-Csv -Path "E:\nombrearchivo.csv"

foreach ($usuario in $usuarios) {
    try {
        Write-Host "Asignando licencia a $($usuario.UserPrincipalName)..."

        Set-MgUserLicense -UserId $usuario.UserPrincipalName `
            -AddLicenses @{SkuId = $usuario.LicenseSkuId} `
            -RemoveLicenses @()

        Write-Host "✅ Licencia asignada a $($usuario.UserPrincipalName)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error al asignar licencia a $($usuario.UserPrincipalName): $_" -ForegroundColor Red
    }
}