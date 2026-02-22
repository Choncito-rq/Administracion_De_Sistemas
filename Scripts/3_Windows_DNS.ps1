# ==========================================================
#    SISTEMA DE ADMINISTRACION DHCP Y DNS - REESTRUCTURADO
# ==========================================================

# --- CONFIGURACIÓN INICIAL (Firewall) ---
New-NetFirewallRule -DisplayName "Lab-DNS-UDP" -Direction Inbound -LocalPort 53 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-DNS-TCP" -Direction Inbound -LocalPort 53 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-Ping-ICMP" -Direction Inbound -Protocol ICMPv4 -Action Allow -ErrorAction SilentlyContinue | Out-Null

# --- VARIABLES GLOBALES Y TABLAS ---
$global:MaskCidrTable = @{
    "128.0.0.0" = 1; "192.0.0.0" = 2; "224.0.0.0" = 3; "240.0.0.0" = 4; "248.0.0.0" = 5; "252.0.0.0" = 6; "254.0.0.0" = 7; "255.0.0.0" = 8;
    "255.128.0.0" = 9; "255.192.0.0" = 10; "255.224.0.0" = 11; "255.240.0.0" = 12; "255.248.0.0" = 13; "255.252.0.0" = 14; "255.254.0.0" = 15; "255.255.0.0" = 16;
    "255.255.128.0" = 17; "255.255.192.0" = 18; "255.255.224.0" = 19; "255.255.240.0" = 20; "255.255.248.0" = 21; "255.255.252.0" = 22; "255.255.254.0" = 23; "255.255.255.0" = 24;
    "255.255.255.128" = 25; "255.255.255.192" = 26; "255.255.255.224" = 27; "255.255.255.240" = 28; "255.255.255.248" = 29; "255.255.255.252" = 30; "255.255.255.254" = 31; "255.255.255.255" = 32
}

# --- 1. FUNCIONES DE UTILIDAD Y CONVERSIÓN ---

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

function Get-CidrLength ([string]$Mask) {
    return $global:MaskCidrTable[$Mask]
}

# --- 2. FUNCIONES DE VALIDACIÓN ---

function Test-ValidIP ($IP) {
    if ([string]::IsNullOrWhiteSpace($IP) -or $IP -eq "localhost" -or $IP -eq "127.0.0.0" -or $IP -eq "0.0.0.0") { 
        return $false 
    }
    if ($IP -match "^([0-9]{1,3}\.){3}[0-9]{1,3}$") {
        $ipParsed = $null
        return [System.Net.IPAddress]::TryParse($IP, [ref]$ipParsed)
    }
    return $false
}

function Test-ValidMask ($IP) {
    return $global:MaskCidrTable.ContainsKey($IP)
}

# --- 3. FUNCIONES DEL MÓDULO DHCP ---

