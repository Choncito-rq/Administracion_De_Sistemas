#!/bin/bash
# ==============================================================================
# http_functions.sh


# Estructura de bloques:
#   BLOQUE 1  - Utilidades generales (mensajes, verificaciones)
#   BLOQUE 2  - Validación de puertos
#   BLOQUE 3  - Consulta dinámica de versiones
#   BLOQUE 4  - Instalación de servidores
#   BLOQUE 5  - Cambio de puerto en archivos de configuración
#   BLOQUE 6  - Creación de usuario dedicado y permisos
#   BLOQUE 7  - Hardening de seguridad (headers, métodos, fingerprinting)
#   BLOQUE 8  - Configuración de firewall (UFW)
#   BLOQUE 9  - Creación de página index.html personalizada
#   BLOQUE 10 - Inicio y verificación de servicios
#   BLOQUE 11 - Flujos completos por servidor (orquestadores)


# ==============================================================================

PUERTOS_RESERVADOS=(21 22 25 53 80 110 143 443 3306 5432 8443)

# URL base del servidor oficial de descargas de Apache Tomcat
TOMCAT_BASE_URL="https://downloads.apache.org/tomcat"

# Directorio donde se instalará Tomcat manualmente
TOMCAT_INSTALL_DIR="/opt/tomcat"

# Directorios raíz de contenido web por servidor
WEB_ROOT_APACHE="/var/www/html"
WEB_ROOT_NGINX="/var/www/html"
WEB_ROOT_TOMCAT="/opt/tomcat/webapps/ROOT"


SERVIDOR_ELEGIDO=""   # Nombre del servidor seleccionado (Apache2 / Nginx / Tomcat)
VERSION_ELEGIDA=""    # Versión seleccionada por el usuario
PUERTO_ELEGIDO=""     # Puerto validado y elegido por el usuario

# ==============================================================================
# BLOQUE 1: UTILIDADES GENERALES
# ==============================================================================

imprimir_encabezado() {
    clear
    echo "============================================================"
    echo "                 SERVIDORES HTTP - LINUX                    "
    echo "============================================================"
    echo ""
}


imprimir_ok()    { echo "[OK]   $1"; }
imprimir_error() { echo "[ERR]  $1"; }
imprimir_info()  { echo "[INFO] $1"; }
imprimir_paso()  { echo "[--> ] $1"; }

verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        imprimir_error "Este script debe ejecutarse como root (sudo bash main.sh)."
        exit 1
    fi
    imprimir_ok "Privilegios root verificados."
}

