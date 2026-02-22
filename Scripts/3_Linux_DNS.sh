#!/bin/bash

# ==========================================================
#    SISTEMA DE ADMINISTRACION DHCP Y DNS (LINUX)
# ==========================================================

# --- CONFIGURACIÓN GLOBAL ---
INTERFAZ="enp0s8"
NETPLAN_FILE="/etc/netplan/99-practica-config.yaml"

# --- 1. VERIFICACIÓN DE PRIVILEGIOS ---
if [ "$EUID" -ne 0 ]; then
  echo "Error: Por favor, ejecute este script como root (sudo)."
  exit 1
fi

# --- 2. FUNCIONES DE UTILIDAD Y RED ---

ip_a_entero() {
    local IFS=.
    read -r i1 i2 i3 i4 <<< "$1"
    echo $(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
}

entero_a_ip() {
    local ip=$1
    echo "$(( (ip >> 24) & 255 )).$(( (ip >> 16) & 255 )).$(( (ip >> 8) & 255 )).$(( ip & 255 ))"
}

cidr_a_mascara() {
    local i mascara=""
    local prefijo=$1
    local octetos_completos=$(($prefijo / 8))
    local bits_sobrantes=$(($prefijo % 8))

    for ((i=0;i<4;i++)); do
        if [ $i -lt $octetos_completos ]; then
            mascara+="255"
        elif [ $i -eq $octetos_completos ]; then
            mascara+=$((256 - 2**(8-bits_sobrantes)))
        else
            mascara+="0"
        fi
        if [ $i -lt 3 ]; then mascara+="."; fi
    done
    echo "$mascara"
}

validar_ip() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    local IFS=.
    read -r -a octetos <<< "$ip"
    if (( ${octetos[0]} == 0 || ${octetos[0]} > 223 )); then return 1; fi 
    for octeto in "${octetos[@]}"; do
        if (( octeto < 0 || octeto > 255 )); then return 1; fi
    done
    case "$ip" in
        "0.0.0.0"|"255.255.255.255"|"127.0.0.1") return 1 ;;
    esac
    return 0
}

ip_pertenece_a_red() {
    local ip_cliente=$1
    local ip_red=$2
    local prefijo=$3
    local ip_num=$(ip_a_entero "$ip_cliente")
    local red_num=$(ip_a_entero "$ip_red")
    local mascara_num=$(( 0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF ))
    local red_calculada=$(( ip_num & mascara_num ))
    local red_base_calculada=$(( red_num & mascara_num ))
    [ "$red_calculada" -eq "$red_base_calculada" ] && return 0 || return 1
}

garantizar_ip_estatica() {
    echo "--- Verificando Configuración IP ---"
    CURRENT_IP=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "Estado: IP actual en memoria: ${CURRENT_IP:-"Ninguna"}"

    read -p "¿Desea configurar una IP ESTÁTICA PERMANENTE? (s/n): " opt
    if [[ "$opt" == "s" || "$opt" == "S" ]]; then
        while true; do
            read -p "Ingrese la nueva IP Estática: " NUEVA_IP
            validar_ip "$NUEVA_IP" && break || echo "IP inválida."
        done

        local i1=$(echo $NUEVA_IP | cut -d. -f1)
        local PREFIJO_CALC=24
        [ "$i1" -le 127 ] && PREFIJO_CALC=8
        [[ "$i1" -gt 127 && "$i1" -le 191 ]] && PREFIJO_CALC=16

        echo "Configurando $NUEVA_IP/$PREFIJO_CALC en Netplan..."
        cat <<EOF > $NETPLAN_FILE
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFAZ:
      dhcp4: no
      addresses:
        - $NUEVA_IP/$PREFIJO_CALC
EOF
        chmod 600 $NETPLAN_FILE
        netplan apply
        sleep 3
        echo "Configuración aplicada."
    fi
}

