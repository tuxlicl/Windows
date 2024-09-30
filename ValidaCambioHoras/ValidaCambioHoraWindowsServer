# Autor: Claudio Aliste Requena
# email: aliste.claudio@gmail.com
# Revision 1.5
# Descripcion: este script genera un archivo txt el cual indica nombre de server, confguracion de time zone, y dia que se cambiara la hora segun horariode verano o invierno
#               En caso de mejorarlo, compartir la mejora con todos                


# Solicitar las credenciales del usuario
$cred = Get-Credential

# Definir la ruta del archivo de log
$logPath = "C:\ChangeHour\CambioDeHora_20224.txt"

# Crear el directorio si no existe
if (-not (Test-Path -Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs"
}

# Función para registrar en el log
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content -Path $logPath -Value $logMessage
}

# Lista de servidores (puedes agregar más IPs o nombres de servidores, serparados por coma y en comillas dobles "")
$Servers = "ingresa ip o cname del server"

foreach ($Server in $Servers) {
    try {
        Write-Log "Conectando a $Server..."
        
        # Crear la sesión con las credenciales proporcionadas, para aplicar el script debes tener el rol de domain admin
        $Session = New-PSSession -ComputerName $Server -Credential $cred
        
        # Ejecutar el bloque de comandos en el servidor remoto
        Invoke-Command -Session $Session -ScriptBlock {
            # Obtener la configuración de la zona horaria actual
            $TimeZone = Get-TimeZone

            # Mostrar la configuración del cambio de hora
            Write-Output "Configuración de la Zona Horaria: $($TimeZone.DisplayName)"
            Write-Output "Horario de Verano está habilitado: $($TimeZone.SupportsDaylightSavingTime)"

            # Calcular el próximo cambio de horario según las reglas específicas de Chile
            if ($TimeZone.SupportsDaylightSavingTime) {
                $currentYear = (Get-Date).Year

                # El primer sábado de septiembre (fin del horario de verano)
                $firstSaturdayInSeptember = (1..7 | ForEach-Object { 
                    $date = Get-Date -Year $currentYear -Month 9 -Day $_
                    if ($date.DayOfWeek -eq 'Saturday') { $date }
                }) | Select-Object -First 1

                # El primer sábado de abril (inicio del horario de verano)
                $firstSaturdayInApril = (1..7 | ForEach-Object { 
                    $date = Get-Date -Year $currentYear -Month 4 -Day $_
                    if ($date.DayOfWeek -eq 'Saturday') { $date }
                }) | Select-Object -First 1

                # Verificar si la fecha actual es anterior al cambio de septiembre
                $currentDate = Get-Date
                if ($currentDate -lt $firstSaturdayInSeptember) {
                    $changeDate = $firstSaturdayInSeptember.ToString('dd/MM/yyyy')
                    Write-Output "El próximo cambio de hora será el: $changeDate"
                } elseif ($currentDate -lt $firstSaturdayInApril) {
                    $changeDate = $firstSaturdayInApril.ToString('dd/MM/yyyy')
                    Write-Output "El próximo cambio de hora será el: $changeDate"
                } else {
                    Write-Output "No se ha encontrado un cambio de hora en el futuro cercano."
                }
            } else {
                Write-Output "El horario de verano no está habilitado para esta zona horaria en $using:Server."
            }
        } | ForEach-Object { 
            Write-Log "$_"
        }
        
        # Cerrar la sesión remota
        Remove-PSSession -Session $Session
        
    } catch {
        Write-Log ("No se pudo conectar a {0}: {1}" -f $Server, $_.Exception.Message)
    }
}
