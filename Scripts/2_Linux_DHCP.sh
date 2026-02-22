#!/bin/bash

INTERFAZ_DEF="enp0s8"
RUTA_CONF="/etc/dhcp/dhcpd.conf"
RUTA_LEASES="/var/lib/dhcpd/dhcpd.leases"


Pausa-Sistema() { 
    echo ""
    read -p "               Presione ENTER para continuar"
}

Validar-Formato-IP() {
    local ip=$1
    # 1. Validar formato numérico
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # 2. Validar IPs prohibidas (Se añade 127.0.0.0 según lo solicitado)
    if [[ "$ip" == "0.0.0.0" || "$ip" == "127.0.0.1" || "$ip" == "127.0.0.0" || "$ip" == "255.255.255.255" ]]; then
        echo "Error: La IP $ip es reservada."
        return 1
    fi
    
    # 3. Validar rango de octetos
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    if [ "$i1" -gt 255 ] || [ "$i2" -gt 255 ] || [ "$i3" -gt 255 ] || [ "$i4" -gt 255 ]; then
        return 1
    fi
    return 0
}

Calcular-Siguiente-IP() {
    local ip=$1
    local base=$(echo $ip | cut -d. -f1-3)
    local ultimo=$(echo $ip | cut -d. -f4)
    echo "$base.$((ultimo + 1))"
}

Determinar-Mascara() {
    local octeto=$(echo $1 | cut -d. -f1)
    if [ "$octeto" -lt 128 ]; then echo "255.0.0.0"; 
    elif [ "$octeto" -lt 192 ]; then echo "255.255.0.0"; 
    else echo "255.255.255.0"; fi
}


Gestionar-Instalacion-Linux() {
    clear
    echo "       VERIFICACION E INSTALACION"
    echo "================================================"
    if rpm -q dhcp-server &> /dev/null; then
        echo "Estado: El paquete dhcp-server YA ESTA INSTALADO"
        read -p "Desea REINSTALAR (limpiar binarios)? (s/n): " resp
        if [[ "$resp" == "s" || "$resp" == "S" ]]; then
            echo "[*] Reinstalando de forma silenciosa..."
            dnf reinstall -y dhcp-server &> /dev/null && echo "[+] Reinstalacion completada."
        fi
    else
        echo "Estado: El servicio DHCP NO ESTA INSTALADO"
        echo "[*] Instalando dhcp-server..."
        dnf install -y dhcp-server &> /dev/null && echo "[+] Instalacion completada."
    fi
    Pausa-Sistema
}

Consultar-Estado-Linux() {
    clear
    echo "            ESTADO DEL SERVICIO"
    echo "================================================"
    if systemctl is-active dhcpd &> /dev/null; then
        echo "Estado: ACTIVO"
        echo "--- Detalles ---"
        systemctl status dhcpd --no-pager | grep "Active:"
    else
        echo "Estado: INACTIVO / DETENIDO"
    fi
    Pausa-Sistema
}

