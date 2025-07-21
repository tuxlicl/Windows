<#
Autor              : Claudio Aliste
Email              : aliste.claudio@gmail.com
Fecha creación     : 31/03/2025
Fecha modificación : 14/05/2025
Propósito          : Generar informe de sanidad de Active Directory en formato HTML
Versión            : 1.1
#>

# ========================
# Variables y rutas
# ========================
$templatePath = "C:\Logs\Informe_Sanidad_AD_Template.html"
$outputPath = "C:\Logs\Informe_Sanidad_AD_Completo.html"

if (!(Test-Path "C:\Logs")) {
    New-Item -Path "C:\Logs" -ItemType Directory -Force | Out-Null
}

# ========================
# Recolección de información
# ========================
$forest = (Get-ADForest | Out-String).Trim()
$domain = (Get-ADDomain | Out-String).Trim()
$dcs = (Get-ADDomainController -Filter * | Format-Table Name,OperatingSystem,IPv4Address,Site | Out-String).Trim()

$dcdiag = (dcdiag /v | Out-String).Trim()
$repSummary = (repadmin /replsummary | Out-String).Trim()
$showRepl = (repadmin /showrepl * | Out-String).Trim()
$dnsDiag = (dcdiag /test:dns /v | Out-String).Trim()

$gpos = (Get-GPO -All | Select DisplayName, GpoStatus, CreationTime, ModificationTime | Format-Table | Out-String).Trim()

# Controladores obsoletos
$obsoleteDCs = (Get-ADDomainController -Filter * | Where-Object { $_.IsGlobalCatalog -eq $false -or $_.Enabled -eq $false } | Format-Table Name, IsGlobalCatalog, Enabled | Out-String).Trim()

# Servicios de replicación
$replicationStatus = ""
$servicios = @("NtFrs", "DFSR")
foreach ($svc in $servicios) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        $replicationStatus += "<p><strong>${svc}:</strong> $($s.Status)</p>`n"
    } else {
        $replicationStatus += "<p><strong>${svc}:</strong> No está presente en este servidor.</p>`n"
    }
}

# ========================
# Construcción del HTML
# ========================
$htmlContent = @"
<html>
<head>
    <title>Informe de Sanidad de Active Directory</title>
    <style>
        body { font-family: Arial; margin: 20px; }
        h2 { color: #004080; border-bottom: 1px solid #ccc; }
        pre { background-color: #f4f4f4; padding: 10px; border: 1px solid #ddd; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>Informe de Sanidad de Active Directory</h1>

    <h2>1. Infraestructura General</h2>
    <pre>$forest

$domain

$dcs</pre>

    <h2>2. Estado de los Controladores de Dominio</h2>
    <pre>$dcdiag</pre>

    <h2>3. Replicación</h2>
    <pre>$repSummary

$showRepl</pre>

    <h2>4. DNS Integrado</h2>
    <pre>$dnsDiag</pre>

    <h2>5. Delegación y Control de Acceso</h2>
    <p>Este punto requiere análisis manual de las ACL por OU específicas.</p>

    <h2>6. Omitido</h2>
    <p>Este punto fue omitido por solicitud.</p>

    <h2>7. Políticas de Grupo (GPOs)</h2>
    <pre>$gpos</pre>

    <h2>8. Auditoría y Registros</h2>
    <p>Debe realizarse desde la consola de eventos o mediante script especializado según permisos.</p>

    <h2>9. Controladores Obsoletos</h2>
    <pre>$obsoleteDCs</pre>

    <h2>10. Servicios de Replicación</h2>
    $replicationStatus

    <h2>11. Recomendaciones</h2>
    <p>Este punto requiere evaluación posterior y revisión técnica detallada.</p>
</body>
</html>
"@

# ========================
# Guardar HTML
# ========================
$htmlContent | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "✅ Informe generado: $outputPath" -ForegroundColor Green
