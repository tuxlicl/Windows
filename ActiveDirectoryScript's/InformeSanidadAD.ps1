#
# Autor              : Claudio Aliste Requena
# Email              : aliste.claudio@gmail.com
# Fecha creación     : 01/03/2021
# Fecha modificación : 03/09/2024
# Propósito          : Informe que validad la integredidad de la DB del AD, Replicacion del mismo, DNs, SysVol, roles del AD y los servicios de funcionamiento
#                      
# Versión            : 1.0
# ***** DISCLAIMER ******: En caso de hacerle una mejora, informar para tener el script actualizado
# ***** DISCLAIMER 2 *****:

# Ruta del archivo de informe unificado
$reportPath = "C:\Informes\Informe_AD_Completo.txt"

# Crear carpeta de informes si no existe
if (-not (Test-Path "C:\Informes")) {
    New-Item -Path "C:\Informes" -ItemType Directory | Out-Null
}

# Iniciar el informe
Add-Content -Path $reportPath -Value "Informe Mensual de Active Directory"
Add-Content -Path $reportPath -Value "Fecha de generación: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Add-Content -Path $reportPath -Value "============================================================`n"

# Script para validar la sanidad de la DB del AD
Add-Content -Path $reportPath -Value "`n=== Validación de la base de datos de Active Directory ==="

function Check-ADDBIntegrity {
    param (
        [string]$logFile = "C:\IntegrityCheck.log"
    )

    $commands = @"
activate instance ntds
files
integrity
quit
quit
"@

    $tempFile = New-TemporaryFile
    Set-Content -Path $tempFile.FullName -Value $commands

    try {
        Write-Host "Deteniendo el servicio NTDS para realizar la validación..."
        Stop-Service -Name NTDS -Force -ErrorAction Stop

        Write-Host "Iniciando la verificación de la base de datos NTDS.dit..."
        Start-Process -FilePath "cmd.exe" `
                      -ArgumentList "/c ntdsutil.exe < $($tempFile.FullName)" `
                      -RedirectStandardOutput $logFile `
                      -NoNewWindow -Wait

        $output = Get-Content -Path $logFile
        Write-Host "Verificación completada. Resultado guardado en $logFile" -ForegroundColor Green

        Write-Host "Reiniciando el servicio NTDS..."
        Start-Service -Name NTDS -ErrorAction Stop

        return $output
    } catch {
        Write-Host "Error durante la ejecución de ntdsutil: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -Path $tempFile.FullName -Force
    }
}

try {
    $integrityResult = Check-ADDBIntegrity
    Add-Content -Path $reportPath -Value $integrityResult
} catch {
    Add-Content -Path $reportPath -Value "Error durante la validación: $($_.Exception.Message)"
}

# Script para validar la sanidad de servicios del AD
Add-Content -Path $reportPath -Value "`n=== Validación de la salud de los servicios de Active Directory ==="

if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory
}

Add-Content -Path $reportPath -Value "`n=== Verificando la salud de la replicación de AD ==="
try {
    $replicationStatus = & repadmin /replsummary
    if ($replicationStatus) {
        $replicationStatus -split "`r?`n" | ForEach-Object {
            Add-Content -Path $reportPath -Value $_
        }
    } else {
        Add-Content -Path $reportPath -Value "No se obtuvo información de replicación."
    }
} catch {
    Add-Content -Path $reportPath -Value "Error al verificar la replicación de AD: $($_.Exception.Message)"
}

Add-Content -Path $reportPath -Value "`n=== Verificando el estado de compartición de SYSVOL y NETLOGON ==="
try {
    if ((Get-SmbShare -Name SYSVOL -ErrorAction SilentlyContinue) -and (Get-SmbShare -Name NETLOGON -ErrorAction SilentlyContinue)) {
        Add-Content -Path $reportPath -Value "SYSVOL y NETLOGON están correctamente compartidos."
    } else {
        Add-Content -Path $reportPath -Value "SYSVOL o NETLOGON no están compartidos correctamente."
    }
} catch {
    Add-Content -Path $reportPath -Value "Error al verificar SYSVOL y NETLOGON: $($_.Exception.Message)"
}

Add-Content -Path $reportPath -Value "`n=== Verificando los servicios de Active Directory ==="
$services = @("NTDS", "KDC", "DNS", "ADWS", "LanmanServer")
foreach ($service in $services) {
    try {
        $status = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($status.Status -eq 'Running') {
            Add-Content -Path $reportPath -Value "El servicio ${service} está funcionando."
        } else {
            Add-Content -Path $reportPath -Value "El servicio ${service} NO está funcionando."
        }
    } catch {
        Add-Content -Path $reportPath -Value "No se pudo verificar el servicio ${service}: $($_.Exception.Message)"
    }
}

# Finalizar el informe
Add-Content -Path $reportPath -Value "`nInforme completado el: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')"
Write-Host "El informe consolidado se ha generado en: $reportPath" -ForegroundColor Cyan