Menu-Gestion-Ambitos-Linux() {
    clear
    echo "                CONFIGURACION DHCP"
    echo "================================================"
    
    # Seleccion de Interfaz
    echo "Interfaces disponibles:"
    nmcli device status | grep -v "lo" | awk '{print " - " $1}'
    read -p "Interfaz a usar (Enter para $INTERFAZ_DEF): " INT_USR
    [ -z "$INT_USR" ] && INT_USR=$INTERFAZ_DEF
    
    # Captura de Datos
    read -p "Nombre del Ambito: " NOMBRE_S
    while true; do
        read -p "IP del Servidor (Inicio): " IP_BASE
        Validar-Formato-IP "$IP_BASE" && break
        echo "IP Invalida."
    done
    
    SERVER_IP=$IP_BASE
    RANGO_I=$(Calcular-Siguiente-IP "$IP_BASE")
    MASCARA=$(Determinar-Mascara "$SERVER_IP")
    
    # Logica de Subnet ID
    IFS='.' read -r i1 i2 i3 i4 <<< "$SERVER_IP"
    if [ "$MASCARA" == "255.0.0.0" ]; then
        ID_RED="$i1.0.0.0"; CIDR=8
    elif [ "$MASCARA" == "255.255.0.0" ]; then
        ID_RED="$i1.$i2.0.0"; CIDR=16
    else
        ID_RED="$i1.$i2.$i3.0"; CIDR=24
    fi

    echo "-> Red Detectada: $ID_RED / Mascara: $MASCARA (/$CIDR)"
    
    while true; do 
        read -p "IP Final del Rango: " RANGO_F
        Validar-Formato-IP "$RANGO_F" && break
        echo "IP Invalida."
    done

    while true; do 
        read -p "Tiempo Concesion (seg): " T_LEASE
        [[ "$T_LEASE" =~ ^[0-9]+$ ]] && break
    done
    
    read -p "Puerta de Enlace (Opcional): " GW_USR
    read -p "Servidor DNS (Opcional): " DNS_USR

    # Aplicar Red
    echo "[*] Configurando IP fija en $INT_USR..."
    NOMBRE_CON=$(nmcli -t -f NAME,DEVICE con show --active | grep "$INT_USR" | cut -d: -f1)
    [ -z "$NOMBRE_CON" ] && NOMBRE_CON=$INT_USR
    
    nmcli con mod "$NOMBRE_CON" ipv4.addresses "$SERVER_IP/$CIDR" ipv4.method manual &> /dev/null
    [ ! -z "$GW_USR" ] && nmcli con mod "$NOMBRE_CON" ipv4.gateway "$GW_USR" &> /dev/null
    nmcli con down "$NOMBRE_CON" &> /dev/null && nmcli con up "$NOMBRE_CON" &> /dev/null
    sleep 2

    # Generar Archivo Conf
    echo "[*] Escribiendo $RUTA_CONF..."
    cat > $RUTA_CONF <<EOF
default-lease-time $T_LEASE;
max-lease-time $T_LEASE;
authoritative;

subnet $ID_RED netmask $MASCARA {
  range $RANGO_I $RANGO_F;
EOF
    [ ! -z "$GW_USR" ] && echo "  option routers $GW_USR;" >> $RUTA_CONF
    [ ! -z "$DNS_USR" ] && echo "  option domain-name-servers $DNS_USR;" >> $RUTA_CONF
    echo "}" >> $RUTA_CONF

    # Reiniciar y Firewall
    systemctl enable dhcpd &> /dev/null
    systemctl restart dhcpd
    if [ $? -eq 0 ]; then
        echo "[+] Servicio DHCP iniciado EXITOSAMENTE."
        firewall-cmd --add-service=dhcp --permanent &> /dev/null
        firewall-cmd --reload &> /dev/null
    else
        echo "[!] ERROR: El servicio fallo"
    fi
    Pausa-Sistema
}

Monitorear-IPs-Linux() {
    clear
    echo "                CONEXIONES ACTIVAS"
    echo "================================================"
    if systemctl is-active dhcpd &> /dev/null; then
        echo "Estado: SERVICIO FUNCIONANDO"
        echo "--- Concesiones (Leases) ---"
        [ -f "$RUTA_LEASES" ] && grep "lease" "$RUTA_LEASES" || echo "Sin asignaciones activas."
    else
        echo "El servicio esta detenido."
    fi
    Pausa-Sistema
}

while true; do
    clear
    echo "================================================"
    echo "          ADMINISTRACION DHCP ALMALINUX"
    echo "================================================"
    echo "1) Instalar / Verificar DHCP"
    echo "2) Status del Servicio"
    echo "3) Crear conexion (Scope)"
    echo "4) Monitorear Conexiones"
    echo "5) Salir"
    echo "================================================"
    read -p "Seleccione una opcion: " opcion

    case $opcion in
        1) Gestionar-Instalacion-Linux ;;
        2) Consultar-Estado-Linux ;;
        3) Menu-Gestion-Ambitos-Linux ;;
        4) Monitorear-IPs-Linux ;;
        5) clear; exit 0 ;;
        *) echo "Elige una opcion valida >:C "; sleep 1 ;;
    esac
done
