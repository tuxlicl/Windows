# Autor: Claudio Aliste Requena
# Revisión: 2.1 (2025)
# Descripción:
# Este script se conecta a servidores remotos vía PowerShell Remoting,
# valida la zona horaria configurada, y muestra cuándo inicia y termina
# el horario de verano (DST) según reglas del sistema (TimeZoneInfo).

# === Credenciales ===
$cred = Get-Credential

# === Ruta de log ===
$logDir = "C:\Logs"
if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logPath = Join-Path $logDir ("CambioDeHora_2025_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".txt")

function Write-Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $message"
}

# === Lista de servidores ===
$Servers = @(
    "server1",
    "server2",
    "server3",
    "server4",
    "server5",
    "server6",
    "server7",
    "server8",
    "server9",
    "server10",
    "server11"
)

foreach ($Server in $Servers) {
    Write-Log "------------------------------------------------------------"
    Write-Log "Conectando a $Server..."

    # Validación de conectividad básica
    if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet)) {
        Write-Log "❌ No se puede resolver o contactar al servidor: $Server"
        continue
    }

    try {
        $Session = New-PSSession -ComputerName $Server -Credential $cred -ErrorAction Stop

        if ($null -eq $Session) {
            Write-Log "❌ No se pudo establecer sesión con ${Server}: sesión nula."
            continue
        }

        Invoke-Command -Session $Session -ScriptBlock {
            $year = 2025
            $tz = [System.TimeZoneInfo]::Local

            $rulesStart = $tz.GetAdjustmentRules() | Where-Object {
                $_.DateStart.Year -le $year -and $_.DateEnd.Year -ge $year
            }

            $rulesEnd = $tz.GetAdjustmentRules() | Where-Object {
                $_.DateStart.Year -le ($year + 1) -and $_.DateEnd.Year -ge ($year + 1)
            }

            Write-Output "Servidor: $env:COMPUTERNAME"
            Write-Output "Zona Horaria: $($tz.DisplayName)"
            Write-Output "ID Zona Horaria: $($tz.Id)"
            Write-Output "Horario de Verano habilitado: $($tz.SupportsDaylightSavingTime)"

            if ($rulesStart -and $rulesEnd) {
                $start = $rulesStart.DaylightTransitionStart
                $end   = $rulesEnd.DaylightTransitionEnd

                function Get-DateFromTransition($transition, $year) {
                    $dayOfWeek = [int]$transition.DayOfWeek
                    $occurrence = $transition.Week
                    $month = $transition.Month
                    $time = $transition.TimeOfDay

                    $date = Get-Date -Year $year -Month $month -Day 1
                    while ($date.DayOfWeek -ne $transition.DayOfWeek) {
                        $date = $date.AddDays(1)
                    }
                    $date = $date.AddDays(7 * ($occurrence - 1)).Date.Add($time.TimeOfDay)
                    return $date
                }

                $dstStart = Get-DateFromTransition $start $year
                $dstEnd   = Get-DateFromTransition $end ($year + 1)

                Write-Output "🟢 Inicio horario de verano: $($dstStart.ToString('dd/MM/yyyy HH:mm'))"
                Write-Output "🔴 Fin horario de verano:    $($dstEnd.ToString('dd/MM/yyyy HH:mm'))"
            } else {
                Write-Output "⚠️ No se encontraron reglas de horario de verano para $year o $($year + 1)."
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
