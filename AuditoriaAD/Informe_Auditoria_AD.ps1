#
# Autor              : Claudio Aliste Requena
# Email              : aliste.claudio@gmail.com
# Fecha creación     : 01/03/2023
# Fecha modificación : 03/09/2024
# Propósito          : Generar informe de AD entregando la siguiente informacón, Nombre de personas, usuarios, correo, Descripcion, área, Estado de cuenta, Cuando cambio la contraseña, ultimo login en AD, 
#                       Cuando expira la cuenta, valida si el campo "contraseña nunca expira" esta activo, Grupos asociado a cada usuario, Grupos Creados en el AD, GPO creadas en el AD, GPO asociadas a grupos en el AD, configuración de cada GPO
# Versión            : 1.0
# ***** DISCLAIMER ******: En caso de hacerle una mejora, informar para tener el script actualizado
# ***** DISCLAIMER 2 *****: No me hago responsable del mal uso de este script, es de uso netamente interno y para auditar cuentas y configuracioens en un entorno de Active Directory.

# Definir rutas para los archivos de salida
$reportPath = "C:\AD_Audit\AD_Audit_Report.html"
$currentDateTime = Get-Date -Format "dd/MM/yyyy HH:mm:ss"

Write-Host "Iniciando el proceso de auditoría..." -ForegroundColor Green

# Crear el directorio si no existe
if (-not (Test-Path -Path "C:\AD_Audit")) {
    Write-Host "Creando directorio C:\AD_Audit..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path "C:\AD_Audit"
} else {
    Write-Host "El directorio C:\AD_Audit ya existe." -ForegroundColor Yellow
}

# Listar todos los grupos existentes en Active Directory
Write-Host "Obteniendo todos los grupos de Active Directory..." -ForegroundColor Yellow
$groups = Get-ADGroup -Filter * | Select-Object Name, SamAccountName, GroupScope, Description

# Listar todos los usuarios y los grupos a los que pertenecen, incluyendo detalles adicionales
Write-Host "Obteniendo todos los usuarios y sus grupos asociados de Active Directory..." -ForegroundColor Yellow
$users = Get-ADUser -Filter * -Properties DisplayName, EmailAddress, MemberOf, SamAccountName, UserPrincipalName, Description, Office, Homepage, Enabled, Created, PasswordLastSet, LastLogonDate, AccountExpirationDate, PasswordNeverExpires | 
Select-Object DisplayName, SamAccountName, UserPrincipalName, Description, Office, Homepage, Enabled,
@{Name='Created';Expression={$_.Created.ToString("dd/MM/yyyy HH:mm")}},
@{Name='PasswordLastSet';Expression={$_.PasswordLastSet.ToString("dd/MM/yyyy HH:mm")}},
@{Name='LastLogonDate';Expression={$_.LastLogonDate.ToString("dd/MM/yyyy HH:mm")}},
@{Name='AccountExpirationDate';Expression={$_.AccountExpirationDate.ToString("dd/MM/yyyy HH:mm")}},
@{Name="Groups";Expression={$_.MemberOf -replace '^CN=([^,]+).+$','$1' -join ', '}}

# Obtener la lista de GPOs y la relación de GPOs con las OUs
try {
    Write-Host "Obteniendo todas las GPOs y la relación con las OUs en Active Directory..." -ForegroundColor Yellow
    $gpos = Get-GPO -All | Select-Object DisplayName, Owner, CreatedTime, ModifiedTime
    $ouGPOs = Get-ADOrganizationalUnit -Filter * | ForEach-Object {
        $ouName = $_.Name
        Write-Host "Obteniendo GPOs aplicadas a la OU $ouName..." -ForegroundColor Cyan
        $linkedGPOs = Get-GPInheritance -Target $_.DistinguishedName | Select-Object -ExpandProperty GpoLinks | Select-Object DisplayName, Enforced
        [PSCustomObject]@{
            OUName = $ouName
            GPOs = $linkedGPOs.DisplayName -join ", "
        }
    }
    # Obtener el detalle de configuración de cada GPO
    Write-Host "Obteniendo detalles de configuración de cada GPO..." -ForegroundColor Yellow
    $gpoDetails = foreach ($gpo in $gpos) {
        Write-Host "Generando reporte de la GPO: $($gpo.DisplayName)..." -ForegroundColor Cyan
        Get-GPOReport -Name $gpo.DisplayName -ReportType Html | Out-String
    }
} catch {
    Write-Host "Error al obtener detalles de las GPOs." -ForegroundColor Red
    $gpos = @()
    $ouGPOs = @()
    $gpoDetails = "No se pudieron obtener los detalles de las GPOs. Es posible que los cmdlets relacionados con GPO no estén disponibles."
}

