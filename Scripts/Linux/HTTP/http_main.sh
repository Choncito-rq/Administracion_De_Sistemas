#!/bin/bash

SOURCE_DIR="$(dirname "$(readlink -f "$0")")"
source "$SOURCE_DIR/http_functions.sh"

IP=$(ip addr show enp0s9 2>/dev/null | awk '/inet /{print $2}' | cut -d'/' -f1)
HOSTNAME=$(hostname)

clear
echo ""
echo "  Actividad 6 - HTTP"
echo "  ------------------"
echo "  Host : $HOSTNAME"
echo "  IP   : ${IP:-No disponible (enp0s9)}"
echo ""
echo "  ================================"
echo "   Instalador de servidor HTTP"
echo "  ================================"
echo ""
echo "  1) Apache2"
echo "  2) Nginx"
echo "  3) Tomcat"
echo "  4) Cambiar puerto de un servidor ya instalado"
echo "  0) Salir"
echo ""

while true; do
    read -rp "  Selecciona una opcion: " opc
    [[ "$opc" =~ ^[0-4]$ ]] && break
    echo "  Opcion invalida."
done

case "$opc" in

0)
    echo "  Saliendo."
    echo ""
    exit 0
    ;;

1)
    echo ""
    mapfile -t versiones < <(get_versiones "apache2")
    select_version "Apache2" "${versiones[@]}"
    read_puerto 80
    install_servicio "apache2" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    echo ""
    echo "  [OK] Apache2 disponible en http://$IP:$PUERTO_ELEGIDO"
    ;;

2)
    echo ""
    mapfile -t versiones < <(get_versiones "nginx")
    select_version "Nginx" "${versiones[@]}"
    read_puerto 80
    install_servicio "nginx" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    echo ""
    echo "  [OK] Nginx disponible en http://$IP:$PUERTO_ELEGIDO"
    ;;

3)
    echo ""
    mapfile -t pkgs < <(apt-cache search "^tomcat" | awk '{print $1}' | grep "^tomcat[0-9]" | sort -rV)

    if [ ${#pkgs[@]} -eq 0 ]; then
        echo "  [ERROR] No se encontraron paquetes de Tomcat."
        exit 1
    fi

    echo "  Paquetes de Tomcat disponibles:"
    echo ""
    for ((i = 0; i < ${#pkgs[@]}; i++)); do
        echo "  $((i + 1))) ${pkgs[$i]}"
    done

    while true; do
        echo ""
        read -rp "  ¿Cual paquete deseas instalar? [1-${#pkgs[@]}]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && [ "$eleccion" -ge 1 ] && [ "$eleccion" -le ${#pkgs[@]} ]; then
            PKG_TOMCAT="${pkgs[$((eleccion - 1))]}"
            break
        fi
        echo "  Opcion invalida."
    done

    mapfile -t versiones < <(get_versiones "$PKG_TOMCAT")
    select_version "Tomcat ($PKG_TOMCAT)" "${versiones[@]}"
    read_puerto 8080
    install_servicio "$PKG_TOMCAT" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    echo ""
    echo "  [OK] Tomcat disponible en http://$IP:$PUERTO_ELEGIDO"
    ;;

4)
    echo ""
    echo "  ¿De que servicio deseas cambiar el puerto?"
    echo ""
    echo "  1) Apache2"
    echo "  2) Nginx"
    echo "  3) Tomcat"
    echo ""

    while true; do
        read -rp "  Selecciona el servicio: " servicio
        [[ "$servicio" =~ ^[1-3]$ ]] && break
        echo "  Opcion invalida."
    done

    read -rp "  Nuevo puerto: " nuevo_puerto

    case "$servicio" in
    1) set_puerto_apache2 "$nuevo_puerto" ;;
    2) set_puerto_nginx   "$nuevo_puerto" ;;
    3) set_puerto_tomcat  "$nuevo_puerto" ;;
    esac
    ;;

esac

echo ""
