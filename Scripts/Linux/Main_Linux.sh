#!/bin/bash

INTERFAZ="enp0s8"
source ./Funtions_Linux.sh

if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecute este script como root (sudo)."
  exit
fi

submenu_dhcp() {
    while true; do
        clear
        echo "=== MENU DHCP ==="
        echo "1. Instalar Servicio"
        echo "2. Configurar (Scope y Red)"
        echo "3. Monitorear Estado"
        echo "4. Volver al menú principal"
        read -p "Opción: " op
        case $op in
            1) instalar_dhcp ;;
            2) configurar_dhcp ;;
            3) monitorear_dhcp ;;
            4) return ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

submenu_dns() {
    while true; do
        clear
        echo "=== MENU DNS (ABC) ==="
        echo "1. Instalar BIND9"
        echo "2. Alta de Dominio"
        echo "3. Baja de Dominio"
        echo "4. Consultar Dominio"
        echo "5. Listar Dominios"
        echo "6. Volver"
        read -p "Opción: " op
        case $op in
            1) instalar_dns ;;
            2) agregar_dominio ;;
            3) eliminar_dominio ;;
            4) consultar_dominio ;;
            5) listar_dominios ;;
            6) return ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

submenu_ssh(){
  clear
    echo "========================================"
    echo "    	    ADMINISTRACIÓN SSH"
    echo "========================================"
    echo "1) Instalar SSH Server"
    echo "2) Reinstalar SSH Server"
    echo "3) Configurar IP Fija (Netplan)"
    echo "4) Verificar Estado y Red"
    echo "0) Salir"
    echo "----------------------------------------"
    read -p "Seleccione una opcion: " op

    case $op in
        1) instalar_ssh "false" ;;
        2) instalar_ssh "true" ;;
        3) configurar_red_linux ;;
        4) verificar_estado_linux; read -p "Presione ENTER para volver" ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) echo -e "\033[0;31mOpción inválida.\033[0m"; sleep 1 ;;
    esac
}

showMenuftp() {
    clear
    echo ""
    echo "================================================="
    echo "             FTP Linux Administrator"
    echo "================================================="
    echo ""
    echo "Seleccione....."
    echo ""
    echo "1) Ver estado del servicio FTP"
    echo "2) Instalar y configurar vsftpd"
    echo "3) Registrar usuarios"
    echo "4) Cambiar grupo de usuario"
    echo "0) Salir"
    echo ""
    echo ""
}

submenu_ftp() {
    # Verificar que es root o tiene sudo
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        echo "Este script requiere permisos sudo"
        exit 1
    fi

    # Crear archivo de log si no existe
    sudo touch "$LOG_FILE" 2>/dev/null || true
    sudo chmod 644 "$LOG_FILE" 2>/dev/null || true

    # Bucle principal
    while :; do
        showMenuftp
        read -p "Selecciona una opcion: " opc

        case "$opc" in
            1)
                showStatus
                ;;
            2)
                installFTP
                ;;
            3)
                registerUsers
                ;;
            4)
                switchGroupMenu
                ;;
            0)
                echo ""
                echo "Saliendo..."
                exit 0
                ;;
            *)
                echo ""
                echo "Opcion invalida"
                read -p "Presiona Enter para continuar..."
                ;;
        esac
    done
}

# ==========================================
#             MENU PRINCIPAL
# ==========================================

while true; do
    clear
    echo "================================="
    echo "   ADMINISTRACIÓN DE SERVICIOS   "
    echo "================================="
    echo "0) Monitoreo"
    echo "1) Administración DHCP"
    echo "2) Administración DNS"
    echo "3) Administración SSH"
    echo "4) Administración FTP"
    echo "5) Salir"
    read -p "Seleccione una opcion: " opcion_main
    
    case $opcion_main in
        0) Monitoring_vm ;;
        1) submenu_dhcp ;;
        2) submenu_dns ;;
        3) submenu_ssh ;;
        4) submenu_ftp ;;
        5) echo "Saliendo..."; exit 0 ;;
        *) echo "Opcion invalida"; read -p "..." ;;
    esac
done
