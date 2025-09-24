<#
Autor              : Claudio Aliste
Email              : aliste.claudio@gmail.com
Fecha creación     : 31/03/2025
Última modificación: 28/07/2025
Propósito          : Comprimir archivos .arc y moverlos a una ruta de red, con validaciones y logs
Versión            : 5.0
#>

# ========== CONFIGURACIÓN ==========
$origen = "X:\-----\------\-------"
$destino = "\\xxx.xxx.xxx.xxx\----\----"
$extensionOriginal = ".arc"
$extensionComprimida = ".7z"
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"
$logPath = "C:\Logs\movimiento_xxxx.log"
$statsPath = "C:\Logs\resumen_20250728_115049.log"
$horaInicio = Get-Date
# ====================================

# ========== VALIDACIONES INICIALES ==========
if (!(Test-Path $sevenZipPath)) {
    Write-Host "❌ 7-Zip no encontrado en $sevenZipPath" -ForegroundColor Red
    exit
}

foreach ($ruta in @($origen, (Split-Path $logPath), $destino)) {
    if (!(Test-Path $ruta)) {
        try {
            New-Item -Path $ruta -ItemType Directory -Force | Out-Null
        } catch {
            Write-Host "❌ No se pudo crear la ruta $ruta - $_" -ForegroundColor Red
            exit
        }
    }
}
# ============================================

# ========== COMPRESIÓN ==========
Write-Host "`n🟡 Comenzando compresión..." -ForegroundColor Yellow
$archivosArc = Get-ChildItem -Path $origen -Filter "*$extensionOriginal" -File
$totalArc = $archivosArc.Count

for ($i = 0; $i -lt $totalArc; $i++) {
    $archivo = $archivosArc[$i]
    $archivo7z = Join-Path -Path $archivo.DirectoryName -ChildPath ($archivo.BaseName + $extensionComprimida)
    $porcentaje = [math]::Round(($i / $totalArc) * 100)
    Write-Progress -Activity "🗜 Comprimiendo archivos" -Status $archivo.Name -PercentComplete $porcentaje

    if (Test-Path $archivo7z) {
        Add-Content -Path $logPath -Value ("[{0}] ⏭ Ya existe: {1}" -f (Get-Date -Format 'HH:mm:ss'), $archivo7z)
        continue
    }

    $args = @(
        'a', '-t7z', '-mx=3', '-mmt=on',
        "`"$archivo7z`"",
        "`"$($archivo.FullName)`""
    )

    try {
        $proceso = Start-Process -FilePath $sevenZipPath -ArgumentList ($args -join ' ') -NoNewWindow -Wait -PassThru
        if (($proceso.ExitCode -eq 0 -or $proceso.ExitCode -eq 1) -and (Test-Path $archivo7z)) {
            Add-Content -Path $logPath -Value ("[{0}] ✅ Comprimido: {1}" -f (Get-Date -Format 'HH:mm:ss'), $archivo.Name)
            Remove-Item -Path $archivo.FullName -Force -ErrorAction SilentlyContinue
        } else {
            Add-Content -Path $logPath -Value ("[{0}] ❌ Error al comprimir: {1}. Código: {2}" -f (Get-Date -Format 'HH:mm:ss'), $archivo.Name, $proceso.ExitCode)
        }
    } catch {
        Add-Content -Path $logPath -Value ("[{0}] ❌ Excepción: {1}" -f (Get-Date -Format 'HH:mm:ss'), $_.Exception.Message)
    }
}
Write-Progress -Activity "🗜 Comprimiendo archivos" -Completed
# =================================

# ========== MOVIMIENTO ==========
Write-Host "`n🚛 Moviendo archivos..." -ForegroundColor Cyan
$archivos7z = Get-ChildItem -Path $origen -Filter "*$extensionComprimida" -File
$total7z = $archivos7z.Count

for ($i = 0; $i -lt $total7z; $i++) {
    $archivo = $archivos7z[$i]
    $destinoFinal = Join-Path -Path $destino -ChildPath $archivo.Name
    $porcentaje = [math]::Round(($i / $total7z) * 100)
    Write-Progress -Activity "🚛 Moviendo archivos" -Status $archivo.Name -PercentComplete $porcentaje

    try {
        Move-Item -Path $archivo.FullName -Destination $destinoFinal -Force -ErrorAction Stop
        Add-Content -Path $logPath -Value ("[{0}] ✅ Movido: {1}" -f (Get-Date -Format 'HH:mm:ss'), $archivo.Name)
    } catch {
        Add-Content -Path $logPath -Value ("[{0}] ❌ Error al mover {1} - {2}" -f (Get-Date -Format 'HH:mm:ss'), $archivo.Name, $_.Exception.Message)
    }
}
Write-Progress -Activity "🚛 Moviendo archivos" -Completed
# =================================

# ========== RESUMEN ==========
$horaFin = Get-Date
$duracion = New-TimeSpan -Start $horaInicio -End $horaFin
$resumen = @"
🧾 Resumen de ejecución
------------------------
Inicio    : $horaInicio
Fin       : $horaFin
Duración  : $($duracion.ToString())
Comprimidos: $totalArc
Movidos     : $total7z
"@
$resumen | Add-Content -Path $statsPath
Write-Host "`n✅ Proceso finalizado. Logs:" -ForegroundColor Green
Write-Host "   Log de ejecución: $logPath"
Write-Host "   Resumen final   : $statsPath"
# =================================
