#!/bin/bash

INTERFAZ="enp0s8"
source./Funtions_Linux.sh

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
    echo "3) Salir"
    read -p "Seleccione una opcion: " opcion_main
    
    case $opcion_main in
        0) Monitoring-vm ;;
        1) submenu_dhcp ;;
        2) submenu_dns ;;
        3) echo "Saliendo..."; exit 0 ;;
        *) echo "Opcion invalida"; read -p "..." ;;
    esac
done
