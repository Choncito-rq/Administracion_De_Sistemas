#Requires -RunAsAdministrator

. .\funtions_Win.ps1

New-NetFirewallRule -DisplayName "Lab-DNS-UDP" -Direction Inbound -LocalPort 53 -Protocol UDP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-DNS-TCP" -Direction Inbound -LocalPort 53 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "Lab-Ping-ICMP" -Direction Inbound -Protocol ICMPv4 -Action Allow -ErrorAction SilentlyContinue | Out-Null

while ($true) {
    Clear-Host
    Write-Host "==========================================" 
    Write-Host "                MONITOREO                 "
    Write-Host "=========================================="
    Write-Host "0) Monitoreo del S.O"
    Write-Host "==========================================" 
    Write-Host "      SISTEMA DE ADMINISTRACION DHCP      "
    Write-Host "=========================================="
    Write-Host ""
    Write-Host "1) Verificar instalacion del Rol"
    Write-Host "2) Instalar o Reinstalar DHCP"
    Write-Host "3) Consulta de servicio (Status)"
    Write-Host "4) Crear / Configurar Ambito DHCP"
    Write-Host "5) Gestionar (Modificar/Eliminar) Ambito Existente"
    Write-Host "6) Monitorear IPs asignadas (Leases)"
    Write-Host "=========================================="
    Write-Host "      SISTEMA DE ADMINISTRACION DNS       "
    Write-Host "=========================================="
    Write-Host "7) Instalar / Reinstalar DNS"
    Write-Host "8) Alta Dominio DNS"
    Write-Host "9) Baja Dominio DNS"
    Write-Host "10) Listar Dominios DNS"
    Write-Host "0) Salir"
    Write-Host "=========================================="
    $op = Read-Host "Seleccione una opcion"

    switch ($op) {
	'0' { Monitoring-vm }
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
        '11' { Clear-Host; Write-Host "Saliendo del sistema..."; exit }
        default {
            Write-Host "Opcion no valida, intente de nuevo." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
