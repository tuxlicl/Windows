<#
Autor              : Claudio Aliste
Email              : aliste.claudio@gmail.com
Fecha creación     : 31/03/2025
Fecha modificación : 06/01/2026
Propósito          : Generar informe de sanidad de Active Directory en formato HTML
Versión            : 1.1
#>


[CmdletBinding()]
param(
    [switch]$Pause
)

# ========================
# CONFIG (EDITABLE)
# ========================
$OutputDir  = "C:\Logs"  # ← EDITABLE
$OutputName = "Informe_Sanidad_AD_{0}.html" -f (Get-Date -Format "yyyyMMdd_HHmmss")  # ← EDITABLE

# Timeouts para ejecutables
$TimeoutSec = 240        # ← EDITABLE (dcdiag/repadmin)

# Bloques RAW (para evitar “chimuchina”, quedan plegados en <details>)
$IncludeRawBlocks = $true # ← EDITABLE
$MaxRawLines      = 350   # ← EDITABLE

# Integridad BD (señales): ventana de eventos a revisar
$DbEventsDaysBack = 7     # ← EDITABLE: últimos N días
$DbEventsMax      = 200   # ← EDITABLE: máximo eventos a leer

# Verificación de servicios por DC (remoto)
$CheckServicesRemote = $true  # ← EDITABLE: si RPC bloqueado, igual no rompe
$ServiceNames = @("NTDS","DNS","KDC","Netlogon","DFSR","W32Time","ADWS")  # ← EDITABLE