# --- 3. MÓDULO DHCP (isc-dhcp-server) ---

instalar_dhcp() {
    echo "=== Instalación DHCP ==="
    if ! dpkg -l | grep -q isc-dhcp-server; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
        echo "Instalación completada."
    else
        echo "El servicio DHCP ya está instalado."
    fi
    read -p "Presione Enter..."
}

configurar_dhcp() {
    echo "=== Configuración DHCP ==="
    garantizar_ip_estatica

    SERVER_IP_FULL=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')
    [ -z "$SERVER_IP_FULL" ] && { echo "Error: No hay IP configurada."; return; }
    
    IP_SERVIDOR=${SERVER_IP_FULL%/*}
    PREFIJO=${SERVER_IP_FULL#*/}
    
    local ip_num=$(ip_a_entero "$IP_SERVIDOR")
    local mascara_num=$(( 0xFFFFFFFF << (32 - PREFIJO) & 0xFFFFFFFF ))
    IP_RED=$(entero_a_ip $(( ip_num & mascara_num )))
    MASCARA_RED=$(cidr_a_mascara $PREFIJO)

    echo "Red detectada: $IP_RED / $MASCARA_RED"
    read -p "Nombre del ámbito: " NOMBRE_AMBITO

    while true; do
        read -p "IP Inicial Pool: " IP_POOL_INICIO
        read -p "IP Final Pool:   " IP_FIN
        if validar_ip "$IP_POOL_INICIO" && validar_ip "$IP_FIN"; then
            if ip_pertenece_a_red "$IP_POOL_INICIO" "$IP_RED" "$PREFIJO" && ip_pertenece_a_red "$IP_FIN" "$IP_RED" "$PREFIJO"; then
                break
            fi
        fi
        echo "Error: IPs inválidas o fuera de la red actual."
    done

    read -p "Gateway (Opcional): " IP_GATEWAY
    read -p "DNS (Opcional): " IP_DNS
    read -p "Tiempo concesión (seg, def 600): " TIEMPO
    [ -z "$TIEMPO" ] && TIEMPO=600

    cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak
    sed -i "s/INTERFACESv4=.*/INTERFACESv4=\"$INTERFAZ\"/" /etc/default/isc-dhcp-server 2>/dev/null || echo "INTERFACESv4=\"$INTERFAZ\"" >> /etc/default/isc-dhcp-server

    cat <<EOF > /etc/dhcp/dhcpd.conf
# Config Generada - $NOMBRE_AMBITO
default-lease-time $TIEMPO;
max-lease-time 7200;
authoritative;

subnet $IP_RED netmask $MASCARA_RED {
    range $IP_POOL_INICIO $IP_FIN;
EOF
    [ -n "$IP_GATEWAY" ] && echo "    option routers $IP_GATEWAY;" >> /etc/dhcp/dhcpd.conf
    [ -n "$IP_DNS" ] && echo "    option domain-name-servers $IP_DNS;" >> /etc/dhcp/dhcpd.conf
    echo "}" >> /etc/dhcp/dhcpd.conf

    systemctl restart isc-dhcp-server
    echo "DHCP Reiniciado."
    read -p "Presione Enter..."
}

monitorear_dhcp() {
    clear
    echo "--- Estado DHCP ---"
    systemctl status isc-dhcp-server --no-pager | grep -E "Active:|Status:"
    echo -e "\n--- Últimos Leases ---"
    [ -f /var/lib/dhcp/dhcpd.leases ] && tail -n 10 /var/lib/dhcp/dhcpd.leases || echo "Sin leases registrados."
    read -p "Presione Enter..."
}

# --- 4. MÓDULO DNS (BIND9) ---

instalar_dns() {
    echo "=== Instalación DNS (BIND9) ==="
    if [ ! -d "/etc/bind" ] || ! dpkg -l | grep -q bind9; then
        apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall bind9 bind9utils
        echo "BIND9 instalado/reparado."
    else
        echo "BIND9 ya está instalado."
    fi
    read -p "Presione Enter..."
}

agregar_dominio() {
    echo "=== ALTA DE DOMINIO ==="
    read -p "Dominio (ej. sitio.com): " DOMINIO
    read -p "IP Destino: " IP_DESTINO
    [ -z "$DOMINIO" ] || [ -z "$IP_DESTINO" ] && { echo "Datos incompletos."; return; }
    
    if grep -q "zone \"$DOMINIO\"" /etc/bind/named.conf.local; then
        echo "El dominio ya existe."; return
    fi

    cat <<EOF >> /etc/bind/named.conf.local
zone "$DOMINIO" {
    type master;
    file "/etc/bind/db.$DOMINIO";
};
EOF

    cat <<EOF > /etc/bind/db.$DOMINIO
\$TTL 604800
@ IN SOA ns.$DOMINIO. root.$DOMINIO. ( 2 604800 86400 2419200 604800 )
@ IN NS ns.$DOMINIO.
@ IN A $IP_DESTINO
ns IN A $IP_DESTINO
www IN A $IP_DESTINO
EOF
    systemctl restart bind9
    echo "Dominio $DOMINIO agregado."
    read -p "Presione Enter..."
}

eliminar_dominio() {
    read -p "Dominio a eliminar: " DOMINIO
    if grep -q "zone \"$DOMINIO\"" /etc/bind/named.conf.local; then
        sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/bind/named.conf.local
        rm -f "/etc/bind/db.$DOMINIO"
        systemctl restart bind9
        echo "Dominio eliminado."
    else
        echo "No se encontró el dominio."
    fi
    read -p "Presione Enter..."
}

listar_dominios() {
    clear
    echo "=== LISTADO DE DOMINIOS DNS ==="
    printf "%-25s | %-15s\n" "DOMINIO" "IP DESTINO"
    echo "--------------------------+---------------"
    [ ! -f "/etc/bind/named.conf.local" ] && { echo "Sin registros."; return; }
    
    DOMINIOS=$(grep "zone \"" /etc/bind/named.conf.local | cut -d'"' -f2)
    for dom in $DOMINIOS; do
        IP=$(grep -P "^\s*@\s+IN\s+A" "/etc/bind/db.$dom" | awk '{print $4}')
        printf "%-25s | %-15s\n" "$dom" "${IP:-"N/A"}"
    done
    read -p "Presione Enter..."
}

# --- 5. MENÚS ---

submenu_dhcp() {
    while true; do
        clear
        echo "=== MENU DHCP ==="
        echo "1. Instalar Servicio"
        echo "2. Configurar Scope"
        echo "3. Monitorear Estado"
        echo "4. Volver"
        read -p "Opción: " op
        case $op in
            1) instalar_dhcp ;;
            2) configurar_dhcp ;;
            3) monitorear_dhcp ;;
            4) return ;;
        esac
    done
}

submenu_dns() {
    while true; do
        clear
        echo "=== MENU DNS (BIND9) ==="
        echo "1. Instalar BIND9"
        echo "2. Alta Dominio"
        echo "3. Baja Dominio"
        echo "4. Listar Dominios"
        echo "5. Volver"
        read -p "Opción: " op
        case $op in
            1) instalar_dns ;;
            2) agregar_dominio ;;
            3) eliminar_dominio ;;
            4) listar_dominios ;;
            5) return ;;
        esac
    done
}

while true; do
    clear
    echo "================================="
    echo "   ADMINISTRACIÓN DE SERVICIOS   "
    echo "================================="
    echo "1. Administración DHCP"
    echo "2. Administración DNS"
    echo "3. Salir"
    read -p "Seleccione una opción: " opcion_main
    case $opcion_main in
        1) submenu_dhcp ;;
        2) submenu_dns ;;
        3) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida"; sleep 1 ;;
    esac
done
