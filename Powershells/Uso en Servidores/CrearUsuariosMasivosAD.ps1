<#
Crea/actualiza/mueve usuarios en AD desde CSV:
GivenName,Surname,SamAccountName,Title,Department,DisplayName,UserPrincipalName,OU

- Lectura robusta del CSV: si la OU viene como DN con comas sin comillas, se reconstruye (todo lo que
  venga después de la 7ma columna se une como OU).
- OU por fila: DN completo con comas, nombre corto ("Operaciones") o ruta ("Operaciones/Talcahuano").
- Ancla nombres/rutas bajo OU=Usuarios,DC=agenciaramos,DC=local.
- -CreateOUIfMissing crea la jerarquía que falte.
- Si la OU final no existe y no se permite crear, fallback seguro a la OU por defecto.
- Surname opcional.
- Password alfanumérica (18). No fuerza cambio al primer logon. (Función sin uso de -Count).
- Soporta -UpdateIfExists, -MoveIfExists y -WhatIf.

Uso recomendado (simulación):
.\New-ADUsers_AgenciaRamos.ps1 -CsvPath C:\Temp\usuarios.csv -UpdateIfExists -MoveIfExists -CreateOUIfMissing -WhatIf
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory=$true)]
  [string]$CsvPath,

  # OU por defecto / ancla
  [string]$TargetOU = "OU=Usuarios,DC=agenciaramos,DC=local",

  [switch]$UpdateIfExists,
  [switch]$MoveIfExists,
  [switch]$CreateOUIfMissing
)

$ErrorActionPreference = 'Stop'

# --- Log ---
$LogDir  = 'C:\Logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogPath = Join-Path $LogDir ("AD_CreateUsers_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
function Write-Log {
  param([string]$Msg,[string]$Level='INFO')
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Msg
  Add-Content -Path $LogPath -Value $line
  Write-Host $line
}
Write-Log "Inicio | CSV: $CsvPath | OU por defecto: $TargetOU | CreateOUIfMissing=$CreateOUIfMissing"
if ($WhatIfPreference) { Write-Log "MODO SIMULACIÓN (-WhatIf) activo." 'WARN' }

# --- Módulo AD ---
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
  Write-Log "No se encuentra el módulo ActiveDirectory (RSAT)." 'ERROR'; throw
}
Import-Module ActiveDirectory -ErrorAction Stop

# --- Lector robusto de CSV (reconstruye OU con comas sin comillas) ---
function Read-UsersCsv {
  param([string]$Path)

  if (-not (Test-Path $Path)) { throw "CSV no encontrado: $Path" }

  $lines = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop -ReadCount 0
  $lines = $lines -replace "`r`n","`n" -replace "`r","`n"
  $rows  = $lines -split "`n"
  $rows  = $rows | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($rows.Count -lt 2) { throw "CSV vacío o sin filas de datos." }

  $header = $rows[0].Trim()
  $expectedHeader = 'GivenName,Surname,SamAccountName,Title,Department,DisplayName,UserPrincipalName,OU'
  if ($header -ne $expectedHeader) {
    throw "Cabecera inválida. Se esperaba: $expectedHeader  | Se encontró: $header"
  }

  $result = New-Object System.Collections.Generic.List[object]

  for ($i=1; $i -lt $rows.Count; $i++) {
    $line = $rows[$i]
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $parts = $line.Split(',')
    if ($parts.Count -lt 8) {
      Write-Log "Fila $i inválida (menos de 8 columnas): $line" 'ERROR'
      continue
    }

    $GivenName         = $parts[0].Trim()
    $Surname           = $parts[1].Trim()
    $SamAccountName    = $parts[2].Trim()
    $Title             = $parts[3].Trim()
    $Department        = $parts[4].Trim()
    $DisplayName       = $parts[5].Trim()
    $UserPrincipalName = $parts[6].Trim()
    $OU                = ($parts[7..($parts.Count-1)] -join ',').Trim()

    $GivenName         = ($GivenName         -replace "`t",' ').Trim()
    $Surname           = ($Surname           -replace "`t",' ').Trim()
    $SamAccountName    = ($SamAccountName    -replace "`t",' ').Trim()
    $Title             = ($Title             -replace "`t",' ').Trim()
    $Department        = ($Department        -replace "`t",' ').Trim()
    $DisplayName       = ($DisplayName       -replace "`t",' ').Trim()
    $UserPrincipalName = ($UserPrincipalName -replace "`t",' ').Trim()
    $OU                = ($OU                -replace "`t",' ').Trim()

    $obj = [PSCustomObject]@{
      GivenName         = $GivenName
      Surname           = $Surname
      SamAccountName    = $SamAccountName
      Title             = $Title
      Department        = $Department
      DisplayName       = $DisplayName
      UserPrincipalName = $UserPrincipalName
      OU                = $OU
    }
    $result.Add($obj)
  }

  return $result
}

