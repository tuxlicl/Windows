<# 
Autor    : PowerShell 🔨🤖🔧
Propósito: Agregar (no reemplazar ni normalizar) direcciones a proxyAddresses de usuarios AD desde un CSV.
Notas    : Usa direcciones EXACTAS del CSV (ya con smtp:/SMTP:), evita duplicados, logging y WhatIf.
#>

[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,                                  # ← EDITABLE: ruta al CSV

    [string]$LogPath = "$(Join-Path $PWD "AddProxyAddresses_$(Get-Date -Format yyyyMMdd_HHmmss).log")",  # ← EDITABLE
    [string]$Server,                                    # ← EDITABLE: opcional, DC específico (ej: dc1.contoso.local)
    [pscredential]$Credential,                          # ← EDITABLE: opcional, credencial alternativa
    [switch]$SkipValidation                             # ← EDITABLE: salta validación de formato de email
)

begin {
    function Write-Log {
        param([string]$Message, [string]$Level = 'INFO')
        $line = "[{0:u}] [{1}] {2}" -f (Get-Date), $Level.ToUpper(), $Message
        $line | Tee-Object -FilePath $LogPath -Append
    }

    function Extract-EmailCore {
        param([string]$addr)
        if ([string]::IsNullOrWhiteSpace($addr)) { return $null }
        $trim = $addr.Trim()
        # Quita prefijo smtp:/SMTP: si viene, solo para validar. NO se modifica lo que se agrega.
        if ($trim -match '^(?i)smtp:') { return $trim.Substring(5) }
        return $trim
    }

    function Test-Email {
        param([string]$addrRaw)
        if ($SkipValidation) { return $true }
        if ([string]::IsNullOrWhiteSpace($addrRaw)) { return $false }
        $pure = Extract-EmailCore $addrRaw
        return ($pure -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
    }

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-Error "No se pudo importar el módulo ActiveDirectory. Error: $($_.Exception.Message)"
        return
    }

    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        Write-Error "CSV no encontrado: $CsvPath"
        return
    }

    Write-Log "==== INICIO ===="
    Write-Log "CSV: $CsvPath"
    Write-Log "Log: $LogPath"
    if ($Server) { Write-Log "Server: $Server" }
    if ($PSCmdlet.WhatIfPreference) { Write-Log "Modo WhatIf: ACTIVADO" }

    try {
        $global:Rows = Import-Csv -LiteralPath $CsvPath
    } catch {
        Write-Error "Error al leer CSV: $($_.Exception.Message)"
        return
    }

    # Verifica columnas mínimas
    $required = @('SamAccountName','Smtp1','Smtp2')
    $missing = $required | Where-Object { -not ($Rows | Get-Member -Name $_ -MemberType NoteProperty) }
    if ($missing) {
        Write-Error "El CSV debe contener las columnas: $($required -join ', '). Faltan: $($missing -join ', ')"
        return
    }

    # Parámetros comunes para cmdlets AD
    $script:ADParams = @{}
    if ($Server)     { $script:ADParams['Server'] = $Server }
    if ($Credential) { $script:ADParams['Credential'] = $Credential }
}

process {
    $total = $Rows.Count
    $idx = 0
    foreach ($row in $Rows) {
        $idx++

        $sam = [string]$row.SamAccountName
        # Toma direcciones EXACTAS del CSV (sin normalizar ni prefijar)
        $raw1 = $row.Smtp1
        $raw2 = $row.Smtp2

        if ([string]::IsNullOrWhiteSpace($sam)) {
            # 🔧 FIX: usar ${idx} porque viene seguido de ":" en la cadena
            Write-Log "Fila ${idx}: SamAccountName vacío. Saltando." "WARN"
            continue
        }

        # Filtra nulos/espacios y dedup del propio CSV
        $cand = @($raw1, $raw2) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() } |
            Select-Object -Unique

        # Valida formato (solo advertencia; no cambia el valor)
        $bad = @()
        foreach ($addr in $cand) {
            if (-not (Test-Email $addr)) { $bad += $addr }
        }
        if ($bad.Count -gt 0) {
            Write-Log "[$sam] Direcciones con formato inusual/ inválido en CSV (se ignoran): $($bad -join '; ')" "WARN"
            # Quitar inválidos para no intentar agregarlos
            $cand = $cand | Where-Object { $bad -notcontains $_ }
            if ($cand.Count -eq 0) {
                Write-Log "[$sam] No quedan direcciones válidas para agregar. Saltando." "WARN"
                continue
            }
        }

        # Trae usuario con proxyAddresses
        try {
            $u = Get-ADUser -Identity $sam -Properties proxyAddresses @ADParams -ErrorAction Stop
        } catch {
            Write-Log "[$sam] Usuario no encontrado o error Get-ADUser: $($_.Exception.Message)" "ERROR"
            continue
        }

        # Conjunto existente (case-insensitive) para evitar duplicados
        $existing = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($e in ($u.proxyAddresses | ForEach-Object { $_ }) ) { $null = $existing.Add($e) }

        # Lista a agregar (solo las que no existan ya)
        $toAdd = New-Object System.Collections.Generic.List[string]
        foreach ($addr in $cand) {
            if (-not $existing.Contains($addr)) {
                $toAdd.Add($addr) | Out-Null
            } else {
                Write-Log "[$sam] Ya existe (se omite): $addr" "INFO"
            }
        }

        if ($toAdd.Count -eq 0) {
            Write-Log "[$sam] Nada que agregar." "INFO"
            continue
        }

        # Ejecuta -Add solo con las nuevas
        $addHash = @{ proxyAddresses = $toAdd.ToArray() }

        $targetDesc = "$sam -> +[$($toAdd -join ', ')]"
        if ($PSCmdlet.ShouldProcess($targetDesc, "Agregar proxyAddresses")) {
            try {
                Set-ADUser -Identity $sam -Add $addHash @ADParams -ErrorAction Stop -WhatIf:$WhatIfPreference
                Write-Log "[$sam] Agregadas: $($toAdd -join ', ')" "INFO"
            } catch {
                Write-Log "[$sam] Error Set-ADUser -Add: $($_.Exception.Message)" "ERROR"
            }
        }
    }
}

end {
    Write-Log "==== FIN ===="
    Write-Host "✅ Listo. Revisa el log en: $LogPath"
}
