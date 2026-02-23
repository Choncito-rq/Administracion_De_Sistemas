#Requires -RunAsAdministrator

#Monitoring

# -------------------------------------------------------------------------------------------------- Monitoreo del S.O

function Monitoring-vm {
   Write-Host "===== DIAGNOSTICO DEL SISTEMA ====="

   Write-Host "Nombre del equipo:"
   hostname

   Write-Host ""
   Write-Host "Direcciones IP:"
   ipconfig

   Write-Host ""
   Write-Host "Espacio en disco:"
   Get-PSDrive C
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------- Validaciones

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

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#DHCP Funtions

# -------------------------------------------------------------------------------------------------- Consulta/Instalación/Estado

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

# -------------------------------------------------------------------------------------------------- Crear ámbito

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

# -------------------------------------------------------------------------------------------------- Gestionar ambitos

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

# -------------------------------------------------------------------------------------------------- Monitoreo del DHCP

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

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#DNS Funtions

# -------------------------------------------------------------------------------------------------- Instalacion/Obtencion DHCP

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

function Obtener-Rango-DHCP {

    $ambito = Get-DhcpServerv4Scope | Select-Object -First 1
    if (-not $ambito) { return $null }

    return @{
        Start = $ambito.StartRange
        End   = $ambito.EndRange
        Scope = $ambito.ScopeId
    }
}

function Obtener-IP-Libre-DNS {

    $rango = Obtener-Rango-DHCP
    if (-not $rango) { return $null }

    $start = Convert-IPToUInt32 $rango.Start
    $end   = Convert-IPToUInt32 $rango.End

    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue |
             Where-Object {$_.ZoneType -eq "Primary"}

    $ipsUsadas = @()

    foreach ($zona in $zonas) {
        $record = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -ErrorAction SilentlyContinue |
                  Where-Object {$_.HostName -eq "@"}
        if ($record) {
            $ipsUsadas += Convert-IPToUInt32 $record.RecordData.IPv4Address.IPAddressToString
        }
    }

    for ($i = $start; $i -le $end; $i++) {
        if ($ipsUsadas -notcontains $i) {
            return Convert-UInt32ToIP $i
        }
    }

    return $null
}

# -------------------------------------------------------------------------------------------------- Alta/Baja/Consultado

function Alta-Dominio {
    Clear-Host
    Write-Host "=== CREACION DE DOMINIO DNS ===" -ForegroundColor Cyan

    # 1. Pedir el nombre del dominio
    $Dominio = Read-Host "Introduce el nombre del dominio (ej. reprobados.com)"

    if ([string]::IsNullOrWhiteSpace($Dominio)) {
        Write-Host "[!] El nombre de dominio no puede estar vacio." -ForegroundColor Red
        Read-Host "Presione ENTER para continuar"
        return
    }

    # 2. Pedir la IP destino y validarla
    $ServerIP = Read-Host "Introduce la IP a la que apuntara (ej. 192.168.100.21)"

    if (-not (Test-ValidIP $ServerIP)) {
        Write-Host "[!] La IP ingresada no es valida o tiene un formato incorrecto." -ForegroundColor Red
        Read-Host "Presione ENTER para continuar"
        return
    }

    try {
        # Si la zona ya existe, la borramos para recrearla limpia
        if (Get-DnsServerZone -Name $Dominio -ErrorAction SilentlyContinue) {
            Remove-DnsServerZone -Name $Dominio -Force
        }

        Write-Host "[*] Creando archivo de zona y registros..." -ForegroundColor Yellow

        # Crear Zona Primaria
        Add-DnsServerPrimaryZone -Name $Dominio -ZoneFile "$Dominio.dns"

        # Crear Registro @ (Raíz)
        Add-DnsServerResourceRecordA -ZoneName $Dominio -Name "@" -IPv4Address $ServerIP

        # Crear Registro www (CNAME)
        Add-DnsServerResourceRecordCName -ZoneName $Dominio -Name "www" -HostNameAlias "$Dominio."

        Write-Host "[OK] Zona '$Dominio' creada con exito." -ForegroundColor Green
        Write-Host "[OK] Registros A y CNAME apuntando a $ServerIP." -ForegroundColor Green

        # Reiniciar caché DNS local para que tome los cambios de inmediato
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
             Where-Object {
                 $_.ZoneType -eq "Primary" -and
                 $_.ZoneName -notmatch "in-addr.arpa" -and
                 $_.ZoneName -ne "TrustAnchors"
             }

    if (-not $zonas) {
        Write-Host "No existen dominios creados manualmente." -ForegroundColor Yellow
        Read-Host "ENTER para continuar"
        return
    }

    foreach ($zona in $zonas) {

        $record = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -ErrorAction SilentlyContinue |
                  Where-Object {$_.HostName -eq "@"}

        $ip = if ($record) {
            $record.RecordData.IPv4Address.IPAddressToString
        } else {
            "Sin IP"
        }

        Write-Host "$($zona.ZoneName)  ->  IP: $ip"
    }

    $nombreDominio = Read-Host "Escriba el NOMBRE del dominio a eliminar"

    $zonaEncontrada = $zonas | Where-Object { $_.ZoneName -eq $nombreDominio }

    if (-not $zonaEncontrada) {
        Write-Host "El dominio no existe o no es valido." -ForegroundColor Red
        Read-Host "ENTER para continuar"
        return
    }

    $confirmar = Read-Host "Seguro que desea eliminar $nombreDominio ? (s/n)"

    if ($confirmar -match "^[sS]$") {
        Remove-DnsServerZone -Name $nombreDominio -Force
        Write-Host "Dominio eliminado correctamente." -ForegroundColor Green
    }
    else {
        Write-Host "Operacion cancelada."
    }

    Read-Host "ENTER para continuar"
}

function Listar-Dominios {

    Clear-Host
    Write-Host "=== DOMINIOS CONFIGURADOS ===" -ForegroundColor Cyan

    $zonas = Get-DnsServerZone -ErrorAction SilentlyContinue |
             Where-Object {
                 $_.ZoneType -eq "Primary" -and
                 $_.ZoneName -notmatch "in-addr.arpa" -and
                 $_.ZoneName -ne "TrustAnchors"
             }

    if (-not $zonas) {
        Write-Host "No hay dominios creados manualmente." -ForegroundColor Yellow
    }
    else {
        foreach ($zona in $zonas) {

            $record = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -ErrorAction SilentlyContinue |
                      Where-Object {$_.HostName -eq "@"}

            $ip = if ($record) {
                $record.RecordData.IPv4Address.IPAddressToString
            } else {
                "Sin IP"
            }

            Write-Host "Dominio: $($zona.ZoneName)  ->  IP: $ip"
        }
    }

    Read-Host "ENTER para continuar"
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#SSH Funtions

# -------------------------------------------------------------------------------------------------- Instalacion

function Install-SSHService {
    param([switch]$Reinstall)

    if ($Reinstall) {
        Write-Host "[*] Eliminando OpenSSH Server para reinstalación..." 
        Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    }

    Write-Host "[*] Comprobando capacidad de OpenSSH Server..." -ForegroundColor Cyan
    $check = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
    
    if ($check.State -ne 'Installed') {
        Write-Host "[*] Instalando OpenSSH Server..." -ForegroundColor Yellow
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    }

    Write-Host "[*] Configurando servicio en inicio automático..." -ForegroundColor Cyan
    Set-Service -Name sshd -StartupType 'Automatic'
    Start-Service sshd -ErrorAction SilentlyContinue

    # Asegurar regla de Firewall
    if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
    }
    
    Write-Host "[+] Servicio SSH listo y activo." -ForegroundColor Green
}

# -------------------------------------------------------------------------------------------------- Configurar SSH

function Set-SSHNetwork {
   $IfName = "Ethernet 2"
   Write-Host "======= Configuracion de red ========"

   do { 
        $NuevaIP = Read-Host "Rango Inicial (Ejem: 192.168.100.1)"
        if (-not (Test-ValidIP $NuevaIP)) { Write-Host "IP invalida o restringida" }
    } until (Test-ValidIP $NuevaIP)

   $Mascara = Read-Host "Ingrese el prefijo (ponle 24) "

   Write-Host "[*] Limpiando configuraciones previas en $IfName ..."
   Get-NetIPAddress -InterfaceAlias $IfName -AddressFamily IPv4 | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

   Write-Host "[*] Asignando nueva IP: $NuevaIP/$Mascara ..."
   try{
       New-NetIPAddress -InterfaceAlias $IfName -IPAddress $NuevaIP -PrefixLength $Mascara -AddressFamily IPv4 -ErrorAction Stop | Out-Null
       Write-Host "[+] Red configurada exitosamente"
      } catch {
       Write-Host "[D:] Error al asignar IP: $($_.Exception.Message)"
    }
}

# -------------------------------------------------------------------------------------------------- Monitorear SSH

function Test-SSHStatus {
    Clear-Host
    Write-Host "======== Verificacion de conexion ========"
    $service = Get-Service sshd -ErrorAction SilentlyContinue
    $firewall = Get-NetFirewallRule -Enabled True | Where-Object { $_.LocalPort -eq 22 -or $_.DisplayName -match "OpenSSH" } | Select-Object -First 1
    $interface = "Ethernet 2"
    $ipData = Get-NetIPAddress -InterfaceAlias $interface -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $ip = if ($ipData) { $ipData.IPAddress } else { "No asignada" }

    Write-Host "Estado del servicio:      " -NoNewline
    if ($service.Status -eq 'Running') { Write-Host "Running" } else { Write-Host "Detenido" }

#-----------------------------------------------------
Write-Host "Puerto 22 Abierto:            " -NoNewline
    if ($firewall) { Write-Host "SÍ" -ForegroundColor Green } else { Write-Host "NO" }

    Write-Host "IP de escucha:            " -NoNewline; Write-Host "$ip"
}