$rows = Read-UsersCsv -Path $CsvPath
if (-not $rows -or $rows.Count -eq 0) { Write-Log "CSV sin filas válidas." 'ERROR'; throw }

# --- Datos de dominio ---
$DomainDN = (Get-ADDomain).DistinguishedName

# Validar OU por defecto (si no existe y no se permite crear, aborta)
if (-not (Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction SilentlyContinue)) {
  if ($CreateOUIfMissing) {
    Write-Log "OU por defecto no existe; se intentará crear: $TargetOU" 'WARN'
  } else {
    Write-Log "OU por defecto no existe: $TargetOU (usa -CreateOUIfMissing para crearla)" 'ERROR'; throw
  }
}

# --- Utilidades ---
function New-RandomPassword {
  param([int]$Length = 18)  # alfanumérica 18
  if ($Length -lt 3) { throw "La longitud mínima debe permitir 1 mayúscula, 1 minúscula y 1 dígito." }

  $U = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  $L = 'abcdefghijkmnopqrstuvwxyz'
  $D = '23456789'

  function Get-RandChar([string]$s) {
    $idx = Get-Random -Min 0 -Max $s.Length
    return $s[$idx]
  }

  $req = @(
    (Get-RandChar $U),
    (Get-RandChar $L),
    (Get-RandChar $D)
  )

  $pool = $U + $L + $D
  $rest = New-Object System.Collections.Generic.List[char]
  for ($i = 0; $i -lt ($Length - 3); $i++) {
    $rest.Add( (Get-RandChar $pool) ) | Out-Null
  }

  $all = New-Object System.Collections.Generic.List[char]
  $req | ForEach-Object { [void]$all.Add($_) }
  $rest | ForEach-Object { [void]$all.Add($_) }
  for ($i = $all.Count - 1; $i -gt 0; $i--) {
    $j = Get-Random -Min 0 -Max ($i + 1)
    if ($j -ne $i) { $tmp = $all[$i]; $all[$i] = $all[$j]; $all[$j] = $tmp }
  }

  -join $all
}

function Get-UserCurrentOU {
  param([string]$UserDN)
  if ($UserDN -match '^[^,]+,(.+)$') { return $Matches[1] } else { return $null }
}

function Ensure-OU {
  param([string]$OUdn)
  if (Get-ADOrganizationalUnit -Identity $OUdn -ErrorAction SilentlyContinue) { return $true }
  if (-not $CreateOUIfMissing) { return $false }
  try {
    $parts = $OUdn -split ','
    for ($i = ($parts.Count - 1); $i -ge 0; $i--) {
      if ($parts[$i] -notmatch '^OU=') { continue }
      $candidate = ($parts[$i..($parts.Count-1)] -join ',')
      if (-not (Get-ADOrganizationalUnit -Identity $candidate -ErrorAction SilentlyContinue)) {
        $parent = ($parts[($i+1)..($parts.Count-1)] -join ',')
        if ([string]::IsNullOrWhiteSpace($parent)) { $parent = $DomainDN }
        $name = $parts[$i] -replace '^OU='
        if ($PSCmdlet.ShouldProcess($candidate,"Crear OU")) {
          New-ADOrganizationalUnit -Name $name -Path $parent -ProtectedFromAccidentalDeletion:$true -WhatIf:$WhatIfPreference | Out-Null
          Write-Log "OU creada: $candidate"
        }
      }
    }
    return [bool](Get-ADOrganizationalUnit -Identity $OUdn -ErrorAction SilentlyContinue)
  } catch {
    Write-Log "No se pudo crear OU ${OUdn}: $($_.Exception.Message)" 'ERROR'
    return $false
  }
}

