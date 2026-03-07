#Requires -RunAsAdministrator

. .\functions_Win.ps1

New-NetFirewallRule -DisplayName "Lab-DNS-UDP"  -Direction Inbound -LocalPort 53 -Protocol UDP    -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-DNS-TCP"  -Direction Inbound -LocalPort 53 -Protocol TCP    -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-Ping-ICMP" -Direction Inbound              -Protocol ICMPv4 -Action Allow -ErrorAction SilentlyContinue | Out-Null

while ($true) {
    Clear-Host
    Write-Host "=========================================="
    Write-Host "              MONITOREO                   "
    Write-Host "=========================================="
    Write-Host "1)  Monitoreo del S.O"
    Write-Host "=========================================="
    Write-Host "    SISTEMA DE ADMINISTRACION DHCP        "
    Write-Host "=========================================="
    Write-Host "2)  Verificar instalacion del Rol"
    Write-Host "3)  Instalar o Reinstalar DHCP"
    Write-Host "4)  Consulta de servicio (Status)"
    Write-Host "5)  Crear / Configurar Ambito DHCP"
    Write-Host "6)  Gestionar (Modificar/Eliminar) Ambito Existente"
    Write-Host "7)  Monitorear IPs asignadas (Leases)"
    Write-Host "=========================================="
    Write-Host "    SISTEMA DE ADMINISTRACION DNS         "
    Write-Host "=========================================="
    Write-Host "8)  Instalar / Reinstalar DNS"
    Write-Host "9)  Alta Dominio DNS"
    Write-Host "10) Baja Dominio DNS"
    Write-Host "11) Listar Dominios DNS"
    Write-Host "=========================================="
    Write-Host "    SISTEMA DE ADMINISTRACION SSH         "
    Write-Host "=========================================="
    Write-Host "12) Instalar SSH"
    Write-Host "13) Reinstalar SSH"
    Write-Host "14) Configurar IP fija"
    Write-Host "15) Monitorear estado SSH"
    Write-Host "=========================================="
    Write-Host "    SISTEMA DE ADMINISTRACION FTP         "
    Write-Host "=========================================="
    Write-Host "16) Inicializar FTP"
    Write-Host "17) Agregar usuario FTP"
    Write-Host "18) Cambiar usuario de grupo"
    Write-Host "19) Reiniciar servicio FTP"
    Write-Host "=========================================="
    Write-Host "0)  Salir"
    Write-Host "=========================================="

    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
        '1'  { Monitoring-vm }
        '2'  { Mostrar-Verificacion }
        '3'  { Instalar-Servicio }
        '4'  { Consultar-Estado }
        '5'  { Configurar-Ambito }
        '6'  { Gestionar-Ambito }
        '7'  { Monitorear-IPs }
        '8'  { Instalar-DNS }
        '9'  { Alta-Dominio }
        '10' { Baja-Dominio }
        '11' { Listar-Dominios }
        '12' { Install-SSHService }
        '13' { Install-SSHService -Reinstall }
        '14' { Set-SSHNetwork }
        '15' { Test-SSHStatus; Read-Host "Presione Enter para volver" }
        '16' { initFTP }
        '17' {
            $num = Read-Host "Ingrese el numero de usuarios a registrar"
            for ($i = 1; $i -le $num; $i++) {
                addUser
                setPermissions
                Pause
            }
        }
        '18' {
            $usuario = Read-Host "Ingrese el nombre del usuario"
            switchGroup -username $usuario
            Pause
        }
        '19' {
            Restart-WebItem "IIS:\Sites\FTP"
            Write-Host "FTP reiniciado correctamente."
            Pause
        }
        '0'  { Clear-Host; Write-Host "Saliendo del sistema..."; exit }
        default {
            Write-Host "Opcion no valida, intente de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
