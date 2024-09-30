<#
Autor              : Claudio Aliste
Email              : aliste.claudio@gmail.com
Fecha creación     : 03/03/2023
Fecha modificación : 13/09/2024
Propósito          : Notificar vencimiento de contraseña por correo con log y formato HTML
Versión            : 2.0
#>

Clear
# Definición de variables
$hoy = Get-Date
$dias = 15
$logPath = "C:\Logs\PasswordExpiryLog.txt"  # Ruta del archivo de log

# Crear el directorio si no existe
if (-not (Test-Path -Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs"
}

# Función para registrar logs
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "dd/MM/yyyy HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Add-Content -Path $logPath -Value $logMessage
}

# Función para enviar correo (en formato HTML)
function Enviar-Correo {
    param (
        [string]$correo,
        [string]$nombreusr,
        [int]$dif_dias,
        [int]$dif_horas
    )

    # Validar si el correo es válido antes de continuar
    if (-not [string]::IsNullOrEmpty($correo) -and $correo -match ".+@.+\..+") {
        $de = "xxx@xxxx.xx" #en este lugar va el remitente del correo
        $servidorsmtp = "10.135.40.32" #Ip del servidor SMTP
        $asunto = "Atención! La Clave de su CUENTA está próxima a caducar"
        
        $cuerpo = @"
        <html>
        <head>
            <style>
                body { font-family: Arial, sans-serif; color: #333; }
                h2 { color: #2E8B57; }
                p { font-size: 14px; }
                .footer { font-size: 12px; color: #ff2d00; margin-top: 20px; }
            </style>
        </head>
        <body>
            <p>Sr(a). <strong>$nombreusr</strong>, se informa que la clave con la que ingresa a la Red Scada caducará en <strong>$dif_dias</strong> día(s) y <strong>$dif_horas</strong> hora(s).</p>
            <p>Se recomienda cambiarla antes de que esto suceda. Puede realizar el cambio de la siguiente manera:</p>
            <ul>
                <li>Presione simultáneamente las teclas <strong>Control + Alt + Suprimir</strong>.</li>
                <li>Seleccione "Cambiar una contraseña".</li>
                <li>Ingrese su contraseña actual y luego la nueva en dos ocasiones.</li>
                <li>Presione <strong>Enter</strong> o haga clic en la flecha.</li>
            </ul>
            <p>Atte</p>
            <p>Subgerencia de Telecomunicaciones y Tecnologías de la Información</p>
            <div class="footer"><strong>Este es un correo automático. Por favor, no responda a este mensaje.</strong></div>
        </body>
        </html>
"@
        
        try {
            $mensaje = New-Object System.Net.Mail.MailMessage
            $mensaje.From = $de
            $mensaje.To.Add($correo)
            $mensaje.Subject = $asunto
            $mensaje.Body = $cuerpo
            $mensaje.IsBodyHtml = $true

            $clientesmtp = New-Object Net.Mail.SmtpClient($servidorsmtp, 3025)
            $clientesmtp.EnableSsl = $false
            $clientesmtp.Send($mensaje)

            Write-Host -ForegroundColor Green "Correo enviado a $nombreusr <$correo>."
            Write-Log "Correo enviado a $nombreusr <$correo>."
        } catch {
            Write-Host -ForegroundColor Red "Error al enviar el correo a $nombreusr <$correo>: $_"
            Write-Log "Error al enviar el correo a $nombreusr <$correo>: $_"
        }
    } else {
        Write-Host -ForegroundColor Yellow "Correo inválido o vacío para $nombreusr. No se envió notificación."
        Write-Log "Correo inválido o vacío para $nombreusr. No se envió notificación."
    }
}

# Obtener usuarios del AD y la fecha de expiración de su clave
$usuarios = Get-ADUser -Filter {PasswordNeverExpires -eq $False -and Enabled -eq $True} -Properties DisplayName, EmailAddress, PasswordExpired, msDS-UserPasswordExpiryTimeComputed |
Select DisplayName, EmailAddress, PasswordExpired, @{Name="PasswordExpires";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}}

# Ciclo para recorrer usuarios
foreach ($usr in $usuarios) {
    $nombreusr = $usr.DisplayName
    $correo = $usr.EmailAddress

    if ($usr.PasswordExpired -eq $False) {
        $diferencia = $usr.PasswordExpires - $hoy
        $dif_dias = $diferencia.Days
        $dif_horas = $diferencia.Hours

        # Solo enviar correo si la contraseña expira en 15 días o menos
        if ($dif_dias -le $dias -and $dif_dias -ge 0) {
            Enviar-Correo $correo $nombreusr $dif_dias $dif_horas
        }
    }
}

# Mensaje final
Write-Host -ForegroundColor Cyan "Proceso completado. Revisa el log en $logPath para más detalles."
ß