function Resolve-OU {
  param(
    [string]$InputOU,
    [string]$DefaultOU,
    [string]$DomainDNParam
  )
  if ([string]::IsNullOrWhiteSpace($InputOU)) { return $DefaultOU }
  $ouStr = $InputOU.Trim()

  if ($ouStr -match ',DC=') { return $ouStr }

  $BaseAnchor = $DefaultOU

  if ($ouStr -like 'OU=*' -and $ouStr -notmatch ',DC=') { return "$ouStr,$BaseAnchor" }

  if ($ouStr -match '[/\\]') {
    $segments = $ouStr -split '[/\\]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $dn = ($segments | ForEach-Object { 'OU=' + $_.Trim() }) -join ','
    return "$dn,$BaseAnchor"
  }

  return "OU=$ouStr,$BaseAnchor"
}

function Get-UsableOU {
  param(
    [string]$PreferredOU,
    [string]$FallbackOU
  )
  if (Get-ADOrganizationalUnit -Identity $PreferredOU -ErrorAction SilentlyContinue) { return $PreferredOU }
  if ($CreateOUIfMissing -and (Ensure-OU -OUdn $PreferredOU)) { return $PreferredOU }
  Write-Log "OU no existe: ${PreferredOU}. Se usará OU por defecto ${FallbackOU} (fallback)." 'WARN'
  if (Get-ADOrganizationalUnit -Identity $FallbackOU -ErrorAction SilentlyContinue) { return $FallbackOU }
  if ($CreateOUIfMissing -and (Ensure-OU -OUdn $FallbackOU)) { return $FallbackOU }
  throw "Ni la OU preferida ni la de fallback existen: Preferred='${PreferredOU}', Fallback='${FallbackOU}'."
}

# --- Proceso principal ---
$created=0; $updated=0; $moved=0; $skipped=0; $errors=0

