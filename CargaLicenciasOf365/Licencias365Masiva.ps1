##
# Autor              : Claudio Aliste Requena
# Email              : aliste.claudio@gmail.com
# Fecha creación     : 31/08/2024
# Fecha modificación : 27/12/2024
# Propósito          : Conectarse por powershell al Tenant de OF365 y cargar de manera masiva las licencias a los usuarios indicados en el archivo usuarios.csv
# Versión            : 2.0
# ***** DISCLAIMER ******: En caso de hacerle una mejora, informar para tener el script actualizado
# ***** DISCLAIMER 2 *****: No me hago responsable del mal uso de este script, es de uso netamente interno y para auditar cuentas y configuracioens en un entorno de Active Directory.

# Ruta al archivo CSV con los usuarios
$csvPath = "C:\ruta\al\archivo\usuarios.csv" 

# Verificar y desinstalar cualquier versión previa del módulo Microsoft.Graph
Write-Host "Verificando módulos de Microsoft.Graph cargados..." -ForegroundColor Yellow
$graphModules = Get-Module -Name Microsoft.Graph* -ListAvailable
if ($graphModules) {
    Write-Host "Se encontraron módulos de Microsoft.Graph cargados. Eliminándolos..." -ForegroundColor Yellow
    foreach ($module in $graphModules) {
        try {
            Remove-Module -Name $module.Name -Force -ErrorAction Stop
            Write-Host "Módulo eliminado: $($module.Name)" -ForegroundColor Green
        } catch {
            Write-Host "No se pudo eliminar el módulo: $($module.Name). Detalles: $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "No se encontraron módulos cargados." -ForegroundColor Green
}

# Instalar o actualizar el módulo Microsoft.Graph
Write-Host "Instalando o actualizando el módulo Microsoft.Graph..." -ForegroundColor Yellow
try {
    Install-Module -Name Microsoft.Graph -Force -AllowClobber -ErrorAction Stop
    Write-Host "Módulo Microsoft.Graph instalado o actualizado correctamente." -ForegroundColor Green
} catch {
    Write-Host "Error durante la instalación o actualización del módulo Microsoft.Graph. Detalles: $_" -ForegroundColor Red
    exit
}

# Conectar a Microsoft Graph
Write-Host "Conectando a Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All" -ErrorAction Stop
    Write-Host "Conexión a Microsoft Graph exitosa." -ForegroundColor Green
} catch {
    Write-Host "Error al conectar a Microsoft Graph. Detalles: $_" -ForegroundColor Red
    exit
}

# Obtener las licencias necesarias
Write-Host "Obteniendo licencias disponibles..." -ForegroundColor Yellow
try {
    $e5Sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq 'ENTERPRISEPACK' }
    $e5EmsSku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq 'ATP_ENTERPRISE' }

    if (-not $e5Sku -or -not $e5EmsSku) {
        Write-Host "No se encontraron las licencias necesarias (ENTERPRISEPACK o ATP_ENTERPRISE)." -ForegroundColor Red
        Disconnect-MgGraph
        exit
    }

    $addLicenses = @(
        @{SkuId = $e5Sku.SkuId},
        @{SkuId = $e5EmsSku.SkuId}
    )
    Write-Host "Licencias obtenidas correctamente." -ForegroundColor Green
} catch {
    Write-Host "Error al obtener las licencias. Detalles: $_" -ForegroundColor Red
    Disconnect-MgGraph
    exit
}

# Leer usuarios del archivo CSV
Write-Host "Leyendo usuarios desde el archivo CSV..." -ForegroundColor Yellow
try {
    $usuarios = Import-Csv $csvPath
    Write-Host "Usuarios leídos correctamente: $($usuarios.Count)" -ForegroundColor Green
} catch {
    Write-Host "Error al leer el archivo CSV. Asegúrate de que el archivo existe y tiene el formato correcto." -ForegroundColor Red
    Disconnect-MgGraph
    exit
}

# Procesar cada usuario
Write-Host "Procesando usuarios..." -ForegroundColor Yellow
foreach ($usuario in $usuarios) {
    try {
        # Asignar localización
        Write-Host "Asignando localización 'CL' al usuario $($usuario.UserPrincipalName)..." -ForegroundColor Yellow
        Update-MgUser -UserId $usuario.UserPrincipalName -UsageLocation CL

        # Asignar licencias
        Write-Host "Asignando licencias a $($usuario.UserPrincipalName)..." -ForegroundColor Yellow
        Set-MgUserLicense -UserId $usuario.UserPrincipalName -AddLicenses $addLicenses -RemoveLicenses @()

        Write-Host "Licencias asignadas correctamente a $($usuario.UserPrincipalName)." -ForegroundColor Green
    } catch {
        Write-Host "Error al procesar al usuario $($usuario.UserPrincipalName): $_" -ForegroundColor Red
    }
}

# Desconectar Microsoft Graph
Write-Host "Desconectando de Microsoft Graph..." -ForegroundColor Yellow
Disconnect-MgGraph
Write-Host "Proceso completado." -ForegroundColor Cyan
