# Autor: Claudio Aliste Requena
# email: aliste.claudio@gmail.com
# Revision 1.5
# Descripcion: este script genera un archivo txt el cual indica nombre de server, confguracion de time zone, y dia que se cambiara la hora segun horario de verano o invierno
#               En caso de mejorarlo, compartir la mejora con todos              

# === Credenciales ===
$cred = Get-Credential

# === Ruta de log ===
$logDir = "C:\Logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logPath = Join-Path $logDir ("CambioDeHora_2024_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $message"
}

# === Lista de servidores ===
$Servers = @(
    “server1”,
    “server2”,
    “server3”,
    “server4”,
    
)

foreach ($Server in $Servers) {
    try {
        Write-Log "------------------------------------------------------------"
        Write-Log "Conectando a $Server..."

        $Session = New-PSSession -ComputerName $Server -Credential $cred

        Invoke-Command -Session $Session -ScriptBlock {
            $TimeZone = Get-TimeZone
            Write-Output "Servidor: $env:COMPUTERNAME"
            Write-Output "Zona Horaria: $($TimeZone.DisplayName)"
            Write-Output "Horario de Verano habilitado: $($TimeZone.SupportsDaylightSavingTime)"

            if ($TimeZone.SupportsDaylightSavingTime) {
                $currentYear = (Get-Date).Year

                $primerSabado = {
                    param($mes)
                    (1..7 | ForEach-Object {
                        $d = Get-Date -Year $currentYear -Month $mes -Day $_
                        if ($d.DayOfWeek -eq 'Saturday') { return $d }
                    }) | Select-Object -First 1
                }

                $cambioAbril = & $primerSabado 4
                $cambioSept = & $primerSabado 9
                $hoy = Get-Date

                if ($hoy -lt $cambioAbril) {
                    Write-Output "Próximo cambio de hora: $($cambioAbril.ToString('dd/MM/yyyy'))"
                } elseif ($hoy -lt $cambioSept) {
                    Write-Output "Próximo cambio de hora: $($cambioSept.ToString('dd/MM/yyyy'))"
                } else {
                    Write-Output "No se encontró un cambio de hora próximo en 2024."
                }
            } else {
                Write-Output "Zona horaria sin soporte para horario de verano."
            }
        } | ForEach-Object {
            Write-Log $_
        }

        Remove-PSSession -Session $Session
    } catch {
        Write-Log "❌ No se pudo conectar a ${Server}: $($_.Exception.Message)"
    }
}

Write-Host "`n✅ Script finalizado. Revisa el log en: $logPath" -ForegroundColor Green