# Generar el reporte en formato HTML
Write-Host "Generando el reporte en formato HTML..." -ForegroundColor Yellow
$reportContent = @"
<html>
<head>
    <title>Auditoría Interna de Active Directory-Usuarios-Grupos-GPO</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #2E8B57; text-align: center; }
        h2 { color: #2E8B57; page-break-before: always; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        table, th, td { border: 1px solid #ddd; }
        th, td { padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        footer { text-align: center; color: #808080; font-size: 12px; margin-top: 20px; }
        .page-number { text-align: right; color: #808080; font-size: 12px; }
    </style>
</head>
<body>
    <h1>Auditoría Interna de Active Directory-Usuarios-Grupos-GPO</h1>

    <h2>1. Usuarios en Active Directory</h2>
    <div class="page-number">Página 1</div>
    <table>
        <tr><th>Nombre</th><th>SamAccountName</th><th>UserPrincipalName</th><th>Descripción</th><th>Office</th><th>Homepage</th><th>Enabled</th><th>Created</th><th>PasswordLastSet</th><th>LastLogonDate</th><th>AccountExpirationDate</th><th>Grupos</th></tr>
"@
$users | ForEach-Object {
    $reportContent += "<tr><td>$($_.DisplayName)</td><td>$($_.SamAccountName)</td><td>$($_.UserPrincipalName)</td><td>$($_.Description)</td><td>$($_.Office)</td><td>$($_.Homepage)</td><td>$($_.Enabled)</td><td>$($_.Created)</td><td>$($_.PasswordLastSet)</td><td>$($_.LastLogonDate)</td><td>$($_.AccountExpirationDate)</td><td>$($_.Groups)</td></tr>"
}
$reportContent += "</table>"

$reportContent += @"
    <h2>2. Grupos en Active Directory</h2>
    <div class="page-number">Página 2</div>
    <table>
        <tr><th>Nombre</th><th>SamAccountName</th><th>Scope</th><th>Descripción</th></tr>
"@
$groups | ForEach-Object {
    $reportContent += "<tr><td>$($_.Name)</td><td>$($_.SamAccountName)</td><td>$($_.GroupScope)</td><td>$($_.Description)</td></tr>"
}
$reportContent += "</table>"

$reportContent += @"
    <h2>3. GPOs en Active Directory</h2>
    <div class="page-number">Página 3</div>
    <table>
        <tr><th>Nombre</th><th>Owner</th><th>Creado</th><th>Modificado</th></tr>
"@
$gpos | ForEach-Object {
    $reportContent += "<tr><td>$($_.DisplayName)</td><td>$($_.Owner)</td><td>$($_.CreatedTime)</td><td>$($_.ModifiedTime)</td></tr>"
}
$reportContent += "</table>"

$reportContent += @"
    <h2>4. Grupos y GPOs Asociadas</h2>
    <div class="page-number">Página 4</div>
    <table>
        <tr><th>Organizational Unit</th><th>GPOs Aplicadas</th></tr>
"@
$ouGPOs | ForEach-Object {
    $reportContent += "<tr><td>$($_.OUName)</td><td>$($_.GPOs)</td></tr>"
}
$reportContent += "</table>"

$reportContent += @"
    <h2>5. Detalle de Configuración de GPOs</h2>
    <div class="page-number">Página 5</div>
"@
$gpoDetails | ForEach-Object {
    $reportContent += $_
}
$reportContent += @"
    <footer>
        <h5>Programado por: Claudio Aliste Requena - Ingeniero de Infraestructura TI & Cloud<br>
        Generado el: $currentDateTime</h5>
    </footer>
</body>
</html>
"@

# Escribir el reporte a un archivo HTML
Write-Host "Guardando el reporte en $reportPath..." -ForegroundColor Yellow
Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8

# Abrir el reporte en el navegador predeterminado
Write-Host "Abriendo el reporte en el navegador predeterminado..." -ForegroundColor Green
Start-Process $reportPath