function Mostrar-Verificacion {
    Clear-Host
    Write-Host "=== VERIFICACION DE INSTALACION ===" -ForegroundColor Cyan
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    if ($dhcpFeature.Installed) {
        Write-Host "Estado: El rol de Servidor DHCP YA ESTA INSTALADO." -ForegroundColor Green
    } else {
        Write-Host "Estado: El rol de Servidor DHCP NO ESTA INSTALADO." -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Instalar-Servicio {
    Clear-Host
    Write-Host "=== INSTALACION DE ROL DHCP ===" -ForegroundColor Cyan
    $dhcpFeature = Get-WindowsFeature -Name DHCP
    if ($dhcpFeature.Installed) {
        Write-Host "El rol DHCP ya se encuentra instalado en el sistema." -ForegroundColor Yellow
        $resp = Read-Host "Desea REINSTALAR el rol? (Esto desinstalara y volvera a instalar) (s/n)"
        if ($resp -eq 's' -or $resp -eq 'S') {
            Write-Host "[*] Desinstalando rol DHCP..." -ForegroundColor Yellow
            Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
            Write-Host "[*] Reinstalando rol DHCP..." -ForegroundColor Yellow
            Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
            Write-Host "[+] Reinstalacion completada." -ForegroundColor Green
        } else {
            Write-Host "Operacion cancelada."
        }
    } else {
        Write-Host "[*] Instalando rol DHCP de forma desatendida..." -ForegroundColor Yellow
        Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null
        Write-Host "[+] Instalacion completada con exito." -ForegroundColor Green
    }
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Consultar-Estado {
    Clear-Host
    Write-Host "=== ESTADO DEL SERVICIO DHCP ===" -ForegroundColor Cyan
    try {
        $service = Get-Service -Name DHCPServer -ErrorAction Stop
        if ($service.Status -eq 'Running') {
            Write-Host "El servicio esta: ACTIVO Y FUNCIONANDO" -ForegroundColor Green
        } else {
            Write-Host "El servicio esta: DETENIDO ($($service.Status))" -ForegroundColor Red
        }
    } catch {
        Write-Host "El servicio DHCP no existe. Ya instalaste el rol?" -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Configurar-Ambito {
    Clear-Host
    Write-Host "=== CREAR / CONFIGURAR AMBITO DHCP ===" -ForegroundColor Cyan

    $ScopeName = Read-Host "Nombre descriptivo del Ambito"
    if ([string]::IsNullOrWhiteSpace($ScopeName)) { $ScopeName = "Ambito_General" }

    do { 
        $StartIP = Read-Host "Rango Inicial (Ejem: 192.168.100.1)"
        if (-not (Test-ValidIP $StartIP)) { Write-Host "IP invalida o restringida." -ForegroundColor Red }
    } until (Test-ValidIP $StartIP)

    do { 
        $EndIP = Read-Host "Rango Final (Ejem: 192.168.100.50)"
        $isValidIP = Test-ValidIP $EndIP
        $isValidRange = $false

        if ($isValidIP) {
            $IntStart = Convert-IPToUInt32 $StartIP
            $IntEnd = Convert-IPToUInt32 $EndIP
            if ($IntEnd -gt $IntStart) {
                $isValidRange = $true
            } else {
                Write-Host "Error: El Rango Final debe ser mayor al Rango Inicial." -ForegroundColor Red
            }
        } else {
            Write-Host "Formato de IP invalido." -ForegroundColor Red
        }
    } until ($isValidIP -and $isValidRange)

    do { 
        $Mask = Read-Host "Mascara de subred (Ejem: 255.255.255.0)"
        if (-not (Test-ValidMask $Mask)) { Write-Host "Mascara invalida." -ForegroundColor Red }
    } until (Test-ValidMask $Mask)

    do {
        $Lease = Read-Host "Tiempo de concesion en segundos (Minimo 60)"
        $isValidLease = ($Lease -match "^\d+$" -and [int]$Lease -ge 60)
        if (-not $isValidLease) { Write-Host "Error: Debe ser un numero entero mayor o igual a 60." -ForegroundColor Red }
    } until ($isValidLease)

    do {
        $GW = Read-Host "Puerta de Enlace (Enter para dejar vacio)"
        if ([string]::IsNullOrWhiteSpace($GW)) { break }
        if (-not (Test-ValidIP $GW)) { Write-Host "Formato de IP invalido." -ForegroundColor Red }
    } until ([string]::IsNullOrWhiteSpace($GW) -or (Test-ValidIP $GW))

    do {
        $DNS = Read-Host "Servidor DNS (Enter para dejar vacio)"
        if ([string]::IsNullOrWhiteSpace($DNS)) { break }
        if (-not (Test-ValidIP $DNS)) { Write-Host "Formato de IP invalido." -ForegroundColor Red }
    } until ([string]::IsNullOrWhiteSpace($DNS) -or (Test-ValidIP $DNS))

    $NetworkID = Get-NetworkID -IP $StartIP -Mask $Mask
    $ServerIP = $StartIP
    $DhcpStartIP = Convert-UInt32ToIP ((Convert-IPToUInt32 $StartIP) + 1)
    $Cidr = Get-CidrLength $Mask
    $IfName = "Ethernet 2"

    Write-Host "`n[*] Resumen Logico ($ScopeName):" -ForegroundColor Yellow
    Write-Host "- Interfaz objetivo: $IfName"
    Write-Host "- La IP $ServerIP sera asignada a este servidor de forma fija."
    Write-Host "- Los clientes recibiran IPs desde $DhcpStartIP hasta $EndIP."
    Write-Host "- ID Red: $NetworkID / $Cidr"

    Write-Host "`n[*] Configurando IP fija ($ServerIP/$Cidr) en '$IfName'..." -ForegroundColor Yellow
    try {
        Remove-NetIPAddress -InterfaceAlias $IfName -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $IfName -IPAddress $ServerIP -PrefixLength $Cidr -AddressFamily IPv4 -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "Aviso: No se pudo asignar la IP a $IfName. (Es posible que ya este asignada)." -ForegroundColor Yellow
    }

    Write-Host "[*] Creando Ambito DHCP en el servidor..." -ForegroundColor Yellow
    try {
        $TimeSpan = [TimeSpan]::FromSeconds([int]$Lease)
        $exists = Get-DhcpServerv4Scope -ScopeId $NetworkID -ErrorAction SilentlyContinue
        if ($exists) { Remove-DhcpServerv4Scope -ScopeId $NetworkID -Force }

        Add-DhcpServerv4Scope -Name $ScopeName -StartRange $DhcpStartIP -EndRange $EndIP -SubnetMask $Mask -LeaseDuration $TimeSpan -State Active -ErrorAction Stop

        if (-not [string]::IsNullOrWhiteSpace($GW)) {
            Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 3 -Value $GW -Force
        }
        if (-not [string]::IsNullOrWhiteSpace($DNS)) {
            Set-DhcpServerv4OptionValue -ScopeId $NetworkID -OptionId 6 -Value $DNS -Force
        }

        Restart-Service DHCPServer -ErrorAction SilentlyContinue
        Write-Host "[+] SERVICIO DHCP CONFIGURADO Y ACTIVO." -ForegroundColor Green
    } catch {
        Write-Host "[!] Error critico al crear el ambito: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Gestionar-Ambito {
    Clear-Host
    Write-Host "=== ELIMINAR O MODIFICAR AMBITO EXISTENTE ===" -ForegroundColor Cyan

    $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if (-not $ambitos) {
        Write-Host "No hay ambitos configurados en este servidor." -ForegroundColor Yellow
        Read-Host "Presione ENTER para continuar"
        return
    }

    $ambitos | Select-Object ScopeId, Name, StartRange, EndRange, State | Format-Table -AutoSize
    $TargetId = Read-Host "Ingrese la 'ScopeId' (ID de Red) del ambito a gestionar"

    $ambito = Get-DhcpServerv4Scope -ScopeId $TargetId -ErrorAction SilentlyContinue
    if (-not $ambito) {
        Write-Host "Ambito no encontrado." -ForegroundColor Red
        Read-Host "Presione ENTER para continuar"
        return
    }

    Write-Host "`nQue desea hacer con el ambito $($ambito.Name)?"
    Write-Host "1) Eliminar por completo"
    Write-Host "2) Modificar nombre descriptivo"
    Write-Host "3) Cancelar"
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        '1' {
            Remove-DhcpServerv4Scope -ScopeId $TargetId -Force
            Write-Host "[-] Ambito eliminado correctamente." -ForegroundColor Green
        }
        '2' {
            $nuevoNombre = Read-Host "Ingrese el nuevo nombre"
            Set-DhcpServerv4Scope -ScopeId $TargetId -Name $nuevoNombre
            Write-Host "[+] Nombre actualizado." -ForegroundColor Green
        }
        '3' { return }
        default { Write-Host "Opcion invalida." -ForegroundColor Red }
    }
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Monitorear-IPs {
    Clear-Host
    Write-Host "=== IPs ASIGNADAS ACTUALMENTE (LEASES) ===" -ForegroundColor Cyan

    $ambitos = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($ambitos) {
        foreach ($ambito in $ambitos) {
            Write-Host "`n>> Ambito: $($ambito.ScopeId) ($($ambito.Name))" -ForegroundColor Yellow
            $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
            if ($leases) {
                $leases | Select-Object IPAddress, HostName, ClientId | Format-Table -AutoSize
            } else {
                Write-Host "  No hay equipos conectados en este ambito." -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "No hay ambitos configurados." -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Presione ENTER para volver al menu"
}

# --- 4. FUNCIONES DEL MÓDULO DNS ---

function Instalar-DNS {
    Clear-Host
    Write-Host "=== INSTALACION DE ROL DNS ===" -ForegroundColor Cyan

    $dnsFeature = Get-WindowsFeature -Name DNS
    if ($dnsFeature.Installed) {
        Write-Host "El rol DNS ya esta instalado." -ForegroundColor Yellow
        $resp = Read-Host "Desea REINSTALAR el rol DNS? (s/n)"
        if ($resp -match "^[sS]$") {
            Uninstall-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
            Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
            Write-Host "DNS reinstalado correctamente." -ForegroundColor Green
        }
    } else {
        Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
        Write-Host "DNS instalado correctamente." -ForegroundColor Green
    }
    Read-Host "Presione ENTER para continuar"
}

function Alta-Dominio {
    Clear-Host
    Write-Host "=== CREACION DE DOMINIO DNS ===" -ForegroundColor Cyan

    $Dominio = Read-Host "Introduce el nombre del dominio (ej. reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($Dominio)) {
        Write-Host "[!] El nombre de dominio no puede estar vacio." -ForegroundColor Red
        Read-Host "Presione ENTER para continuar"; return
    }

    $ServerIP = Read-Host "Introduce la IP a la que apuntara (ej. 192.168.100.21)"
    if (-not (Test-ValidIP $ServerIP)) {
        Write-Host "[!] La IP ingresada no es valida." -ForegroundColor Red
        Read-Host "Presione ENTER para continuar"; return
    }

    try {
        if (Get-DnsServerZone -Name $Dominio -ErrorAction SilentlyContinue) {
            Remove-DnsServerZone -Name $Dominio -Force
        }
        Write-Host "[*] Creando archivo de zona y registros..." -ForegroundColor Yellow
        Add-DnsServerPrimaryZone -Name $Dominio -ZoneFile "$Dominio.dns"
        Add-DnsServerResourceRecordA -ZoneName $Dominio -Name "@" -IPv4Address $ServerIP
        Add-DnsServerResourceRecordCName -ZoneName $Dominio -Name "www" -HostNameAlias "$Dominio."
        Write-Host "[OK] Zona '$Dominio' creada con exito." -ForegroundColor Green
        Clear-DnsServerCache -Force
    } catch {
        Write-Host "[ERROR] Al configurar DNS: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Presione ENTER para continuar"
}

function Baja-Dominio {
    Clear-Host
    Write-Host "=== ELIMINAR DOMINIO DNS ===" -ForegroundColor Cyan

    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue |
             Where-Object { $_.ZoneType -eq "Primary" -and $_.ZoneName -notmatch "in-addr.arpa" -and $_.ZoneName -ne "TrustAnchors" }

    if (-not $zonas) {
        Write-Host "No existen dominios creados manualmente." -ForegroundColor Yellow
        Read-Host "ENTER para continuar"; return
    }

    foreach ($zona in $zonas) {
        $record = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -ErrorAction SilentlyContinue | Where-Object {$_.HostName -eq "@"}
        $ip = if ($record) { $record.RecordData.IPv4Address.IPAddressToString } else { "Sin IP" }
        Write-Host "$($zona.ZoneName)  ->  IP: $ip"
    }

    $nombreDominio = Read-Host "Escriba el NOMBRE del dominio a eliminar"
    $zonaEncontrada = $zonas | Where-Object { $_.ZoneName -eq $nombreDominio }

    if (-not $zonaEncontrada) {
        Write-Host "El dominio no existe." -ForegroundColor Red
        Read-Host "ENTER para continuar"; return
    }

    if ((Read-Host "Seguro que desea eliminar $nombreDominio ? (s/n)") -match "^[sS]$") {
        Remove-DnsServerZone -Name $nombreDominio -Force
        Write-Host "Dominio eliminado correctamente." -ForegroundColor Green
    }
    Read-Host "ENTER para continuar"
}

function Listar-Dominios {
    Clear-Host
    Write-Host "=== DOMINIOS CONFIGURADOS ===" -ForegroundColor Cyan
    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue |
             Where-Object { $_.ZoneType -eq "Primary" -and $_.ZoneName -notmatch "in-addr.arpa" -and $_.ZoneName -ne "TrustAnchors" }

    if (-not $zonas) {
        Write-Host "No hay dominios creados manualmente." -ForegroundColor Yellow
    } else {
        foreach ($zona in $zonas) {
            $record = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -ErrorAction SilentlyContinue | Where-Object {$_.HostName -eq "@"}
            $ip = if ($record) { $record.RecordData.IPv4Address.IPAddressToString } else { "Sin IP" }
            Write-Host "Dominio: $($zona.ZoneName)  ->  IP: $ip"
        }
    }
    Read-Host "ENTER para continuar"
}

# --- 5. BUCLE PRINCIPAL (MENÚ) ---

while ($true) {
    Clear-Host
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      SISTEMA DE ADMINISTRACION DHCP      " -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "1) Verificar instalacion del Rol"
    Write-Host "2) Instalar o Reinstalar DHCP"
    Write-Host "3) Consulta de servicio (Status)"
    Write-Host "4) Crear / Configurar Ambito DHCP"
    Write-Host "5) Gestionar (Modificar/Eliminar) Ambito Existente"
    Write-Host "6) Monitorear IPs asignadas (Leases)"
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "      SISTEMA DE ADMINISTRACION DNS       "
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "7) Instalar / Reinstalar DNS"
    Write-Host "8) Alta Dominio DNS"
    Write-Host "9) Baja Dominio DNS"
    Write-Host "10) Listar Dominios DNS"
    Write-Host "0) Salir"
    Write-Host "==========================================" -ForegroundColor Cyan
    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
        '1' { Mostrar-Verificacion }
        '2' { Instalar-Servicio }
        '3' { Consultar-Estado }
        '4' { Configurar-Ambito }
        '5' { Gestionar-Ambito }
        '6' { Monitorear-IPs }
        '7' { Instalar-DNS }
        '8' { Alta-Dominio }
        '9' { Baja-Dominio }
        '10' { Listar-Dominios }
        '0' { Clear-Host; Write-Host "Saliendo del sistema..."; exit }
        default {
            Write-Host "Opcion no valida, intente de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
