#!/bin/bash

source ./Funtions_Linux.sh

while true; do
    clear
    echo "========================================"
    echo "    ADMINISTRACIÓN SSH - UBUNTU 24.04   "
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
done
