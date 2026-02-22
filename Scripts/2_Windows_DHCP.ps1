#Requires -RunAsAdministrator

function Convert-IPToUInt32 ([string]$IP) {
    $bytes = ([System.Net.IPAddress]$IP).GetAddressBytes()
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIP ([uint32]$IPValue) {
    $bytes = [BitConverter]::GetBytes($IPValue)
    if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($bytes) }
    return ([System.Net.IPAddress]$bytes).ToString()
}

function Get-NetworkID {
    param([string]$IP, [string]$Mask)
    $ipB = ([System.Net.IPAddress]$IP).GetAddressBytes()
    $maskB = ([System.Net.IPAddress]$Mask).GetAddressBytes()
    $netB = New-Object byte[] 4
    for ($i=0; $i -lt 4; $i++) { $netB[$i] = $ipB[$i] -band $maskB[$i] }
    return ([System.Net.IPAddress]$netB).ToString()
}

# --- FUNCIÓN CORREGIDA: BLOQUEA SOLO .0 y .1 ---
function Test-ValidIP ($IP) {
    # 1. Validación de nulos o localhost genérico
    if ([string]::IsNullOrWhiteSpace($IP) -or $IP -eq "localhost") { return $false }

    # 2. BLOQUEO ESPECÍFICO (Solo .0 y .1)
    if ($IP -eq "127.0.0.1" -or $IP -eq "127.0.0.0" -or $IP -eq "0.0.0.0" -or $IP -eq "255.255.255.255") {
        return $false
    }
    
    # 3. Validación de formato y octetos (0-255)
    if ($IP -match "^([0-9]{1,3}\.){3}[0-9]{1,3}$") {
        $ipParsed = $null
        $success = [System.Net.IPAddress]::TryParse($IP, [ref]$ipParsed)
        if ($success) {
            $octetos = $IP.Split('.')
            foreach ($o in $octetos) { if ([int]$o -gt 255) { return $false } }
            return $true # Aquí ya permite cualquier otra IP como 127.0.0.2, etc.
        }
    }
    return $false
}

$global:MaskCidrTable = @{
    "128.0.0.0" = 1; "192.0.0.0" = 2; "224.0.0.0" = 3; "240.0.0.0" = 4; "248.0.0.0" = 5; "252.0.0.0" = 6; "254.0.0.0" = 7; "255.0.0.0" = 8;
    "255.128.0.0" = 9; "255.192.0.0" = 10; "255.224.0.0" = 11; "255.240.0.0" = 12; "255.248.0.0" = 13; "255.252.0.0" = 14; "255.254.0.0" = 15; "255.255.0.0" = 16;
    "255.255.128.0" = 17; "255.255.192.0" = 18; "255.255.224.0" = 19; "255.255.240.0" = 20; "255.255.248.0" = 21; "255.255.252.0" = 22; "255.255.254.0" = 23; "255.255.255.0" = 24;
    "255.255.255.128" = 25; "255.255.255.192" = 26; "255.255.255.224" = 27; "255.255.255.240" = 28; "255.255.255.248" = 29; "255.255.255.252" = 30; "255.255.255.254" = 31; "255.255.255.255" = 32
}

function Test-ValidMask ($IP) {
    return $global:MaskCidrTable.ContainsKey($IP)
}

function Get-CidrLength ([string]$Mask) {
    return $global:MaskCidrTable[$Mask]
}

function Gestionar-Rol-DHCP {
    Clear-Host
    Write-Host "`t    VERIFICACION E INSTALACION"
    Write-Host "================================================"
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    
    if ($dhcpFeature.Installed) {
        Write-Host "Estado: El rol de Servidor DHCP YA ESTA INSTALADO"
        $resp = Read-Host "Desea REINSTALAR el rol? (s/n)"
        if ($resp -eq 's' -or $resp -eq 'S') {
            Write-Host "[*] Desinstalando rol DHCP..."
            Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
            Write-Host "[*] Reinstalando rol DHCP..."
            Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
            Write-Host "[+] Reinstalacion completada."
        }
    } else {
        Write-Host "Estado: El rol de Servidor DHCP NO ESTA INSTALADO"
        $resp = Read-Host "Desea instalarlo ahora? (s/n)"
        if ($resp -eq 's' -or $resp -eq 'S') {
            Write-Host "[*] Instalando rol DHCP..."
            Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
            Write-Host "[+] Instalacion completada."
        }
    }
    Read-Host "`t`tPresione ENTER para continuar"
}

function Consultar-Estado {
    Clear-Host
    Write-Host "`t     ESTADO DEL SERVICIO DHCP"
    Write-Host "================================================"
    try {
        $service = Get-Service -Name DHCPServer -ErrorAction Stop
        Write-Host "El servicio esta: $($service.Status)"
    } catch {
        Write-Host "El servicio DHCP no existe o no esta instalado."
    }
    Read-Host "`t`tPresione ENTER para continuar"
}

