INTERFAZ="enp0s8"
#Monitoring

# -------------------------------------------------------------------------------------------------- Monitoreo del S.O

Monitoring_vm() {
   echo "===== DIAGNOSTICO DEL SISTEMA ====="
   echo "Nombre del equipo:"
   hostname

   echo ""
   echo "Direcciones IP:"
   ip a | grep inet | grep -v 127.0.0.1

   echo ""
   echo "Espacio en disco:"
   df -h /
    read -p "Presione Enter..."
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------- Validaciones

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
    # Regex básico de formato
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    
    local IFS=.
    read -r -a octetos <<< "$ip"
    
    # Validaciones de rango numérico
    if (( ${octetos[0]} == 0 )); then return 1; fi
    if (( ${octetos[0]} > 223 )); then return 1; fi 
    
    for octeto in "${octetos[@]}"; do
        if (( octeto < 0 || octeto > 255 )); then return 1; fi
    done

    # Lista negra de IPs
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

    if [ "$red_calculada" -eq "$red_base_calculada" ]; then return 0; else return 1; fi
}

garantizar_ip_estatica() {
    echo "--- Verificando Configuración IP ---"
    
    # Verificamos si ya existe nuestro archivo de configuración persistente
    NETPLAN_FILE="/etc/netplan/99-practica-config.yaml"
    
    # Detectar IP actual
    CURRENT_IP=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    if [ -z "$CURRENT_IP" ]; then
        echo "Estado: La interfaz $INTERFAZ no tiene IP asignada actualmente."
    else
        echo "Estado: IP actual en memoria: $CURRENT_IP"
    fi

    read -p "¿Desea configurar una IP ESTÁTICA PERMANENTE? (s/n): " opt
    if [[ "$opt" == "s" || "$opt" == "S" ]]; then
        
        # 1. Pedir la IP
        while true; do
            read -p "Ingrese la nueva IP Estática (Solo IP, ej. 192.168.50.4): " NUEVA_IP
            if ! validar_ip "$NUEVA_IP"; then echo "IP inválida."; continue; fi
            break
        done

        # 2. Calcular prefijo automático
        local i1=$(echo $NUEVA_IP | cut -d. -f1)
        local PREFIJO_CALC=24
        if [ "$i1" -le 127 ]; then PREFIJO_CALC=8; 
        elif [ "$i1" -le 191 ]; then PREFIJO_CALC=16; fi

        echo "Configurando $NUEVA_IP/$PREFIJO_CALC de forma PERMANENTE..."

        # 3. CREAR ARCHIVO NETPLAN (Esto es lo que la hace permanente)
        # Nota: Netplan es muy estricto con los espacios (indentación).
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

        # 4. Aplicar cambios
        echo "Aplicando configuración de Netplan..."
        chmod 600 $NETPLAN_FILE
        netplan apply
        
        # Pequeña pausa para que la tarjeta reaccione
        sleep 3
        
        echo "La IP ha quedado grabada en disco."

    fi
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#DHCP Funtions

# -------------------------------------------------------------------------------------------------- Instalación/Verificacion

instalar_dhcp() {
    echo "=== Instalación DHCP ==="
    if ! dpkg -l | grep -q isc-dhcp-server; then
        echo "Instalando isc-dhcp-server..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y isc-dhcp-server
        echo "Instalación completada."
    else
        echo "El servicio DHCP ya está instalado."
    fi
    read -p "Presione Enter..."
}

# -------------------------------------------------------------------------------------------------- Crear ambito

configurar_dhcp() {
    echo "=== Configuración DHCP ==="
    garantizar_ip_estatica

    SERVER_IP_FULL=$(ip -4 addr show $INTERFAZ | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+')
    if [ -z "$SERVER_IP_FULL" ]; then echo "Error: No hay IP configurada."; return; fi
    
    IP_SERVIDOR=${SERVER_IP_FULL%/*}
    PREFIJO=${SERVER_IP_FULL#*/}
    
    # Calcular ID de Red
    local ip_num=$(ip_a_entero "$IP_SERVIDOR")
    local mascara_num=$(( 0xFFFFFFFF << (32 - PREFIJO) & 0xFFFFFFFF ))
    local red_num=$(( ip_num & mascara_num ))
    IP_RED=$(entero_a_ip "$red_num")
    MASCARA_RED=$(cidr_a_mascara $PREFIJO)

    echo "Configurando DHCP sobre red: $IP_RED / $MASCARA_RED"
    read -p "Ingrese nombre del ámbito: " NOMBRE_AMBITO

    while true; do
        read -p "IP Inicial del Pool: " IP_POOL_INICIO
        read -p "IP Final del Pool:   " IP_FIN
        
        if ! validar_ip "$IP_POOL_INICIO" || ! validar_ip "$IP_FIN"; then
             echo "Error: IP inválida."
             continue
        fi

if ! ip_pertenece_a_red "$IP_POOL_INICIO" "$IP_RED" "$PREFIJO"; then
            echo "Error: IP inicial fuera de rango."
            continue
        fi

        if ! ip_pertenece_a_red "$IP_FIN" "$IP_RED" "$PREFIJO"; then
            echo "Error: IP final fuera de rango."
            continue
        fi
        break
    done

    read -p "Gateway (Enter para omitir): " IP_GATEWAY
    read -p "DNS (Enter para omitir): " IP_DNS
    read -p "Tiempo de concesión (segundos, default 600): " TIEMPO
    if [ -z "$TIEMPO" ]; then TIEMPO=600; fi

    sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.bak

    if grep -q "INTERFACESv4" /etc/default/isc-dhcp-server; then
        sudo sed -i "s/INTERFACESv4=.*/INTERFACESv4=\"$INTERFAZ\"/" /etc/default/isc-dhcp-server
    else
        echo "INTERFACESv4=\"$INTERFAZ\"" | sudo tee -a /etc/default/isc-dhcp-server > /dev/null
    fi

    cat <<EOF > /etc/dhcp/dhcpd.conf
# Config Generada - $NOMBRE_AMBITO
default-lease-time $TIEMPO;
max-lease-time 7200;
authoritative;

subnet $IP_RED netmask $MASCARA_RED {
    range $IP_POOL_INICIO $IP_FIN;
EOF
    if [ -n "$IP_GATEWAY" ]; then echo "    option routers $IP_GATEWAY;" >> /etc/dhcp/dhcpd.conf; fi
    if [ -n "$IP_DNS" ]; then echo "    option domain-name-servers $IP_DNS;" >> /etc/dhcp/dhcpd.conf; fi
    echo "}" >> /etc/dhcp/dhcpd.conf

    echo "Reiniciando DHCP..."
    systemctl restart isc-dhcp-server
    read -p "Presione Enter..."
}

# -------------------------------------------------------------------------------------------------- Monitoreo

monitorear_dhcp() {
    clear
    echo "--- Estado DHCP ---"
    systemctl status isc-dhcp-server --no-pager | grep -E "Active:|Status:"
    echo -e "\n--- Concesiones ---"
    [ -f /var/lib/dhcp/dhcpd.leases ] && tail -n 10 /var/lib/dhcp/dhcpd.leases || echo "Sin leases."
    read -p "Presione Enter..."
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#DNS Funtions

# -------------------------------------------------------------------------------------------------- Instalación/Verificacion

instalar_dns() {
    echo "=== Instalación DNS ==="
    # CORRECCION: Verificamos si EXISTE LA CARPETA, no solo el paquete.
    # Si la carpeta /etc/bind no existe, forzamos reinstalación con --reinstall
    
    if [ ! -d "/etc/bind" ] || ! dpkg -l | grep -q bind9; then
        echo "Archivos de configuración no encontrados o paquete faltante."
        echo "Instalando/Reparando BIND9..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y --reinstall bind9 bind9utils bind9-doc
        echo "Instalación y reparación completada."
    else
        echo "El servicio BIND9 y sus archivos ya están correctos."
    fi
    read -p "Presione Enter..."
}

# -------------------------------------------------------------------------------------------------- Alta/Baja/Consultado/Busqueda

agregar_dominio() {
    echo "=== ALTA DE DOMINIO ==="
    read -p "Dominio (ej. sitio.com): " DOMINIO
    read -p "IP Destino: " IP_DESTINO

    if [ -z "$DOMINIO" ] || [ -z "$IP_DESTINO" ]; then echo "Faltan datos."; read -p "Enter..."; return; fi
    
    if grep -q "zone \"$DOMINIO\"" /etc/bind/named.conf.local; then
        echo "El dominio ya existe."
        read -p "Enter..."
        return
    fi

    cat <<EOF >> /etc/bind/named.conf.local

zone "$DOMINIO" {
    type master;
    file "/etc/bind/db.$DOMINIO";
};
EOF

    cat <<EOF > /etc/bind/db.$DOMINIO
; BIND data file for $DOMINIO
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMINIO.
@       IN      A       $IP_DESTINO
ns      IN      A       $IP_DESTINO
www     IN      A       $IP_DESTINO
EOF

    systemctl restart bind9
    echo "Dominio agregado."
    read -p "Presione Enter..."
}

eliminar_dominio() {
    echo "=== BAJA DE DOMINIO ==="
    read -p "Dominio a eliminar: " DOMINIO
    if ! grep -q "zone \"$DOMINIO\"" /etc/bind/named.conf.local; then
        echo "No existe."
        read -p "Enter..."
        return
    fi

    sed -i "/zone \"$DOMINIO\"/,/};/d" /etc/bind/named.conf.local
    if [ -f "/etc/bind/db.$DOMINIO" ]; then rm "/etc/bind/db.$DOMINIO"; fi
    
    systemctl restart bind9
    echo "Eliminado."
    read -p "Presione Enter..."
}

listar_dominios() {
    clear
    echo "=========================================="
    echo "       LISTADO DE DOMINIOS Y IPs"
    echo "=========================================="
    
    # Encabezados de la tabla
    printf "%-25s | %-15s\n" "DOMINIO" "IP DESTINO"
    echo "--------------------------+---------------"

    # Verificar si existe el archivo de configuración
    if [ ! -f "/etc/bind/named.conf.local" ]; then
        echo "No se encontró configuración de BIND."
        read -p "Enter..."; return
    fi

    # Obtener lista limpia de dominios
    DOMINIOS=$(grep "zone \"" /etc/bind/named.conf.local | cut -d'"' -f2)

    if [ -z "$DOMINIOS" ]; then
        echo "      (No hay dominios registrados)"
    else
        # Bucle: Por cada dominio, buscamos su archivo y su IP
        for dom in $DOMINIOS; do
            ARCHIVO_ZONA="/etc/bind/db.$dom"
            IP="No encontrada"

            if [ -f "$ARCHIVO_ZONA" ]; then
                # Buscamos la línea que dice "@ IN A 192..." y sacamos la 4ta palabra (la IP)
                IP_DETECTADA=$(grep -P "^\s*@\s+IN\s+A" "$ARCHIVO_ZONA" | awk '{print $4}')
                
                if [ -n "$IP_DETECTADA" ]; then
                    IP=$IP_DETECTADA
                fi
            fi
            
            # Imprimir en formato de columnas
            printf "%-25s | %-15s\n" "$dom" "$IP"
        done
    fi
    echo "--------------------------+---------------"
    read -p "Presione Enter para volver..."
}

consultar_dominio() {
    echo "=== CONSULTA ==="
    read -p "Dominio: " DOMINIO
    echo "Resultados locales:"
    nslookup $DOMINIO 127.0.0.1
    read -p "Presione Enter..."
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#SSH Funtions

# -------------------------------------------------------------------------------------------------- Instalación/Verificacion

function instalar_ssh() {
    local reinstalar=$1 # Recibe un argumento si es reinstalación

    if [ "$reinstalar" == "true" ]; then
        echo -e "\n[*] Eliminando OpenSSH Server y configuraciones previas..."
        sudo apt-get purge -y openssh-server > /dev/null
        sudo apt-get autoremove -y > /dev/null
    fi

    echo "[*] Actualizando índices de paquetes..."
    sudo apt-get update -qq

    echo "[*] Instalando OpenSSH Server..."
    sudo apt-get install -y openssh-server

    echo "[*] Asegurando que el servicio inicie en el boot..."
    sudo systemctl enable ssh
    sudo systemctl start ssh

    # Configuración de Firewall (ufw es el estándar en Ubuntu)
    echo "[*] Configurando Firewall (Puerto 22)..."
    sudo ufw allow 22/tcp > /dev/null
    
    echo -e "\033[0;32m[+] Servicio SSH instalado y activo.\033[0m"
}

# -------------------------------------------------------------------------------------------------- Configurar SSH

function configurar_red_linux() {
    local interfaz="enp0s9"
    echo -e "\n=== CONFIGURACIÓN DE RED (NETPLAN) ==="

    while true; do
          read -p "Ingrese la nueva IP Estática (Eje. 192.168.50.4): " nueva_ip
          if ! validar_ip "$nueva_ip"; then echo "IP inválida."; continue; fi
          break
    done

     local i1=$(echo $nueva_ip | cut -d. -f1)
     local prefijo=24
     if [ "$i1" -le 127 ]; then prefijo=8; 
     elif [ "$i1" -le 191 ]; then prefijo=16; fi


    echo "[*] Generando nueva configuración de Netplan..."
    
    # Esta parte "limpia" configuraciones anteriores al sobreescribir el archivo
    sudo cat <<EOF > /etc/netplan/99-ssh-config.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $interfaz:
      dhcp4: no
      addresses:
        - $nueva_ip/$prefijo
EOF

    echo "[*] Aplicando cambios de red..."
    sudo chmod 600 /etc/netplan/99-ssh-config.yaml
    sudo netplan apply
    
    echo -e "\033[0;32m[+] Interfaz $interfaz configurada con $nueva_ip/$prefijo\033[0m"
}

# -------------------------------------------------------------------------------------------------- Monitoreo SSH

function verificar_estado_linux() {
    clear
    echo "=== VERIFICACIÓN DE CONEXIÓN SSH ==="
    
    # Verificar servicio
    if systemctl is-active --quiet ssh; then
        echo -e "Estado del Servicio: \033[0;32mACTIVO\033[0m"
    else
        echo -e "Estado del Servicio: \033[0;31mDETENIDO\033[0m"
    fi

    # Verificar IP
    ip_actual=$(ip -4 addr show enp0s9 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo -e "IP en enp0s8:        \033[0;33m${ip_actual:-"No configurada"}\033[0m"
    
    # Verificar puerto
    puerto=$(ss -tlpn | grep :22)
    if [ -z "$puerto" ]; then
        echo -e "Puerto 22:           \033[0;31mCERRADO\033[0m"
    else
        echo -e "Puerto 22:           \033[0;32mESCUCHANDO\033[0m"
    fi
}

# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

#FTP Funtions

# -------------------------------------------------------------------------------------------------- Instalacion/Configuracion

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

FTP_ROOT="/srv/ftp"
LOG_FILE="/var/log/ftp_usuarios.log"
CONF_FILE="/etc/vsftpd.conf"
BACKUP_CONF="/etc/vsftpd.conf.bak"


checkInstalled() {
    local program="$1"
    if command -v "$program" &>/dev/null; then
        echo "$program esta instalado"
        return 0
    else
        echo "$program no esta instalado"
        return 1
    fi
}

installService() {
    local service="$1"
    echo "Instalando $service..."
    
    if sudo apt-get update && sudo apt-get install -y "$service"; then
        echo "$service instalado exitosamente"
        return 0
    else
        echo "Error al instalar $service"
        return 1
    fi
}

# Funcion generica de logging
writeLog() {
    local action="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $action: $message" >> "$LOG_FILE"
}


setupGroups() {
    ###CREACION DE GRUPOS
    if ! getent group "Reprobados" >/dev/null; then
        sudo groupadd Reprobados
        writeLog "GRUPO_CREADO" "Grupo Reprobados creado"
    fi
    if ! getent group "Recursadores" >/dev/null; then
        sudo groupadd Recursadores
        writeLog "GRUPO_CREADO" "Grupo Recursadores creado"
    fi

    # Crear directorios de grupo
    if [[ ! -d /srv/ftp/Reprobados ]]; then
        sudo mkdir -p /srv/ftp/Reprobados
        sudo chown root:Reprobados /srv/ftp/Reprobados
        sudo chmod 2770 /srv/ftp/Reprobados
        # ACL por defecto: subdirectorios heredan rwx solo para el grupo
        sudo setfacl -d -m g::rwx /srv/ftp/Reprobados
        sudo setfacl -d -m o::--- /srv/ftp/Reprobados
        writeLog "DIR_CREADO" "Directorio Reprobados creado"
    fi
    if [[ ! -d /srv/ftp/Recursadores ]]; then
        sudo mkdir -p /srv/ftp/Recursadores
        sudo chown root:Recursadores /srv/ftp/Recursadores
        sudo chmod 2770 /srv/ftp/Recursadores
        # ACL por defecto: subdirectorios heredan rwx solo para el grupo
        sudo setfacl -d -m g::rwx /srv/ftp/Recursadores
        sudo setfacl -d -m o::--- /srv/ftp/Recursadores
        writeLog "DIR_CREADO" "Directorio Recursadores creado"
    fi
}


setupFtpConf() {
    echo "Configurando vsftpd.conf..."

    # Hacer respaldo si no existe
    if [[ ! -f "$BACKUP_CONF" ]]; then
        sudo cp "$CONF_FILE" "$BACKUP_CONF" 2>/dev/null || true
    fi

    # Crear configuracion
    sudo tee /etc/vsftpd.conf >/dev/null <<EOL
listen=NO
listen_ipv6=YES
anonymous_enable=YES
anon_root=/srv/ftp/Anonymous
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
no_anon_password=YES
local_enable=YES
write_enable=YES
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
chroot_list_enable=YES
chroot_list_file=/etc/vsftpd.chroot_list
allow_writeable_chroot=YES
local_umask=022
anon_umask=022
user_sub_token=\$USER
local_root=/srv/ftp/\$USER
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
EOL

    # Crear chroot_list si no existe
    sudo touch /etc/vsftpd.chroot_list

    # Agregar usuarios a chroot_list si no estan
    if ! sudo grep -q "luvbeen" /etc/vsftpd.chroot_list 2>/dev/null; then
        sudo tee -a /etc/vsftpd.chroot_list >/dev/null <<EOL
luvbeen
root
EOL
    fi

    # Reiniciar servicio
    sudo service vsftpd restart
    writeLog "CONF_FTP" "vsftpd.conf configurado y servicio reiniciado"

    echo "Configuracion completada"
}

# Instalar vsftpd
installFTP() {
    echo ""
    echo "================================================="
    echo "    INSTALACION DE VSFTPD Y CONFIGURACION"
    echo "================================================="
    echo ""

    if checkInstalled vsftpd; then
        echo "vsftpd ya esta instalado"
        echo ""
        read -p "Deseas reconfigurar? [s/n]: " reconf
        if [[ "$reconf" != "s" ]]; then
            return 0
        fi
    else
        read -p "Quieres proceder con la instalacion de vsftpd? [s/n]: " opcInst

        if [[ "$opcInst" == "s" ]]; then
            echo "Procediendo con la instalacion..."
            if installService vsftpd && installService acl; then
                echo "Instalacion exitosa"

                # Hacer respaldo
                if [[ -f "$CONF_FILE" ]]; then
                    sudo cp "$CONF_FILE" "$BACKUP_CONF"
                    echo "Respaldo de configuracion creado: $BACKUP_CONF"
                fi
            else
                echo "Hubo un fallo en la instalacion"
                return 1
            fi
        else
            echo "Instalacion cancelada"
            return 0
        fi
    fi

    # Configurar
    setupFtpConf

    # Crear estructura
    echo ""
    echo "Creando estructura de directorios..."
    if [[ ! -d $FTP_ROOT/General ]]; then
        sudo mkdir -p $FTP_ROOT/General
        sudo chmod 2777 $FTP_ROOT/General
        # ACL por defecto: subdirectorios creados por cualquier usuario heredan rwx para todos
        sudo setfacl -d -m o::rwx $FTP_ROOT/General
        sudo setfacl -d -m g::rwx $FTP_ROOT/General
        sudo setfacl -d -m u::rwx $FTP_ROOT/General
        echo "Directorio General creado"

        sudo mkdir -p $FTP_ROOT/Anonymous
        sudo mkdir -p $FTP_ROOT/Anonymous/General
        sudo chmod 755 $FTP_ROOT/Anonymous/General
        sudo mount --bind $FTP_ROOT/General $FTP_ROOT/Anonymous/General 2>/dev/null || true
        echo "Directorio Anonymous creado"
    fi

    setupGroups

    echo ""
    echo "Instalacion y configuracion completada"
    read -p "Presiona Enter para continuar..."
}

# -------------------------------------------------------------------------------------------------- Verificacion

showStatus() {
    echo ""
    echo "================================================="
    echo "       ESTADO DEL SERVICIO FTP (VSFTPD)"
    echo "================================================="
    echo ""

    checkInstalled vsftpd

    if systemctl is-active --quiet vsftpd; then
        echo "Servicio activo (running)"
    else
        echo "Servicio inactivo (stopped)"
    fi

    if systemctl is-enabled --quiet vsftpd; then
        echo "Servicio habilitado en boot"
    else
        echo "Servicio NO habilitado en boot"
    fi

    echo ""
    if ss -tuln 2>/dev/null | grep -q ":21 "; then
        echo "Puerto 21 escuchando"
    else
        echo "Puerto 21 NO escuchando"
    fi

    echo ""
    read -p "Presiona Enter para continuar..."
}

# -------------------------------------------------------------------------------------------------- Gestionar usuarios

registerUsers() {
    echo ""
    echo "================================================="
    echo "		REGISTRO DE USUARIOS"
    echo "================================================="
    echo ""

    # Verificar que vsftpd esta instalado
    if ! checkInstalled vsftpd >/dev/null 2>&1; then
        echo "vsftpd no esta instalado"
        echo "Por favor instala vsftpd primero"
        read -p "Presiona Enter para continuar..."
        return 1
    fi

    echo "Configurando vsftpd.conf..."
    setupFtpConf

    echo "Creando grupos..."
    if [[ ! -d /srv/ftp/General ]]; then
        sudo mkdir -p /srv/ftp/General
        sudo chmod 2777 /srv/ftp/General
        # ACL por defecto: subdirectorios creados por cualquier usuario heredan rwx para todos
        sudo setfacl -d -m o::rwx /srv/ftp/General
        sudo setfacl -d -m g::rwx /srv/ftp/General
        sudo setfacl -d -m u::rwx /srv/ftp/General
        sudo mkdir -p /srv/ftp/Anonymous
        sudo mkdir -p /srv/ftp/Anonymous/General
        sudo chmod 755 /srv/ftp/Anonymous/General
        sudo mount --bind /srv/ftp/General /srv/ftp/Anonymous/General 2>/dev/null || true
    fi

    setupGroups

    # Leer numero de usuarios
    read -p "Cuantos usuarios registraras?: " num_users

    # Validar que sea un numero
    if ! [[ "$num_users" =~ ^[0-9]+$ ]]; then
        echo "Error: debes ingresar un numero"
        read -p "Presiona Enter para continuar..."
        return 1
    fi

    # Crear usuarios
    for ((i = 1; i <= num_users; i++)); do
        echo ""
        echo "================================================="
        echo "Usuario $i de $num_users"
        echo "================================================="
        echo ""

        # Solicitar nombre de usuario
        while :; do
            read -p "Ingresa nombre del usuario: " user
            if [[ -z "$user" ]]; then
                echo "El nombre no puede estar vacio"
                continue
            fi
            if id "$user" &>/dev/null; then
                echo "El usuario '$user' ya existe"
            else
                break
            fi
        done

        # Solicitar grupo
        while :; do
            read -p "A que grupo pertenece? [1=Reprobados / 2=Recursadores]: " gpo
            if [[ "$gpo" == "1" ]]; then
                addUser "$user" Reprobados
                break
            elif [[ "$gpo" == "2" ]]; then
                addUser "$user" Recursadores
                break
            else
                echo "Opcion invalida. Intenta de nuevo"
            fi
        done
    done

    echo ""
    echo "Registro de usuarios completado"
    read -p "Presiona Enter para continuar..."
}

# Cambiar grupo de usuario
switchGroupMenu() {
    echo ""
    echo "================================================="
    echo "            CAMBIO DE GRUPO ------>"
    echo "================================================="
    echo ""

    read -p "Ingresa el nombre del usuario (una vez lo ponga se pasara al otro grupo): " usu

    if [[ -z "$usu" ]]; then
        echo "Error: nombre de usuario vacio"
        read -p "Presiona Enter para continuar..."
        return 1
    fi

    switchGroup "$usu"

    echo ""
    read -p "Presiona Enter para continuar..."
}

addUser() {
    local username="$1"
    local group="$2"

    echo "Creando usuario: $username en grupo: $group"

    # Crear usuario
    sudo useradd "$username" -d /srv/ftp || {
        echo "Error al crear usuario $username"
        return 1
    }

    # Agregar a grupo
    sudo usermod -a -G "$group" "$username"

    # Crear estructura de directorios
    sudo mkdir -p /srv/ftp/"$username"
    sudo chown "$username:$username" /srv/ftp/"$username"

    sudo mkdir -p /srv/ftp/"$username"/"$username"
    sudo chown "$username:$username" /srv/ftp/"$username"/"$username"

    sudo chmod 500 /srv/ftp/"$username"

    # Crear directorio General compartido
    sudo mkdir -p /srv/ftp/"$username"/General
    sudo chmod 2777 /srv/ftp/"$username"/General
    sudo mount --bind /srv/ftp/General /srv/ftp/"$username"/General 2>/dev/null || true
    sudo chmod 2777 -R /srv/ftp/General

    # Crear directorio de grupo (solo miembros del grupo pueden escribir)
    sudo mkdir -p /srv/ftp/"$username"/"$group"
    sudo chmod 2770 /srv/ftp/"$username"/"$group"
    sudo mount --bind /srv/ftp/"$group" /srv/ftp/"$username"/"$group" 2>/dev/null || true
    sudo chmod 2770 -R /srv/ftp/"$group"

    # Establecer contrasena
    echo "Estableciendo contrasena para $username..."
    sudo passwd "$username"

    writeLog "USUARIO_CREADO" "Usuario: $username | Grupo: $group"
    echo "Usuario $username creado exitosamente"
}

switchGroup() {
    local username="$1"

    # Verificar que el usuario exista
    if ! id "$username" &>/dev/null; then
        echo "El usuario no existe"
        return 1
    fi

    # Obtener grupo actual (el ultimo listado)
    local current_group
    current_group=$(id -nG "$username" | awk '{print $NF}')

    # Determinar nuevo grupo
    local new_group
    if [[ "$current_group" == "Reprobados" ]]; then
        new_group="Recursadores"
    elif [[ "$current_group" == "Recursadores" ]]; then
        new_group="Reprobados"
    else
        echo "El usuario no pertenece a un grupo valido"
        return 1
    fi

    echo "Cambiando usuario $username de $current_group a $new_group..."

    # Quitar bind mount anterior
    sudo umount /srv/ftp/"$username"/"$current_group" 2>/dev/null || true
    sudo rm -rf /srv/ftp/"$username"/"$current_group"

    # Cambiar grupo principal y secundarios
    sudo usermod -g "$new_group" "$username"
    sudo usermod -G "$new_group" "$username"

    # Crear nuevo bind mount
    sudo mkdir -p /srv/ftp/"$username"/"$new_group"
    sudo chmod 2770 /srv/ftp/"$username"/"$new_group"
    sudo mount --bind /srv/ftp/"$new_group" /srv/ftp/"$username"/"$new_group" 2>/dev/null || true
    sudo chmod 2770 -R /srv/ftp/"$new_group"

    writeLog "GRUPO_CAMBIADO" "Usuario: $username | Grupo anterior: $current_group | Grupo nuevo: $new_group"

    echo "Usuario $username cambiado a $new_group correctamente"
}