# ========================
# Helpers
# ========================
function Ensure-Dir {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function HtmlEncode {
    param([string]$s)
    if ($null -eq $s) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($s)
}

function Invoke-Exe {
    <#
      Ejecuta un EXE con timeout. Devuelve @{ ExitCode; StdOut; StdErr; TimedOut }
      SOLO LECTURA, no detiene/inicia nada.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 180
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = ($Arguments -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    $null = $p.Start()
    $timedOut = -not $p.WaitForExit($TimeoutSeconds * 1000)

    if ($timedOut) { try { $p.Kill() } catch {} }

    [pscustomobject]@{
        ExitCode = if ($timedOut) { 999 } else { $p.ExitCode }
        StdOut   = $p.StandardOutput.ReadToEnd()
        StdErr   = $p.StandardError.ReadToEnd()
        TimedOut = $timedOut
    }
}

function To-HtmlTable {
    param(
        [Parameter(Mandatory)]$Data,
        [Parameter(Mandatory)][string]$Title,
        [string]$Hint = ""
    )

    if ($null -eq $Data -or ($Data | Measure-Object).Count -eq 0) {
        return @"
<section class="card">
  <h2>$(HtmlEncode $Title)</h2>
  $(if($Hint){ "<p class='muted'>$(HtmlEncode $Hint)</p>" } else { "" })
  <div class="empty">Sin datos.</div>
</section>
"@
    }

    $htmlTable = $Data | ConvertTo-Html -Fragment -As Table
    @"
<section class="card">
  <h2>$(HtmlEncode $Title)</h2>
  $(if($Hint){ "<p class='muted'>$(HtmlEncode $Hint)</p>" } else { "" })
  $htmlTable
</section>
"@
}

function To-DetailsBlock {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Content
    )
    if ([string]::IsNullOrWhiteSpace($Content)) { return "" }

    $lines = $Content -split "`r?`n"
    if ($lines.Count -gt $MaxRawLines) {
        $lines = $lines | Select-Object -First $MaxRawLines
        $Content = ($lines -join "`r`n") + "`r`n... (recortado a $MaxRawLines líneas)"
    }

    @"
<details class="raw">
  <summary>$(HtmlEncode $Title)</summary>
  <pre>$(HtmlEncode $Content)</pre>
</details>
"@
}

function Get-SeverityBadge {
    param([ValidateSet("OK","WARN","FAIL","INFO")][string]$Level)
@{
"OK"   = "<span class='badge ok'>OK</span>"
"WARN" = "<span class='badge warn'>WARN</span>"
"FAIL" = "<span class='badge fail'>FAIL</span>"
"INFO" = "<span class='badge info'>INFO</span>"
}[$Level]
}

function Try-GetRegValue {
    param([string]$Path,[string]$Name)
    try {
        $p = Get-ItemProperty -Path $Path -ErrorAction Stop
        return $p.$Name
    } catch { return $null }
}

function Get-DriveFreePct {
    param([string]$FilePath)
    try {
        $root = [System.IO.Path]::GetPathRoot($FilePath)
        if (-not $root) { return $null }
        $d = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($root.TrimEnd('\'))'" -ErrorAction Stop
        if ($d.Size -le 0) { return $null }
        return [math]::Round(($d.FreeSpace / $d.Size) * 100, 1)
    } catch { return $null }
}

function Summarize-ServiceStates {
    param([object[]]$ServiceObjects)
    if (-not $ServiceObjects -or $ServiceObjects.Count -eq 0) { return "Sin datos" }
    $bad = $ServiceObjects | Where-Object { $_.Status -ne 'Running' -and $_.Status -ne 'No presente' }
    if ($bad.Count -eq 0) { return "OK" }
    return ("Problemas: " + (($bad | ForEach-Object { "$($_.Service)=$($_.Status)" }) -join ", "))
}

# ========================
# Inicio
# ========================
Ensure-Dir -Path $OutputDir
$outputPath = Join-Path $OutputDir $OutputName
$start = Get-Date

# ========================
# Recolección AD (solo lectura)
# ========================
try { Import-Module ActiveDirectory -ErrorAction Stop }
catch {
    Write-Host "❌ No se pudo cargar ActiveDirectory: $($_.Exception.Message)" -ForegroundColor Red
    if ($Pause) { Read-Host "Enter para salir" }
    exit 1
}

$forest = Get-ADForest
$domain = Get-ADDomain
$dcs    = Get-ADDomainController -Filter * | Sort-Object HostName

# Niveles funcionales (pedido)
$domainFunctionalLevel = $domain.DomainMode
$forestFunctionalLevel = $forest.ForestMode

# Roles FSMO (resumen)
$fsmoTable = [pscustomobject]@{
    Forest    = $forest.Name
    Domain    = $domain.DNSRoot
    "Forest Functional Level" = $forestFunctionalLevel
    "Domain Functional Level" = $domainFunctionalLevel
    SchemaMaster         = $forest.SchemaMaster
    DomainNamingMaster   = $forest.DomainNamingMaster
    PDCEmulator          = $domain.PDCEmulator
    RIDMaster            = $domain.RIDMaster
    InfrastructureMaster = $domain.InfrastructureMaster
}

# Inventario DCs (incluye OS) + roles por DC (pedido)
$dcTable = $dcs | ForEach-Object {
    [pscustomobject]@{
        Name     = $_.HostName
        Site     = $_.Site
        IPv4     = $_.IPv4Address
        OS       = $_.OperatingSystem
        IsGC     = $_.IsGlobalCatalog
        ReadOnly = $_.IsReadOnly
        "OperationMasterRoles" = ($_.OperationMasterRoles -join ", ")
    }
}

# Resumen OS (pedido “SO de los DCs” en modo ejecutivo)
$osSummary = $dcTable |
    Group-Object OS | Sort-Object Count -Descending |
    ForEach-Object { [pscustomobject]@{ OperatingSystem = $_.Name; Count = $_.Count } }

# Servicios locales (solo estado, no tocamos nada)
$svcLocal = foreach ($sn in $ServiceNames) {
    $s = Get-Service -Name $sn -ErrorAction SilentlyContinue
    if ($null -eq $s) {
        [pscustomobject]@{ Service=$sn; Status="No presente"; StartType=""; Note="(puede ser normal según rol)" }
    } else {
        [pscustomobject]@{ Service=$sn; Status=$s.Status; StartType=$s.StartType; Note="" }
    }
}

# Servicios por DC (remoto) - pedido “verificar servicios AD”
$svcRemoteSummary = @()
if ($CheckServicesRemote) {
    foreach ($dc in $dcs) {
        $rows = @()
        $note = ""
        try {
            foreach ($sn in $ServiceNames) {
                $s = Get-Service -ComputerName $dc.HostName -Name $sn -ErrorAction Stop
                $rows += [pscustomobject]@{ Service=$sn; Status=$s.Status; StartType=$s.StartType }
            }
        } catch {
            $note = "No accesible por RPC/Permisos: $($_.Exception.Message)"
        }

        $svcRemoteSummary += [pscustomobject]@{
            DC      = $dc.HostName
            Summary = if ($note) { $note } else { Summarize-ServiceStates -ServiceObjects ($rows | ForEach-Object { [pscustomobject]@{Service=$_.Service; Status=$_.Status} }) }
        }
    }
}

# ========================
# Integridad/Estado BD AD (señales seguras)
# ========================
# Nota: NO se ejecuta esentutl/ntdsutil offline (eso sí podría ser riesgoso si se hace mal).
$ntdsRegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
$dbPath  = Try-GetRegValue -Path $ntdsRegPath -Name "DSA Database file"
$logPath = Try-GetRegValue -Path $ntdsRegPath -Name "Database log files path"

$dbExists  = if ($dbPath)  { Test-Path -LiteralPath $dbPath }  else { $false }
$logExists = if ($logPath) { Test-Path -LiteralPath $logPath } else { $false }

$dbSizeGB = $null
try { if ($dbExists) { $dbSizeGB = [math]::Round(((Get-Item -LiteralPath $dbPath).Length / 1GB), 2) } } catch {}

$freePctDbDrive  = if ($dbPath)  { Get-DriveFreePct -FilePath $dbPath }  else { $null }
$freePctLogDrive = if ($logPath) { Get-DriveFreePct -FilePath $logPath } else { $null }

# Eventos en “Directory Service” (errores recientes)
$since = (Get-Date).AddDays(-1 * [Math]::Abs($DbEventsDaysBack))
$dbEventSummary = @()
try {
    $ev = Get-WinEvent -FilterHashtable @{
        LogName   = "Directory Service"
        StartTime = $since
    } -ErrorAction Stop | Select-Object -First $DbEventsMax

    $errCount  = ($ev | Where-Object { $_.LevelDisplayName -in @("Error","Critical") } | Measure-Object).Count
    $warnCount = ($ev | Where-Object { $_.LevelDisplayName -eq "Warning" } | Measure-Object).Count

    $top = $ev |
        Where-Object { $_.LevelDisplayName -in @("Error","Critical") } |
        Group-Object Id | Sort-Object Count -Descending | Select-Object -First 5 |
        ForEach-Object { [pscustomobject]@{ EventId = $_.Name; Count = $_.Count } }

    $dbEventSummary += [pscustomobject]@{
        "Window (days)" = $DbEventsDaysBack
        "Errors/Critical" = $errCount
        "Warnings"        = $warnCount
        "Top Error IDs"   = if ($top.Count -gt 0) { ($top | ForEach-Object { "$($_.EventId)($($_.Count))" } ) -join ", " } else { "N/A" }
    }
} catch {
    $dbEventSummary += [pscustomobject]@{
        "Window (days)" = $DbEventsDaysBack
        "Errors/Critical" = "No se pudo leer el log: $($_.Exception.Message)"
        "Warnings"        = ""
        "Top Error IDs"   = ""
    }
}

$dbHealthTable = @(
    [pscustomobject]@{
        "NTDS Database Path" = $dbPath
        "DB Exists"          = $dbExists
        "DB Size (GB)"       = $dbSizeGB
        "Free % (DB Drive)"  = $freePctDbDrive
        "Log Path"           = $logPath
        "Logs Exist"         = $logExists
        "Free % (Log Drive)" = $freePctLogDrive
        "Nota"               = "Chequeos seguros (existencia/ruta/espacio/eventos). Integridad profunda requiere ventana offline."
    }
)

# ========================
# DCDIAG / REPADMIN (con timeout)
# ========================
$dcdiagCore = Invoke-Exe -FilePath "dcdiag.exe" -Arguments @("/test:Advertising","/test:Replications","/test:DNS","/v") -TimeoutSeconds $TimeoutSec
$dcdiagSvc  = Invoke-Exe -FilePath "dcdiag.exe" -Arguments @("/test:Services","/v") -TimeoutSeconds $TimeoutSec
$repl       = Invoke-Exe -FilePath "repadmin.exe" -Arguments @("/replsummary") -TimeoutSeconds $TimeoutSec

function Get-Findings {
    param([string]$Text,[string]$SourceTag)

    $find = @()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $find }

    $patterns = @("fail","error","warning","unable","denied","timed out","fatal")
    $lines = $Text -split "`r?`n"

    foreach ($ln in $lines) {
        $l = $ln.Trim()
        if (-not $l) { continue }
        foreach ($p in $patterns) {
            if ($l -match $p) {
                $find += [pscustomobject]@{ Source = $SourceTag; Line = $l }
                break
            }
        }
        if ($find.Count -ge 60) { break }
    }
    return $find
}

$findings = @()
foreach ($item in @(
    @{Obj=$dcdiagCore; Tag="DCDIAG(core)"},
    @{Obj=$dcdiagSvc;  Tag="DCDIAG(services)"},
    @{Obj=$repl;       Tag="REPADMIN"}
)) {
    if ($item.Obj.TimedOut) {
        $findings += [pscustomobject]@{ Source=$item.Tag; Line="Timed out (> ${TimeoutSec}s). Considera subir TimeoutSec." }
    }
    if (-not [string]::IsNullOrWhiteSpace($item.Obj.StdErr)) {
        $findings += [pscustomobject]@{ Source=$item.Tag; Line=("STDERR: " + (($item.Obj.StdErr -split "`r?`n") | Select-Object -First 1)) }
    }
    $findings += Get-Findings -Text $item.Obj.StdOut -SourceTag $item.Tag
}

$overall =
    if ($findings.Count -eq 0) { "OK" }
    elseif ($findings.Count -le 10) { "WARN" }
    else { "FAIL" }

# ========================
# HTML
# ========================
$css = @"
:root{--bg:#0b1220;--card:#121b2e;--text:#e7ecff;--muted:#a9b4da;--line:#2a3560;--ok:#2ecc71;--warn:#f1c40f;--fail:#e74c3c;--info:#5dade2;}
body{font-family:Segoe UI,Arial; margin:0; background:linear-gradient(180deg,#0b1220,#070b14); color:var(--text);}
.container{max-width:1100px; margin:0 auto; padding:24px;}
.header{display:flex; gap:16px; align-items:center; justify-content:space-between; margin-bottom:18px;}
.h1{font-size:26px; font-weight:700;}
.meta{color:var(--muted); font-size:13px;}
.card{background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; margin:14px 0; box-shadow:0 6px 18px rgba(0,0,0,.25);}
.card h2{margin:0 0 10px 0; font-size:18px;}
.badge{padding:4px 10px; border-radius:999px; font-weight:700; font-size:12px; display:inline-block;}
.badge.ok{background:rgba(46,204,113,.18); color:var(--ok); border:1px solid rgba(46,204,113,.35);}
.badge.warn{background:rgba(241,196,15,.18); color:var(--warn); border:1px solid rgba(241,196,15,.35);}
.badge.fail{background:rgba(231,76,60,.18); color:var(--fail); border:1px solid rgba(231,76,60,.35);}
.badge.info{background:rgba(93,173,226,.18); color:var(--info); border:1px solid rgba(93,173,226,.35);}
table{width:100%; border-collapse:collapse; font-size:13px;}
th,td{border-bottom:1px solid var(--line); padding:8px 10px; text-align:left; vertical-align:top;}
th{color:#cdd6ff; font-weight:700;}
pre{background:#0a1020; border:1px solid var(--line); padding:10px; border-radius:10px; overflow:auto; color:#dbe3ff; font-size:12px;}
.muted{color:var(--muted); margin:6px 0 0 0;}
.raw summary{cursor:pointer; color:#cdd6ff; font-weight:600;}
.empty{color:var(--muted); padding:6px 0;}
.footer{color:var(--muted); font-size:12px; padding:20px 0;}
"@

$html = New-Object System.Text.StringBuilder
[void]$html.AppendLine("<!doctype html><html><head><meta charset='utf-8'><title>Informe Sanidad AD</title><style>$css</style></head><body>")
[void]$html.AppendLine("<div class='container'>")
[void]$html.AppendLine("<div class='header'><div><div class='h1'>Informe de Sanidad de Active Directory</div><div class='meta'>Generado en: $(HtmlEncode $env:COMPUTERNAME) · Inicio: $(HtmlEncode $start.ToString())</div></div><div>$(Get-SeverityBadge -Level $overall)</div></div>")

# Resumen ejecutivo (incluye niveles funcionales)
$summaryLines = @(
    "Bosque: $($forest.Name)",
    "Dominio: $($domain.DNSRoot)",
    "Nivel funcional del bosque: $forestFunctionalLevel",
    "Nivel funcional del dominio: $domainFunctionalLevel",
    "DCs detectados: $($dcTable.Count)",
    "Hallazgos (dcdiag/repadmin): $($findings.Count)"
)

[void]$html.AppendLine(@"
<section class="card">
  <h2>Resumen ejecutivo</h2>
  <p class="muted">Estado general: $(HtmlEncode $overall)</p>
  <ul>
    <li>$(HtmlEncode $summaryLines[0])</li>
    <li>$(HtmlEncode $summaryLines[1])</li>
    <li>$(HtmlEncode $summaryLines[2])</li>
    <li>$(HtmlEncode $summaryLines[3])</li>
    <li>$(HtmlEncode $summaryLines[4])</li>
    <li>$(HtmlEncode $summaryLines[5])</li>
  </ul>
</section>
"@)

# Hallazgos
[void]$html.AppendLine((To-HtmlTable -Data $findings -Title "Hallazgos (líneas relevantes)" -Hint "Extracción simple de posibles errores/warnings desde dcdiag/repadmin."))

# Niveles funcionales + FSMO
[void]$html.AppendLine((To-HtmlTable -Data @($fsmoTable) -Title "Niveles funcionales y Roles FSMO" -Hint "ForestMode/DomainMode y asignación FSMO actual."))

# OS Summary
[void]$html.AppendLine((To-HtmlTable -Data $osSummary -Title "Sistema Operativo de los Domain Controllers (resumen)" -Hint "Conteo por versión reportada desde AD."))

# Roles por DC + inventario
[void]$html.AppendLine((To-HtmlTable -Data $dcTable -Title "Roles por DC e inventario" -Hint "Incluye GC/RODC y OperationMasterRoles por controlador."))

# Servicios AD (local)
[void]$html.AppendLine((To-HtmlTable -Data $svcLocal -Title "Servicios AD relevantes (este DC)" -Hint "Solo lectura. No inicia/detiene servicios."))

# Servicios AD (remoto por DC)
if ($CheckServicesRemote) {
    [void]$html.AppendLine((To-HtmlTable -Data $svcRemoteSummary -Title "Verificación de servicios AD por DC (remoto)" -Hint "Consulta con Get-Service -ComputerName. Si RPC/Firewall bloquea, se marca como No accesible."))
}

# Integridad/estado BD AD (señales)
[void]$html.AppendLine((To-HtmlTable -Data $dbHealthTable -Title "Base de datos de Active Directory (NTDS) - estado e integridad (señales seguras)" -Hint "Valida rutas/espacio/tamaño + revisa eventos en Directory Service. No ejecuta chequeos offline."))

# Eventos resumen
[void]$html.AppendLine((To-HtmlTable -Data $dbEventSummary -Title "Eventos recientes (Directory Service)" -Hint "Resumen de errores/advertencias en la ventana configurada."))

# Bloques RAW opcionales
if ($IncludeRawBlocks) {
    [void]$html.AppendLine((To-DetailsBlock -Title "Salida RAW: dcdiag (Advertising/Replications/DNS)" -Content $dcdiagCore.StdOut))
    [void]$html.AppendLine((To-DetailsBlock -Title "Salida RAW: dcdiag (Services)" -Content $dcdiagSvc.StdOut))
    [void]$html.AppendLine((To-DetailsBlock -Title "Salida RAW: repadmin /replsummary" -Content $repl.StdOut))
    if ($dcdiagCore.StdErr) { [void]$html.AppendLine((To-DetailsBlock -Title "STDERR: dcdiag core" -Content $dcdiagCore.StdErr)) }
    if ($dcdiagSvc.StdErr)  { [void]$html.AppendLine((To-DetailsBlock -Title "STDERR: dcdiag services" -Content $dcdiagSvc.StdErr)) }
    if ($repl.StdErr)       { [void]$html.AppendLine((To-DetailsBlock -Title "STDERR: repadmin" -Content $repl.StdErr)) }
}

# Recomendaciones cortas (sin chimuchina)
$reco = @()
if ($overall -eq "OK") {
    $reco += "A nivel general se ve sano. Mantener monitoreo de replicación y DNS."
} elseif ($overall -eq "WARN") {
    $reco += "Revisar hallazgos puntuales. Correlacionar con eventos de red/DNS si es intermitente."
} else {
    $reco += "Priorizar replicación y DNS (dcdiag/repadmin) y revisar errores en Directory Service."
}
$reco += "Este informe es 100% lectura: no detiene ni reinicia servicios."

[void]$html.AppendLine(@"
<section class="card">
  <h2>Recomendaciones</h2>
  <ul>
    <li>$(HtmlEncode $reco[0])</li>
    <li>$(HtmlEncode $reco[1])</li>
  </ul>
</section>
"@)

$end = Get-Date
$dur = (New-TimeSpan -Start $start -End $end).ToString()
[void]$html.AppendLine("<div class='footer'>Duración: $(HtmlEncode $dur)</div>")
[void]$html.AppendLine("</div></body></html>")

$html.ToString() | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "✅ Informe generado: $outputPath" -ForegroundColor Green

if ($Pause) {
    Read-Host "Presiona Enter para cerrar"
}