verificar_dependencias() {
    imprimir_paso "Verificando dependencias del sistema..."

    local deps=("curl" "wget" "awk" "sed" "ss" "ufw")
    local faltantes=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            faltantes+=("$dep")
        fi
    done

    if [ ${#faltantes[@]} -gt 0 ]; then
        imprimir_info "Instalando dependencias faltantes: ${faltantes[*]}"
        apt-get update -qq
        apt-get install -y "${faltantes[@]}" &>/dev/null
    fi

    imprimir_ok "Dependencias verificadas."
}

# ==============================================================================
# BLOQUE 2: VALIDACIÓN DE PUERTOS
# ==============================================================================

validar_puerto() {
    local puerto="$1"

    # Capa 1: Solo dígitos, sin espacios ni caracteres especiales
    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        imprimir_error "El puerto '$puerto' contiene caracteres invalidos. Solo se permiten numeros."
        return 1
    fi

    # Capa 2: Rango válido para servicios de usuario
    if [ "$puerto" -lt 1024 ] || [ "$puerto" -gt 65535 ]; then
        imprimir_error "El puerto $puerto esta fuera del rango permitido (1024-65535)."
        return 1
    fi

    # Capa 3: Lista negra de puertos reservados del sistema
    for reservado in "${PUERTOS_RESERVADOS[@]}"; do
        if [ "$puerto" -eq "$reservado" ]; then
            imprimir_error "El puerto $puerto esta reservado para otro servicio del sistema."
            imprimir_info  "Puertos bloqueados: ${PUERTOS_RESERVADOS[*]}"
            return 1
        fi
    done

    # Capa 4: Verificar que ningún proceso esté usando ese puerto actualmente.
    # `ss -tlnp` lista todos los sockets TCP en escucha con el proceso asociado.
    if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
        local proceso
        proceso=$(ss -tlnp | grep ":${puerto} " | awk '{print $6}' | head -1)
        imprimir_error "El puerto $puerto ya esta en uso por: $proceso"
        return 1
    fi

    imprimir_ok "Puerto $puerto disponible y valido."
    return 0
}

solicitar_puerto() {
    local puerto_input

    while true; do
        echo ""
        echo "Puertos bloqueados : ${PUERTOS_RESERVADOS[*]}"
        echo "Rango valido       : 1024 - 65535"
        echo -n "Ingresa el puerto de escucha: "
        read -r puerto_input

        # Verificar que no esté vacío antes de pasar a validar_puerto
        if [ -z "$puerto_input" ]; then
            imprimir_error "El puerto no puede estar vacio."
            continue
        fi

        # Si validar_puerto retorna 0, el puerto es válido → salir del bucle
        if validar_puerto "$puerto_input"; then
            PUERTO_ELEGIDO="$puerto_input"
            break
        fi
        # Si retorna 1, el bucle continúa y vuelve a pedir el puerto
    done
}

# ==============================================================================
# BLOQUE 3: CONSULTA DINÁMICA DE VERSIONES
# ==============================================================================

obtener_versiones_apache() {
    imprimir_paso "Consultando versiones disponibles de Apache2 en el repositorio..."
    echo ""

    # Actualizar índice de paquetes silenciosamente para obtener info fresca
    apt-get update -qq 2>/dev/null

    # Extraer versiones únicas del repositorio usando apt-cache madison.
    # awk '{print $3}' → toma la tercera columna (número de versión)
    # sort -Vr         → ordena por versión de mayor a menor
    # uniq             → elimina duplicados
    mapfile -t VERSIONES_DISPONIBLES < <(
        apt-cache madison apache2 2>/dev/null \
        | awk '{print $3}'                    \
        | sort -Vr                            \
        | uniq
    )

    if [ ${#VERSIONES_DISPONIBLES[@]} -eq 0 ]; then
        imprimir_error "No se encontraron versiones de Apache2 en el repositorio."
        imprimir_info  "Verifica tu conexion a internet o el archivo /etc/apt/sources.list"
        return 1
    fi

    echo "Versiones disponibles de Apache2:"
    echo "------------------------------------"
    for i in "${!VERSIONES_DISPONIBLES[@]}"; do
        if [ "$i" -eq 0 ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- Latest"
        elif [ "$i" -eq $((${#VERSIONES_DISPONIBLES[@]}-1)) ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- LTS/Estable"
        else
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}"
        fi
    done
    echo "------------------------------------"
    return 0
}

obtener_versiones_nginx() {
    imprimir_paso "Consultando versiones disponibles de Nginx en el repositorio..."
    echo ""

    apt-get update -qq 2>/dev/null

    mapfile -t VERSIONES_DISPONIBLES < <(
        apt-cache madison nginx 2>/dev/null \
        | awk '{print $3}'                  \
        | sort -Vr                          \
        | uniq
    )

    if [ ${#VERSIONES_DISPONIBLES[@]} -eq 0 ]; then
        imprimir_error "No se encontraron versiones de Nginx en el repositorio."
        return 1
    fi

    echo "Versiones disponibles de Nginx:"
    echo "------------------------------------"
    for i in "${!VERSIONES_DISPONIBLES[@]}"; do
        if [ "$i" -eq 0 ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- Latest"
        elif [ "$i" -eq $((${#VERSIONES_DISPONIBLES[@]}-1)) ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- LTS/Estable"
        else
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}"
        fi
    done
    echo "------------------------------------"
    return 0
}

obtener_versiones_tomcat() {
    imprimir_paso "Consultando versiones disponibles de Tomcat en downloads.apache.org..."
    echo ""

    mapfile -t VERSIONES_DISPONIBLES < <(
        curl -s --connect-timeout 10 "$TOMCAT_BASE_URL/" 2>/dev/null \
        | grep -oP 'tomcat-\K[0-9]+(?=/)' \
        | sort -Vr                         \
        | uniq                             \
        | while read -r rama; do
            # Para cada rama principal obtener la versión puntual más reciente
            version=$(
                curl -s --connect-timeout 10 "$TOMCAT_BASE_URL/tomcat-${rama}/" 2>/dev/null \
                | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+(?=/)' \
                | sort -Vr \
                | head -1
            )
            if [ -n "$version" ]; then
                echo "$version (rama $rama)"
            fi
        done
    )

    if [ ${#VERSIONES_DISPONIBLES[@]} -eq 0 ]; then
        imprimir_error "No se pudo conectar a downloads.apache.org"
        imprimir_info  "Verifica la conexion a internet del servidor."
        return 1
    fi

    echo "Versiones disponibles de Tomcat:"
    echo "------------------------------------"
    for i in "${!VERSIONES_DISPONIBLES[@]}"; do
        if [ "$i" -eq 0 ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- Latest"
        elif [ "$i" -eq $((${#VERSIONES_DISPONIBLES[@]}-1)) ]; then
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}  <- LTS/Estable"
        else
            echo "  $((i+1))) ${VERSIONES_DISPONIBLES[$i]}"
        fi
    done
    echo "------------------------------------"
    return 0
}

seleccionar_version() {
    local total="${#VERSIONES_DISPONIBLES[@]}"
    local opcion

    while true; do
        echo ""
        echo -n "Selecciona el numero de version [1-${total}]: "
        read -r opcion

        if [ -z "$opcion" ]; then
            imprimir_error "Debes ingresar una opcion."
            continue
        fi

        if ! [[ "$opcion" =~ ^[0-9]+$ ]]; then
            imprimir_error "Opcion invalida. Ingresa solo el numero."
            continue
        fi

        if [ "$opcion" -lt 1 ] || [ "$opcion" -gt "$total" ]; then
            imprimir_error "Opcion fuera de rango. Elige entre 1 y $total."
            continue
        fi

        VERSION_ELEGIDA="${VERSIONES_DISPONIBLES[$((opcion-1))]}"
        # Para Tomcat el formato es "X.X.X (rama Y)", extraemos solo el numero
        VERSION_ELEGIDA=$(echo "$VERSION_ELEGIDA" | awk '{print $1}')
        imprimir_ok "Version seleccionada: $VERSION_ELEGIDA"
        break
    done
}

# ==============================================================================
# BLOQUE 4: INSTALACIÓN DE SERVIDORES
# ==============================================================================

instalar_apache() {
    imprimir_paso "Iniciando instalacion silenciosa de Apache2 version $VERSION_ELEGIDA..."

    export DEBIAN_FRONTEND=noninteractive

    if apt-get install -y "apache2=${VERSION_ELEGIDA}" 2>/dev/null; then
        imprimir_ok "Apache2 $VERSION_ELEGIDA instalado correctamente."
    else
        imprimir_info "Version exacta no disponible. Instalando la version mas reciente..."
        apt-get install -y apache2 2>/dev/null || {
            imprimir_error "Fallo la instalacion de Apache2."
            return 1
        }
    fi

    # mod_headers es obligatorio para que funcionen los Security Headers del BLOQUE 7
    a2enmod headers 2>/dev/null
    a2enmod rewrite 2>/dev/null

    systemctl enable apache2 --quiet 2>/dev/null
    imprimir_ok "Servicio Apache2 habilitado en el arranque."
    return 0
}

# ------------------------------------------------------------------------------
# instalar_nginx
#
# Instala Nginx de forma silenciosa. Misma lógica que instalar_apache.
#
# Nota: Nginx no requiere habilitación de módulos adicionales porque
# los headers de seguridad se agregan directamente en nginx.conf
# como directivas add_header en el bloque server{}.
# ------------------------------------------------------------------------------
instalar_nginx() {
    imprimir_paso "Iniciando instalacion silenciosa de Nginx version $VERSION_ELEGIDA..."

    export DEBIAN_FRONTEND=noninteractive

    if apt-get install -y "nginx=${VERSION_ELEGIDA}" 2>/dev/null; then
        imprimir_ok "Nginx $VERSION_ELEGIDA instalado correctamente."
    else
        imprimir_info "Version exacta no disponible. Instalando la version mas reciente..."
        apt-get install -y nginx 2>/dev/null || {
            imprimir_error "Fallo la instalacion de Nginx."
            return 1
        }
    fi

    systemctl enable nginx --quiet 2>/dev/null
    imprimir_ok "Servicio Nginx habilitado en el arranque."
    return 0
}

# ------------------------------------------------------------------------------
# instalar_tomcat
#
# Tomcat requiere un proceso de instalación manual completamente diferente
# a Apache y Nginx, ya que no está en los repositorios APT estándar.
#
# Proceso detallado:
#
#   Paso 1 - Verificar Java:
#     Tomcat es una aplicación Java. Si Java no está instalado, se instala
#     OpenJDK 17 automáticamente. JAVA_HOME se detecta con readlink sobre
#     el binario `java` para obtener la ruta absoluta del JDK.
#
#   Paso 2 - Construir URL de descarga:
#     La rama se extrae del primer número de la versión (ej: 10.1.30 → rama 10).
#     La URL tiene la estructura:
#     downloads.apache.org/tomcat/tomcat-{rama}/v{version}/bin/apache-tomcat-{version}.tar.gz
#
#   Paso 3 - Descargar binario:
#     wget -q descarga silenciosamente. Si falla (versión incorrecta, sin red),
#     se reporta el error y se aborta.
#
#   Paso 4 - Extraer binario:
#     tar -xzf extrae el .tar.gz
#     --strip-components=1 elimina el directorio raíz interno del tar
#     para que los archivos queden directamente en /opt/tomcat/ sin subdirectorio.
#
#   Paso 5 - Variables de entorno:
#     CATALINA_HOME y JAVA_HOME se persisten en /etc/environment para que
#     estén disponibles en todos los shells, incluido el del servicio systemd.
#
#   Paso 6 - Servicio systemd:
#     Se crea /etc/systemd/system/tomcat.service para que Tomcat se pueda
#     gestionar con systemctl start/stop/restart/status tomcat, igual que
#     Apache y Nginx.
# ------------------------------------------------------------------------------
instalar_tomcat() {
    imprimir_paso "Iniciando instalacion de Apache Tomcat $VERSION_ELEGIDA..."

    # Paso 1: Verificar Java (dependencia obligatoria de Tomcat)
    if ! command -v java &>/dev/null; then
        imprimir_info "Java no encontrado. Instalando OpenJDK 17..."
        apt-get install -y openjdk-17-jdk 2>/dev/null || {
            imprimir_error "No se pudo instalar Java. Tomcat requiere Java para funcionar."
            return 1
        }
    fi
    imprimir_ok "Java disponible: $(java -version 2>&1 | head -1)"

    # Paso 2: Determinar rama y construir URL de descarga
    local rama_tomcat
    rama_tomcat=$(echo "$VERSION_ELEGIDA" | cut -d'.' -f1)
    local url_descarga="${TOMCAT_BASE_URL}/tomcat-${rama_tomcat}/v${VERSION_ELEGIDA}/bin/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"
    local archivo_tmp="/tmp/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"

    imprimir_paso "Descargando desde: $url_descarga"

    # Paso 3: Descargar binario .tar.gz desde el servidor oficial
    if ! wget -q --show-progress -O "$archivo_tmp" "$url_descarga" 2>/dev/null; then
        imprimir_error "No se pudo descargar Tomcat. Verifica la version o la conexion."
        return 1
    fi
    imprimir_ok "Descarga completada: $archivo_tmp"

    # Paso 4: Extraer binario en directorio de instalación
    if [ -d "$TOMCAT_INSTALL_DIR" ]; then
        imprimir_info "Directorio existente. Creando respaldo..."
        mv "$TOMCAT_INSTALL_DIR" "${TOMCAT_INSTALL_DIR}_backup_$(date +%Y%m%d%H%M%S)"
    fi
    mkdir -p "$TOMCAT_INSTALL_DIR"
    tar -xzf "$archivo_tmp" -C "$TOMCAT_INSTALL_DIR" --strip-components=1
    rm -f "$archivo_tmp"
    imprimir_ok "Tomcat extraido en $TOMCAT_INSTALL_DIR"

    # Paso 5: Configurar variables de entorno persistentes
    export CATALINA_HOME="$TOMCAT_INSTALL_DIR"
    export JAVA_HOME
    JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(which java)")")")

    grep -q "CATALINA_HOME" /etc/environment || \
        echo "CATALINA_HOME=$TOMCAT_INSTALL_DIR" >> /etc/environment
    grep -q "JAVA_HOME" /etc/environment || \
        echo "JAVA_HOME=$JAVA_HOME" >> /etc/environment

    imprimir_ok "Variables de entorno: CATALINA_HOME=$CATALINA_HOME | JAVA_HOME=$JAVA_HOME"

    # Paso 6: Crear servicio systemd para manejo con systemctl
    cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat $VERSION_ELEGIDA
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=$JAVA_HOME"
Environment="CATALINA_HOME=$TOMCAT_INSTALL_DIR"
Environment="CATALINA_PID=$TOMCAT_INSTALL_DIR/temp/tomcat.pid"
ExecStart=$TOMCAT_INSTALL_DIR/bin/startup.sh
ExecStop=$TOMCAT_INSTALL_DIR/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tomcat --quiet 2>/dev/null
    imprimir_ok "Servicio systemd de Tomcat creado y habilitado."
    return 0
}

# ==============================================================================
# BLOQUE 5: CAMBIO DE PUERTO EN ARCHIVOS DE CONFIGURACIÓN
# ==============================================================================
#
# Cada servidor tiene su propio archivo de configuración donde se define
# el puerto de escucha. Se usa sed -i para editar el archivo en sitio.
# Se hace un respaldo .bak antes de cualquier modificación.
# ==============================================================================

# ------------------------------------------------------------------------------
# cambiar_puerto_apache
#
# Archivos que se modifican:
#   /etc/apache2/ports.conf                      → directiva "Listen <puerto>"
#   /etc/apache2/sites-available/000-default.conf → "<VirtualHost *:<puerto>>"
#
# El patrón sed [0-9]* captura cualquier número existente para reemplazarlo,
# sin asumir que el puerto actual siempre es 80.
# ------------------------------------------------------------------------------
cambiar_puerto_apache() {
    local conf_ports="/etc/apache2/ports.conf"
    local conf_site="/etc/apache2/sites-available/000-default.conf"

    imprimir_paso "Configurando Apache2 para escuchar en puerto $PUERTO_ELEGIDO..."

    cp "$conf_ports" "${conf_ports}.bak.$(date +%Y%m%d%H%M%S)"

    sed -i "s/Listen [0-9]*/Listen $PUERTO_ELEGIDO/g" "$conf_ports"
    sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$PUERTO_ELEGIDO>/" "$conf_site"

    imprimir_ok "Puerto de Apache2 cambiado a $PUERTO_ELEGIDO"
    return 0
}

# ------------------------------------------------------------------------------
# cambiar_puerto_nginx
#
# Archivo que se modifica:
#   /etc/nginx/sites-available/default → directivas "listen <puerto>"
#
# Se actualizan dos variantes de la directiva listen:
#   - IPv4: "listen 80 ;"     → "listen 8080 ;"
#   - IPv6: "listen [::]:80"  → "listen [::]:8080"
# ------------------------------------------------------------------------------
cambiar_puerto_nginx() {
    local conf_nginx="/etc/nginx/sites-available/default"

    imprimir_paso "Configurando Nginx para escuchar en puerto $PUERTO_ELEGIDO..."

    cp "$conf_nginx" "${conf_nginx}.bak.$(date +%Y%m%d%H%M%S)"

    sed -i "s/listen [0-9]* /listen $PUERTO_ELEGIDO /g" "$conf_nginx"
    sed -i "s/listen \[::\]:[0-9]*/listen [::]:$PUERTO_ELEGIDO/g" "$conf_nginx"

    imprimir_ok "Puerto de Nginx cambiado a $PUERTO_ELEGIDO"
    return 0
}

# ------------------------------------------------------------------------------
# cambiar_puerto_tomcat
#
# Archivo que se modifica:
#   /opt/tomcat/conf/server.xml → atributo port del conector HTTP
#
# En server.xml el conector HTTP está definido como:
#   <Connector port="8080" protocol="HTTP/1.1" ...>
# Solo se reemplaza el 8080 (default de Tomcat) para no afectar
# otros conectores como AJP (8009) o shutdown (8005).
# ------------------------------------------------------------------------------
cambiar_puerto_tomcat() {
    local conf_server="$TOMCAT_INSTALL_DIR/conf/server.xml"

    imprimir_paso "Configurando Tomcat para escuchar en puerto $PUERTO_ELEGIDO..."

    cp "$conf_server" "${conf_server}.bak.$(date +%Y%m%d%H%M%S)"

    sed -i "s/port=\"8080\"/port=\"$PUERTO_ELEGIDO\"/g" "$conf_server"

    imprimir_ok "Puerto de Tomcat cambiado a $PUERTO_ELEGIDO en server.xml"
    return 0
}

# ==============================================================================
# BLOQUE 6: USUARIO DEDICADO Y PERMISOS
# ==============================================================================

crear_usuario_dedicado() {
    local usuario="$1"
    local directorio="$2"

    imprimir_paso "Creando usuario dedicado '$usuario' con permisos limitados..."

    if id "$usuario" &>/dev/null; then
        imprimir_info "El usuario '$usuario' ya existe. Omitiendo creacion."
    else
        useradd \
            --system \
            --no-create-home \
            --shell /bin/false \
            --comment "Usuario de servicio para $usuario" \
            "$usuario"
        imprimir_ok "Usuario '$usuario' creado (sin shell, sin home)."
    fi

    mkdir -p "$directorio"
    chown -R "${usuario}:${usuario}" "$directorio"
    chmod 750 "$directorio"
    chmod o-rwx "$directorio"

    imprimir_ok "Permisos configurados: $directorio -> propietario $usuario (chmod 750)"
    return 0
}

# ==============================================================================
# BLOQUE 7: HARDENING DE SEGURIDAD
# ==============================================================================

configurar_seguridad_apache() {
    local conf_security="/etc/apache2/conf-available/security.conf"

    imprimir_paso "Aplicando hardening de seguridad a Apache2..."

    # Capa 1: ServerTokens Prod → solo devuelve "Server: Apache" sin versión
    # ServerSignature Off → elimina firma de Apache en páginas de error
    if [ -f "$conf_security" ]; then
        cp "$conf_security" "${conf_security}.bak.$(date +%Y%m%d%H%M%S)"
        sed -i "s/ServerTokens OS/ServerTokens Prod/"         "$conf_security"
        sed -i "s/ServerTokens Full/ServerTokens Prod/"       "$conf_security"
        sed -i "s/ServerSignature On/ServerSignature Off/"    "$conf_security"
        sed -i "s/ServerSignature Email/ServerSignature Off/" "$conf_security"
        grep -q "ServerTokens"    "$conf_security" || echo "ServerTokens Prod"    >> "$conf_security"
        grep -q "ServerSignature" "$conf_security" || echo "ServerSignature Off"  >> "$conf_security"
    else
        echo "ServerTokens Prod"    > "$conf_security"
        echo "ServerSignature Off" >> "$conf_security"
    fi
    imprimir_ok "Capa 1: ServerTokens Prod y ServerSignature Off aplicados."

    # Capa 2: Security Headers en archivo dedicado
    local conf_headers="/etc/apache2/conf-available/security-headers.conf"
    cat > "$conf_headers" << 'EOF'
# Evita que el sitio sea cargado en un iframe de otro dominio (anti-Clickjacking)
Header always set X-Frame-Options "SAMEORIGIN"

# Evita que el navegador adivine el tipo MIME de la respuesta (anti-MIME sniffing)
Header always set X-Content-Type-Options "nosniff"

# Activa filtro XSS en navegadores que lo soportan
Header always set X-XSS-Protection "1; mode=block"

# Controla cuanta informacion de referrer se envia en peticiones cross-origin
Header always set Referrer-Policy "strict-origin-when-cross-origin"
EOF
    a2enconf security-headers 2>/dev/null
    imprimir_ok "Capa 2: Security Headers configurados."

    # Capa 3: Bloqueo de métodos HTTP peligrosos
    local conf_methods="/etc/apache2/conf-available/restrict-methods.conf"
    cat > "$conf_methods" << 'EOF'
# Deshabilitar TRACE globalmente (previene Cross-Site Tracing - XST)
TraceEnable Off

# Solo permitir GET, POST y HEAD en todos los directorios.
# Cualquier otro metodo sera rechazado con 403 Forbidden.
<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
EOF
    a2enconf restrict-methods 2>/dev/null
    imprimir_ok "Capa 3: Metodos TRACE, DELETE, TRACK bloqueados."

    apache2ctl configtest 2>/dev/null && systemctl reload apache2 2>/dev/null
    return 0
}

configurar_seguridad_nginx() {
    local conf_nginx="/etc/nginx/nginx.conf"
    local conf_site="/etc/nginx/sites-available/default"

    imprimir_paso "Aplicando hardening de seguridad a Nginx..."

    # Capa 1: server_tokens off elimina la versión del encabezado "Server: nginx"
    if grep -q "server_tokens" "$conf_nginx"; then
        sed -i "s/.*server_tokens.*/\tserver_tokens off;/" "$conf_nginx"
    else
        sed -i "/http {/a \\tserver_tokens off;" "$conf_nginx"
    fi
    imprimir_ok "Capa 1: server_tokens off configurado."

    # Capas 2 y 3: Headers de seguridad y bloqueo de métodos en el sitio default
    local bloque_seguridad="
    # Capa 2: Security Headers
    add_header X-Frame-Options 'SAMEORIGIN' always;
    add_header X-Content-Type-Options 'nosniff' always;
    add_header X-XSS-Protection '1; mode=block' always;
    add_header Referrer-Policy 'strict-origin-when-cross-origin' always;

    # Capa 3: Bloqueo de metodos peligrosos (devuelve 405 Method Not Allowed)
    if (\$request_method !~ ^(GET|POST|HEAD)\$) {
        return 405;
    }"

    if ! grep -q "X-Frame-Options" "$conf_site"; then
        sed -i "/server {/a $bloque_seguridad" "$conf_site"
    fi
    imprimir_ok "Capas 2 y 3: Security Headers y restriccion de metodos configurados."

    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null
    return 0
}

configurar_seguridad_tomcat() {
    local conf_server="$TOMCAT_INSTALL_DIR/conf/server.xml"
    local conf_web="$TOMCAT_INSTALL_DIR/conf/web.xml"

    imprimir_paso "Aplicando hardening de seguridad a Tomcat..."

    # Capa 1: El atributo server=" " en el conector hace que Tomcat devuelva
    # un encabezado Server vacío en lugar de "Apache-Coyote/1.1"
    sed -i 's/Server="Apache-Coyote\/[0-9.]*"/Server=" "/' "$conf_server"
    sed -i 's/protocol="HTTP\/1.1"/protocol="HTTP\/1.1" server=" "/' "$conf_server"
    imprimir_ok "Capa 1: Version de Tomcat ocultada en encabezados HTTP."

    # Capa 3: Bloquear métodos peligrosos en web.xml (estándar Java EE / Jakarta EE)
    if ! grep -q "Restrict TRACE" "$conf_web"; then
        sed -i "/<\/web-app>/i \\
    <security-constraint>\\
        <web-resource-collection>\\
            <web-resource-name>Restrict TRACE TRACK DELETE</web-resource-name>\\
            <url-pattern>/*</url-pattern>\\
            <http-method>TRACE</http-method>\\
            <http-method>TRACK</http-method>\\
            <http-method>DELETE</http-method>\\
        </web-resource-collection>\\
        <auth-constraint />\\
    </security-constraint>" "$conf_web"
    fi
    imprimir_ok "Capa 3: Metodos TRACE/TRACK/DELETE bloqueados en web.xml."

    systemctl restart tomcat 2>/dev/null
    return 0
}


# ------------------------------------------------------------------------------
configurar_firewall() {
    imprimir_paso "Configurando UFW - Firewall..."

    if ! command -v ufw &>/dev/null; then
        apt-get install -y ufw 2>/dev/null
    fi

    ufw --force enable 2>/dev/null

    # Regla 1 (CRITICA): SSH siempre abierto - se aplica antes que cualquier otra
    ufw allow 22/tcp comment "SSH - NO ELIMINAR" 2>/dev/null
    imprimir_ok "Puerto 22 (SSH) asegurado y abierto."

    # Regla 2: FTP siempre bloqueado
    ufw deny 21/tcp comment "FTP bloqueado" 2>/dev/null
    imprimir_ok "Puerto 21 (FTP) bloqueado."

    # Regla 3: Abrir el puerto elegido
    ufw allow "${PUERTO_ELEGIDO}/tcp" comment "HTTP ${SERVIDOR_ELEGIDO}" 2>/dev/null
    imprimir_ok "Puerto $PUERTO_ELEGIDO abierto para $SERVIDOR_ELEGIDO."

    # Regla 4: Cerrar puertos HTTP por defecto no utilizados
    local puertos_http_default=(80 8080 8888)
    for p in "${puertos_http_default[@]}"; do
        if [ "$p" -ne "$PUERTO_ELEGIDO" ]; then
            ufw deny "${p}/tcp" comment "Cerrado - no utilizado" 2>/dev/null
            imprimir_info "Puerto $p cerrado."
        fi
    done

    ufw reload 2>/dev/null
    imprimir_ok "Firewall recargado."
    echo ""
    echo "Estado actual del firewall:"
    ufw status verbose
    return 0
}


# ------------------------------------------------------------------------------
crear_index_html() {
    local directorio="$1"
    local archivo="${directorio}/index.html"

    imprimir_paso "Creando pagina index.html en $directorio..."

    mkdir -p "$directorio"

    cat > "$archivo" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${SERVIDOR_ELEGIDO} - Servidor Web</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .card {
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 16px;
            padding: 48px;
            text-align: center;
            max-width: 600px;
            width: 90%;
        }
        .badge {
            display: inline-block;
            background: #0f3460;
            border: 1px solid #e94560;
            border-radius: 999px;
            padding: 6px 20px;
            font-size: 13px;
            color: #e94560;
            margin-bottom: 24px;
            letter-spacing: 2px;
            text-transform: uppercase;
        }
        h1 { font-size: 2rem; margin-bottom: 8px; }
        .subtitle { color: #a0aec0; margin-bottom: 32px; }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 16px;
            margin-top: 32px;
        }
        .info-item {
            background: rgba(255,255,255,0.07);
            border-radius: 10px;
            padding: 20px 12px;
        }
        .info-label { font-size: 11px; color: #a0aec0; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
        .info-value { font-size: 1.1rem; font-weight: 600; color: #63b3ed; }
        .footer { margin-top: 32px; font-size: 12px; color: #4a5568; }
    </style>
</head>
<body>
    <div class="card">
        <div class="badge">Servidor Activo</div>
        <h1>${SERVIDOR_ELEGIDO}</h1>
        <p class="subtitle">Configurado automaticamente via script de aprovisionamiento</p>
        <div class="info-grid">
            <div class="info-item">
                <div class="info-label">Servidor</div>
                <div class="info-value">${SERVIDOR_ELEGIDO}</div>
            </div>
            <div class="info-item">
                <div class="info-label">Version</div>
                <div class="info-value">${VERSION_ELEGIDA}</div>
            </div>
            <div class="info-item">
                <div class="info-label">Puerto</div>
                <div class="info-value">${PUERTO_ELEGIDO}</div>
            </div>
        </div>
        <div class="footer">
            Practica 6 - Administracion de Sistemas | $(date '+%Y-%m-%d %H:%M:%S')
        </div>
    </div>
</body>
</html>
EOF

    imprimir_ok "index.html creado en: $archivo"
    return 0
}


iniciar_servicio() {
    local servicio="$1"

    imprimir_paso "Iniciando servicio: $servicio..."

    systemctl restart "$servicio" 2>/dev/null
    sleep 3

    if systemctl is-active --quiet "$servicio"; then
        imprimir_ok "Servicio $servicio activo y corriendo."
    else
        imprimir_error "El servicio $servicio no pudo iniciarse."
        imprimir_info  "Revisa los logs con: journalctl -xeu $servicio"
        return 1
    fi
    return 0
}


verificar_instalacion() {
    imprimir_paso "Verificando instalacion con: curl -I http://localhost:${PUERTO_ELEGIDO}"
    echo ""
    echo "============ ENCABEZADOS HTTP ============"

    if curl -s -I --max-time 10 "http://localhost:${PUERTO_ELEGIDO}" 2>/dev/null; then
        echo "=========================================="
        imprimir_ok "El servidor responde correctamente en el puerto $PUERTO_ELEGIDO"
    else
        imprimir_error "El servidor no respondio. Verifica la configuracion y los logs."
        return 1
    fi
    return 0
}

# ==============================================================================

flujo_apache() {
    SERVIDOR_ELEGIDO="Apache2"

    imprimir_encabezado
    echo "  Servidor seleccionado: $SERVIDOR_ELEGIDO"
    echo ""

    obtener_versiones_apache || return 1
    seleccionar_version
    solicitar_puerto

    echo ""
    echo "--------------------------------------------"
    echo "  Resumen de instalacion:"
    echo "  Servidor : $SERVIDOR_ELEGIDO"
    echo "  Version  : $VERSION_ELEGIDA"
    echo "  Puerto   : $PUERTO_ELEGIDO"
    echo "--------------------------------------------"
    echo -n "Confirmar instalacion? [s/N]: "
    read -r confirmacion
    if [[ ! "$confirmacion" =~ ^[sS]$ ]]; then
        imprimir_info "Instalacion cancelada."
        return 0
    fi

    instalar_apache                                      || return 1
    cambiar_puerto_apache                                || return 1
    crear_usuario_dedicado "www-data" "$WEB_ROOT_APACHE"
    crear_index_html "$WEB_ROOT_APACHE"
    configurar_seguridad_apache
    configurar_firewall
    iniciar_servicio "apache2"
    verificar_instalacion

    echo ""
    imprimir_ok "Apache2 instalado y configurado exitosamente."
}


flujo_nginx() {
    SERVIDOR_ELEGIDO="Nginx"

    imprimir_encabezado
    echo "  Servidor seleccionado: $SERVIDOR_ELEGIDO"
    echo ""

    obtener_versiones_nginx || return 1
    seleccionar_version
    solicitar_puerto

    echo ""
    echo "--------------------------------------------"
    echo "  Resumen de instalacion:"
    echo "  Servidor : $SERVIDOR_ELEGIDO"
    echo "  Version  : $VERSION_ELEGIDA"
    echo "  Puerto   : $PUERTO_ELEGIDO"
    echo "--------------------------------------------"
    echo -n "Confirmar instalacion? [s/N]: "
    read -r confirmacion
    if [[ ! "$confirmacion" =~ ^[sS]$ ]]; then
        imprimir_info "Instalacion cancelada."
        return 0
    fi

    instalar_nginx                                     || return 1
    cambiar_puerto_nginx                               || return 1
    crear_usuario_dedicado "nginx" "$WEB_ROOT_NGINX"
    crear_index_html "$WEB_ROOT_NGINX"
    configurar_seguridad_nginx
    configurar_firewall
    iniciar_servicio "nginx"
    verificar_instalacion

    echo ""
    imprimir_ok "Nginx instalado y configurado exitosamente."
}


flujo_tomcat() {
    SERVIDOR_ELEGIDO="Tomcat"

    imprimir_encabezado
    echo "  Servidor seleccionado: $SERVIDOR_ELEGIDO"
    echo ""

    obtener_versiones_tomcat || return 1
    seleccionar_version
    solicitar_puerto

    echo ""
    echo "--------------------------------------------"
    echo "  Resumen de instalacion:"
    echo "  Servidor : $SERVIDOR_ELEGIDO"
    echo "  Version  : $VERSION_ELEGIDA"
    echo "  Puerto   : $PUERTO_ELEGIDO"
    echo "--------------------------------------------"
    echo -n "Confirmar instalacion? [s/N]: "
    read -r confirmacion
    if [[ ! "$confirmacion" =~ ^[sS]$ ]]; then
        imprimir_info "Instalacion cancelada."
        return 0
    fi

    instalar_tomcat                                          || return 1
    cambiar_puerto_tomcat                                    || return 1
    crear_usuario_dedicado "tomcat" "$WEB_ROOT_TOMCAT"
    crear_index_html "$WEB_ROOT_TOMCAT"
    configurar_seguridad_tomcat
    configurar_firewall
    iniciar_servicio "tomcat"
    verificar_instalacion

    echo ""
    imprimir_ok "Tomcat instalado y configurado exitosamente."
}

# Fin de http_functions.sh