function Menu-Gestion-Ambitos {
    Clear-Host
    Write-Host "`t        GESTION DE DHCP"
    Write-Host "================================================"
    $crear = Read-Host "Desea CREAR un nuevo ambito? (s/n)"
    
    if ($crear -eq 's' -or $crear -eq 'S') {
        $ScopeName = Read-Host "Nombre descriptivo del Ambito"
        if ([string]::IsNullOrWhiteSpace($ScopeName)) { $ScopeName = "Ambito_General" }

        do { $StartIP = Read-Host "IP Rango Inicial (IP Servidor): "; if (-not (Test-ValidIP $StartIP)) { Write-Host "IP invalida o reservada." } } until (Test-ValidIP $StartIP)
        do { 
            $EndIP = Read-Host "IP Rango Final: "
            $isValidIP = Test-ValidIP $EndIP
            $isValidRange = if ($isValidIP) { (Convert-IPToUInt32 $EndIP) -gt (Convert-IPToUInt32 $StartIP) } else { $false }
            if (-not $isValidRange) { Write-Host "Rango invalido." }
        } until ($isValidIP -and $isValidRange)

        do { $Mask = Read-Host "Mascara de subred: "; if (-not (Test-ValidMask $Mask)) { Write-Host "Mascara invalida." } } until (Test-ValidMask $Mask)
        do { $Lease = Read-Host "Segundos de concesion (Lease)"; $isValidLease = ($Lease -match "^\d+$" -and [int]$Lease -ge 60) } until ($isValidLease)

        $GW = Read-Host "Puerta de Enlace (Enter para omitir)"
        $DNS = Read-Host "Servidor DNS (Enter para omitir)"

        $NetworkID = Get-NetworkID -IP $StartIP -Mask $Mask
        $IfName = "Ethernet 2"
        $DhcpStartIP = Convert-UInt32ToIP ((Convert-IPToUInt32 $StartIP) + 1)
        $Cidr = Get-CidrLength $Mask

        try {
            New-NetIPAddress -InterfaceAlias $IfName -IPAddress $StartIP -PrefixLength $Cidr -ErrorAction SilentlyContinue | Out-Null
            $TimeSpan = [TimeSpan]::FromSeconds([int]$Lease)
            if (Get-DhcpServerv4Scope -ScopeId $NetworkID -ErrorAction SilentlyContinue) { Remove-DhcpServerv4Scope -ScopeId $NetworkID -Force }
            Add-DhcpServerv4Scope -Name $ScopeName -StartRange $DhcpStartIP -EndRange $EndIP -SubnetMask $Mask -LeaseDuration $TimeSpan -State Active
            if ($GW) { Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 3 -Value $GW -Force }
            if ($DNS) { Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 6 -Value $DNS -Force }
            Restart-Service DHCPServer -ErrorAction SilentlyContinue
            Write-Host "[+] Ambito configurado con exito."
        } catch { Write-Host "[!] Error: $($_.Exception.Message)" }
    }

    Write-Host "`t      Ambitos Actuales"
    Write-Host "================================================="
    $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($ambitos) {
        $ambitos | Select-Object ScopeId, Name, State | Format-Table -AutoSize
        $TargetId = Read-Host "Ingrese ScopeId para eliminar/modificar (Enter para omitir)"
        if (-not [string]::IsNullOrWhiteSpace($TargetId)) {
            Write-Host "1) Eliminar | 2) Renombrar | 3) Salir"
            $accion = Read-Host "Accion"
            if ($accion -eq '1') { Remove-DhcpServerv4Scope -ScopeId $TargetId -Force; Write-Host "Eliminado." }
            elseif ($accion -eq '2') { $n = Read-Host "Nuevo nombre"; Set-DhcpServerv4Scope -ScopeId $TargetId -Name $n; Write-Host "Actualizado." }
        }
    } else { Write-Host "No hay ambitos registrados." }
    
    Read-Host "`t`t Presione ENTER para continuar"
}

function Monitorear-IPs {
    Clear-Host
    Write-Host "`t      Conexiones Activas"
    Write-Host "================================================="
    $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($ambitos) {
        foreach ($a in $ambitos) {
            Write-Host "Ambito: $($a.ScopeId)"
            $l = Get-DhcpServerv4Lease -ScopeId $a.ScopeId -ErrorAction SilentlyContinue
            if ($l) { $l | Select-Object IPAddress, HostName, ClientId | Format-Table } else { Write-Host "  Sin concesiones activas." }
        }
    }
    Read-Host "`nPresione ENTER para volver"
}

while ($true) {
    Clear-Host
    Write-Host "================================================="
    Write-Host "		ADMINISTRACION DHCP"
    Write-Host "================================================="
    Write-Host "1) Verificar e Instalar Rol DHCP"
    Write-Host "2) Status del Servicio"
    Write-Host "3) Monitorear IPs asignadas"
    Write-Host "4) Gestionar Ambitos"
    Write-Host "5) Salir"
    Write-Host "=========================================="
    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
        '1' { Gestionar-Rol-DHCP }
        '2' { Consultar-Estado }
        '3' { Monitorear-IPs }
        '4' { Menu-Gestion-Ambitos }
        '5' { exit }
        default { Write-Host "Opcion invalida."; Start-Sleep 1 }
    }
}