foreach ($r in $rows) {
  try {
    $allValues = [string]::Join('', @($r.GivenName,$r.Surname,$r.SamAccountName,$r.Title,$r.Department,$r.DisplayName,$r.UserPrincipalName,$r.OU))
    if ([string]::IsNullOrWhiteSpace($allValues)) { continue }

    $GivenName         = ($r.GivenName         -replace "`t",' ').Trim()
    $Surname           = ($r.Surname           -replace "`t",' ').Trim()
    $SamAccountName    = ($r.SamAccountName    -replace "`t",' ').Trim()
    $Title             = ($r.Title             -replace "`t",' ').Trim()
    $Department        = ($r.Department        -replace "`t",' ').Trim()
    $DisplayName       = ($r.DisplayName       -replace "`t",' ').Trim()
    $UserPrincipalName = ($r.UserPrincipalName -replace "`t",' ').Trim()
    $RowOU             = ($r.OU                -replace "`t",' ').Trim()

    if ([string]::IsNullOrWhiteSpace($GivenName) -or
        [string]::IsNullOrWhiteSpace($SamAccountName) -or
        [string]::IsNullOrWhiteSpace($DisplayName) -or
        [string]::IsNullOrWhiteSpace($UserPrincipalName)) {
      $rowText = ($r | ConvertTo-Json -Compress)
      Write-Log "Fila inválida (faltan campos obligatorios). Datos: $rowText" 'ERROR'
      $errors++; continue
    }

    Write-Log "OU (CSV crudo) para ${SamAccountName}: '${RowOU}'"

    $PreferredOU = Resolve-OU -InputOU $RowOU -DefaultOU $TargetOU -DomainDNParam $DomainDN
    $EffectiveOU = Get-UsableOU -PreferredOU $PreferredOU -FallbackOU $TargetOU
    Write-Log "OU final para ${SamAccountName}: ${EffectiveOU}"

    $existing = Get-ADUser -Filter "sAMAccountName -eq '$SamAccountName'" -Properties * -ErrorAction SilentlyContinue

    if ($existing) {
      if ($UpdateIfExists) {
        $setParams = @{
          Identity          = $existing.DistinguishedName
          GivenName         = $GivenName
          Surname           = $Surname
          DisplayName       = $DisplayName
          Title             = $Title
          Department        = $Department
          UserPrincipalName = $UserPrincipalName
          WhatIf            = $WhatIfPreference
          ErrorAction       = 'Stop'
        }
        if ($PSCmdlet.ShouldProcess($SamAccountName,"Actualizar usuario existente")) {
          Set-ADUser @setParams
          Write-Log "Actualizado: $SamAccountName"
          $updated++
        }
      }

      if ($MoveIfExists) {
        $currentOU = Get-UserCurrentOU -UserDN $existing.DistinguishedName
        if ($currentOU -and ($currentOU -ne $EffectiveOU)) {
          if ($PSCmdlet.ShouldProcess($SamAccountName,"Mover a $EffectiveOU (desde $currentOU)")) {
            try {
              Move-ADObject -Identity $existing.DistinguishedName -TargetPath $EffectiveOU -WhatIf:$WhatIfPreference -ErrorAction Stop
              Write-Log "Movido: $SamAccountName  $currentOU  ➜  $EffectiveOU"
              $moved++
            } catch {
              Write-Log "No se pudo mover ${SamAccountName} a ${EffectiveOU}: $($_.Exception.Message)" 'ERROR'
              $errors++
            }
          }
        }
      }

      if (-not $UpdateIfExists -and -not $MoveIfExists) {
        Write-Log "Ya existe, omitido: $SamAccountName"
        $skipped++
      }
      continue
    }

    $pwdPlain  = New-RandomPassword -Length 18
    $pwdSecure = ConvertTo-SecureString -String $pwdPlain -AsPlainText -Force

    $newParams = @{
      Name                  = $DisplayName
      DisplayName           = $DisplayName
      GivenName             = $GivenName
      Surname               = $Surname
      SamAccountName        = $SamAccountName
      UserPrincipalName     = $UserPrincipalName
      Title                 = $Title
      Department            = $Department
      Path                  = $EffectiveOU
      AccountPassword       = $pwdSecure
      Enabled               = $true
      ChangePasswordAtLogon = $false
      WhatIf                = $WhatIfPreference
      ErrorAction           = 'Stop'
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName,"Crear usuario en $EffectiveOU")) {
      New-ADUser @newParams
      Write-Log "Creado: $SamAccountName | UPN: $UserPrincipalName | OU: $EffectiveOU | PassTemp: $pwdPlain"
      $created++
    }

  } catch {
    Write-Log "Error con $($r.SamAccountName): $($_.Exception.Message)" 'ERROR'
    $errors++
  }
}

Write-Log "Resumen -> Creados: $created | Actualizados: $updated | Movidos: $moved | Omitidos: $skipped | Errores: $errors"
Write-Host "`n✅ Log: $LogPath"

# ======== LÍNEAS EXTRA DE VERIFICACIÓN Y REPORTE ========
Get-ADUser -Filter * -SearchBase "OU=Usuarios,DC=agenciaramos,DC=local" -Properties DisplayName,DistinguishedName |
  Select DisplayName,DistinguishedName | Sort DisplayName

Get-ADUser -Filter * -SearchBase "OU=Usuarios,DC=agenciaramos,DC=local" -Properties Title,Department,DisplayName,UserPrincipalName |
  Select DisplayName,SamAccountName,UserPrincipalName,Title,Department,DistinguishedName |
  Export-Csv C:\Logs\AD_Usuarios_Reporte.csv -NoTypeInformation -Encoding UTF8
Write-Host "📄 Reporte exportado a: C:\Logs\AD_Usuarios_Reporte.csv"
