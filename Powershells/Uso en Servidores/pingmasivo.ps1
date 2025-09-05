# Autor: Claudio Aliste Requena
# Revisión: 2.1 (2025)
# Descripción:
# Este script hace ping masivo a una lista de servidores y guarda la ip del mismo y si respondio o no en un listado .txt

# Ruta del archivo con la lista de servidores
$serverList = "C:\Scripts\servidores.txt"

# Ruta del log de salida
$log = "C:\Scripts\ping_resultados.txt"
if (Test-Path $log) { Remove-Item $log -Force }

# Leer cada línea y hacer ping
Get-Content $serverList | ForEach-Object {
    $server = $_.Trim()
    if ($server) {
        try {
            # Resolver IP
            $ip = [System.Net.Dns]::GetHostAddresses($server) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1

            if ($ip) {
                $status = Test-Connection -ComputerName $server -Count 2 -Quiet
                $result = if ($status) { 
                    "✅ ${server} (${ip}): Disponible" 
                } else { 
                    "❌ ${server} (${ip}): No responde" 
                }
            } else {
                $result = "⚠️ ${server}: No se pudo resolver IP"
            }
        } catch {
            $result = "❌ ${server}: Error - $($_.Exception.Message)"
        }

        Write-Host $result
        Add-Content -Path $log -Value $result
    }
}

Write-Host "`n✅ Revisión finalizada. Ver log: $log" -ForegroundColor Green
