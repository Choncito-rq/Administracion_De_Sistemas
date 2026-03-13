if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecuta este script como root o con sudo."
    exit 1
fi
set_puerto_tomcat() {
    local puerto=$1
    local conf

    conf=$(find /etc/tomcat* /opt/tomcat* -name "server.xml" 2>/dev/null | head -1)

    if [ -z "$conf" ]; then
        echo "[ERROR] No se encontro server.xml de Tomcat."
        return 1
    fi

    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP/port=\"$puerto\" protocol=\"HTTP/" "$conf"
    echo "[OK] Puerto de Tomcat cambiado a $puerto en $conf."

    local svc
    svc=$(systemctl list-units --type=service | grep -i tomcat | awk '{print $1}' | head -1)
    if [ -n "$svc" ]; then
        systemctl restart "$svc"
        echo "[OK] Tomcat reiniciado."
    else
        echo "[ADVERTENCIA] No se encontro el servicio tomcat. Reinicia manualmente."
    fi
}

get_versiones() {
    local paquete=$1
    apt-cache madison "$paquete" 2>/dev/null | awk '{print $3}' | head -8
}

select_version() {
    local etiqueta=$1
    shift
    local versiones=("$@")
    local total=${#versiones[@]}

    if [ $total -eq 0 ]; then
        echo "[ERROR] No se encontraron versiones de $etiqueta."
        return 1
    fi

    local lts_idx=$((total / 2))

    echo ""
    echo "  Versiones disponibles de $etiqueta:"
    for ((i = 0; i < total; i++)); do
        local label=""
        if [ $i -eq 0 ]; then
            label="  (Latest)"
        elif [ $i -eq $lts_idx ] && [ $total -ge 3 ]; then
            label="  (LTS / Estable)"
        elif [ $i -eq $((total - 1)) ]; then
            label="  (Oldest)"
        fi
        echo "  $((i + 1))) ${versiones[$i]}$label"
    done

    while true; do
        read -rp "
  ¿Cual version deseas instalar? [1-$total]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && [ "$eleccion" -ge 1 ] && [ "$eleccion" -le $total ]; then
            VERSION_ELEGIDA="${versiones[$((eleccion - 1))]}"
            return 0
        fi
        echo "  Opcion invalida."
    done
}

read_puerto() {
    local default=$1

    while true; do
        read -rp "  ¿En que puerto deseas configurar el servicio? [default: $default]: " puerto
        puerto="${puerto:-$default}"

        if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
            echo "  Solo se permiten numeros."
            continue
        fi

        if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
            echo "  Puerto fuera de rango (1-65535)."
            continue
        fi

        local reservados=(21 22 25 53 110 143 3306 5432 6379 27017 3389 445 139)
        local reservado=false
        for r in "${reservados[@]}"; do
            if [ "$puerto" -eq "$r" ]; then
                echo "  El puerto $puerto esta reservado para otro servicio."
                reservado=true
                break
            fi
        done
        [ "$reservado" = true ] && continue

        if [ "$puerto" -lt 1024 ]; then
            echo "  [ADVERTENCIA] El puerto $puerto es privilegiado (<1024)."
        fi

        PUERTO_ELEGIDO=$puerto
        return 0
    done
}

new_index_html() {
    local servicio=$1
    local version=$2
    local puerto=$3
    local webroot
    local fecha
    fecha=$(date "+%Y-%m-%d %H:%M:%S")

    case "$servicio" in
    apache2) webroot="/var/www/apache2" ;;
    nginx)   webroot="/var/www/nginx" ;;
    tomcat*) webroot="/var/lib/${servicio}/webapps/ROOT" ;;
    *)       webroot="/var/www/html" ;;
    esac

    mkdir -p "$webroot"

    cat >"$webroot/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
<title>SERVIDOR ACTIVO - $servicio</title>
</head>
<body bgcolor="white">

<hr>
<h1>SERVIDOR ACTIVO</h1>
<hr>

<p><b>Servicio:</b> $servicio</p>
<p><b>Version:</b> $version</p>
<p><b>Puerto:</b> $puerto</p>
<p><b>Fecha de instalacion:</b> $fecha</p>

<hr>

<table border="1" cellpadding="5" cellspacing="0">
  <tr>
    <th bgcolor="silver">Campo</th>
    <th bgcolor="silver">Valor</th>
  </tr>
  <tr>
    <td>Servicio</td>
    <td>$servicio</td>
  </tr>
  <tr>
    <td>Version</td>
    <td>$version</td>
  </tr>
  <tr>
    <td>Puerto</td>
    <td>$puerto</td>
  </tr>
  <tr>
    <td>Instalado el</td>
    <td>$fecha</td>
  </tr>
</table>

<hr>
<p><font size="1">Generado automaticamente por http_functions.sh</font></p>

</body>
</html>
EOF

    echo "[OK] index.html generado en: $webroot/index.html"
}

set_puerto_apache2() {
    local puerto=$1
    local conf="/etc/apache2/ports.conf"

    sed -i "s/Listen [0-9]*/Listen $puerto/" "$conf"
    sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$puerto>/" /etc/apache2/sites-enabled/*.conf 2>/dev/null
    echo "[OK] Puerto de Apache2 cambiado a $puerto."
    systemctl restart apache2
    echo "[OK] Apache2 reiniciado."
}

set_puerto_nginx() {
    local puerto=$1
    local conf="/etc/nginx/sites-enabled/default"

    sed -i "s/listen [0-9]* /listen $puerto /" "$conf"
    sed -i "s/listen \[::\]:[0-9]*/listen [::]:$puerto/" "$conf"
    echo "[OK] Puerto de Nginx cambiado a $puerto."
    systemctl restart nginx
    echo "[OK] Nginx reiniciado."
}

install_servicio() {
    local servicio=$1
    local version=$2
    local puerto=$3

    echo ""
    echo "======================================================"
    echo "  Instalando $servicio $version en puerto $puerto"
    echo "======================================================"

    apt-get update

    case "$servicio" in
    apache2)
        if ! apt-get install -y "apache2=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y apache2
        fi
        systemctl enable apache2
        systemctl start apache2
        sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/apache2|' /etc/apache2/sites-enabled/000-default.conf
        sed -i 's|<Directory /var/www/html|<Directory /var/www/apache2|' /etc/apache2/sites-enabled/000-default.conf
        systemctl restart apache2
        set_puerto_apache2 "$puerto"
        ;;
    nginx)
        if ! apt-get install -y "nginx=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y nginx
        fi
        systemctl enable nginx
        systemctl start nginx
        sed -i 's|root /var/www/html|root /var/www/nginx|' /etc/nginx/sites-enabled/default
        systemctl restart nginx
        set_puerto_nginx "$puerto"
        ;;
    tomcat*)
        if ! apt-get install -y "$servicio=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y "$servicio"
        fi
        local svc
        svc=$(systemctl list-units --type=service | grep -i tomcat | awk '{print $1}' | head -1)
        if [ -n "$svc" ]; then
            systemctl enable "$svc"
            systemctl start "$svc"
        fi
        set_puerto_tomcat "$puerto"
        ;;
    esac

    echo ""
    local version_real
    version_real=$(dpkg -l "$servicio" 2>/dev/null | awk '/^ii/{print $3}')

    echo "[OK] $servicio instalado correctamente. Version real: $version_real"
    new_index_html "$servicio" "$version_real" "$puerto"
}
