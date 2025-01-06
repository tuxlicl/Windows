#
# Autor              : Claudio Aliste Requena
# Email              : aliste.claudio@gmail.com
# Fecha creación     : 01/03/2021
# Fecha modificación : 06/01/2024
# Propósito          : Informe que valida la integridad de la DB del AD, replicación, DNS, SysVol, roles del AD y los servicios de funcionamiento.
#                       Enumera la cantidad de Domains Controllers y los roles en caso de tener, indica el nivel funcional del dominio y de la foresta jerarquica del mismo
#
# Versión            : 2.0
# ***** DISCLAIMER ******: En caso de hacerle una mejora, comentar lo que hace y enviar por correo para generar la actualizacion del mismo
# ***** DISCLAIMER 2 *****: Estos script son para automatizar la generación de informes mensuales, no tiene otro fin

# Ruta del archivo de informe
$reportPath = "C:\Informes\Informe_AD_Completo.txt"

# Crear carpeta de informes si no existe
if (-not (Test-Path "C:\Informes")) {
    New-Item -Path "C:\Informes" -ItemType Directory | Out-Null
}

# Encabezado del informe
Add-Content -Path $reportPath -Value "Informe Mensual de Active Directory"
Add-Content -Path $reportPath -Value "Fecha de generación: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Add-Content -Path $reportPath -Value "============================================================`n"

# Validación de la base de datos de AD
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
        Stop-Service -Name NTDS -Force -ErrorAction Stop
        Start-Process -FilePath "cmd.exe" `
                      -ArgumentList "/c ntdsutil.exe < $($tempFile.FullName)" `
                      -RedirectStandardOutput $logFile `
                      -NoNewWindow -Wait
        $output = Get-Content -Path $logFile
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
# Consulta nivel funcional de domnio y bosque de AD
Add-Content -Path $reportPath -Value "`n=== Nivel Funcional de Dominio y Bosque ==="
try {
    # Obtener nivel funcional del Dominio
    $domainMode = (Get-ADDomain).DomainMode
    # Obtener nivel funcional del Bosque
    $forestMode = (Get-ADForest).ForestMode

    Add-Content -Path $reportPath -Value "Nivel Funcional del Dominio: $domainMode"
    Add-Content -Path $reportPath -Value "Nivel Funcional del Bosque: $forestMode"
} catch {
    Add-Content -Path $reportPath -Value "Error al obtener el nivel funcional del dominio o bosque: $($_.Exception.Message)"
}

# Enumeración de DC
Add-Content -Path $reportPath -Value "`n=== Enumeración de Controladores de Dominio (DC) ==="
try {
    $DCs = Get-ADDomainController -Filter * | Select-Object Name
    Add-Content -Path $reportPath -Value "Cantidad de Controladores de Dominio: $($DCs.Count)"
    $DCs | ForEach-Object {
        Add-Content -Path $reportPath -Value "Nombre del DC: $($_.Name)"
    }
} catch {
    Add-Content -Path $reportPath -Value "Error al enumerar los Controladores de Dominio: $($_.Exception.Message)"
}

# Roles de los DC
Add-Content -Path $reportPath -Value "`n=== Roles de los DC en el AD ==="
try {
    $rolesDC = Get-ADDomainController -Filter * | Select-Object Name, OperationMasterRoles
    foreach ($dc in $rolesDC) {
        Add-Content -Path $reportPath -Value "Nombre: $($dc.Name) - Roles: $($dc.OperationMasterRoles -join ', ')"
    }
} catch {
    Add-Content -Path $reportPath -Value "Error al obtener los roles de los DC: $($_.Exception.Message)"
}

# Servicios del AD
Add-Content -Path $reportPath -Value "`n=== Validación de la salud de los servicios de Active Directory ==="
if (-not (Get-Module -Name ActiveDirectory)) {
    Import-Module ActiveDirectory
}

# Replicación
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

# Compartición SYSVOL y NETLOGON
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

# Verificación de los servicios
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

# Cierre
Add-Content -Path $reportPath -Value "`nInforme completado el: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')"
Write-Host "El informe consolidado se ha generado en: $reportPath" -ForegroundColor Cyan