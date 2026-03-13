
$null = & cmd /c "chcp 65001" 2>$null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

function Escribir-Mensaje {
    param(
        [string]$Texto,
        [ValidateSet("INFO","OK","ERROR")]
        [string]$Tipo = "INFO"
    )
    $color = switch ($Tipo) {
        "OK"    { "Green" }
        "ERROR" { "Red"   }
        default { "White" }
    }
    Write-Host "  $Texto" -ForegroundColor $color
}

function Verificar-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Escribir-Mensaje "Ejecute el script como Administrador." "ERROR"
        exit 1
    }
}

function Leer-Puerto {
    $puertosReservados = @(21,22,23,25,53,443,3306,3389,5985,5986)
    do {
        $entrada = Read-Host "  Puerto de escucha"
        if ($entrada -notmatch "^\d+$") {
            Escribir-Mensaje "Ingrese solo numeros." "ERROR"; continue
        }
        $numero = [int]$entrada
        if ($numero -lt 1 -or $numero -gt 65535) {
            Escribir-Mensaje "Puerto fuera de rango (1-65535)." "ERROR"; continue
        }
        if ($puertosReservados -contains $numero) {
            Escribir-Mensaje "Puerto $numero reservado para otro servicio." "ERROR"; continue
        }
        $enUso = Test-NetConnection -ComputerName localhost -Port $numero `
                     -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($enUso.TcpTestSucceeded) {
            Escribir-Mensaje "Puerto $numero ya esta en uso." "ERROR"; continue
        }
        $valido = $true
    } while (-not $valido)
    return $numero
}

function Instalar-Chocolatey {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
    $rutaChoco = "$env:ProgramData\chocolatey\bin\choco.exe"
    $disponible = (Get-Command choco -ErrorAction SilentlyContinue) -or (Test-Path $rutaChoco)
    if ($disponible) {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            $env:PATH += ";$env:ProgramData\chocolatey\bin"
        }
        return
    }
    Escribir-Mensaje "Instalando gestor de paquetes..." "INFO"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1')) *>&1 | Out-Null
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
        Escribir-Mensaje "Gestor de paquetes listo." "OK"
    } catch {
        Escribir-Mensaje "Error al instalar gestor de paquetes: $_" "ERROR"; exit 1
    }
}

function Obtener-VersionIIS {
    $caracteristica = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($caracteristica -and $caracteristica.Installed) {
        $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -EA SilentlyContinue).VersionString
        return @{ LTS = $version; Latest = $version; Paquete = "WindowsFeature" }
    }
    return @{ LTS = "10.0 (WS2022)"; Latest = "10.0 (WS2022)"; Paquete = "WindowsFeature" }
}

function Consultar-APIChocolatey {
    param([string]$NombrePaquete, [int]$Cantidad = 40)
    $url = "https://community.chocolatey.org/api/v2/FindPackagesById()" +
           "?id='$NombrePaquete'&`$top=$Cantidad"
    $respuesta = Invoke-RestMethod -Uri $url -UseBasicParsing -ErrorAction Stop
    $versiones = $respuesta | ForEach-Object { $_.properties.Version } |
                 Where-Object { $_ -match "^\d+\.\d+" } |
                 Select-Object -Unique |
                 Sort-Object { [version]($_ -replace "[^0-9\.].*","") }
    return $versiones
}

function Obtener-VersionesApache {
    $paquete = "apache-httpd"
    try {
        $versiones = Consultar-APIChocolatey -NombrePaquete $paquete -Cantidad 40
        if (-not $versiones -or @($versiones).Count -eq 0) { throw "sin resultados" }
        $versiones = @($versiones) | Where-Object {
            $_ -notmatch "\.\d{8}$" -and
            ([version]($_ -replace "[^0-9\.].*","")) -ge [version]"2.4.46"
        }
        if (@($versiones).Count -eq 0) { throw "sin versiones compatibles" }
        $versiones = @($versiones)
        return @{ LTS=$versiones[0]; Latest=$versiones[-1]; Todas=$versiones; Paquete=$paquete }
    } catch {
        try {
            $salida = choco search $paquete --exact --all-versions 2>&1
            $versiones = @($salida | ForEach-Object {
                if ($_ -match "^$paquete\s+([\d]+\.[\d]+[\.\d]*)") { $Matches[1] }
            } | Where-Object {
                $_ -notmatch "\.\d{8}$" -and
                ([version]($_ -replace "[^0-9\.].*","")) -ge [version]"2.4.46"
            } | Select-Object -Unique |
              Sort-Object { [version]($_ -replace "[^0-9\.].*","") })
            if ($versiones.Count -eq 0) { throw "sin resultados" }
            return @{ LTS=$versiones[0]; Latest=$versiones[-1]; Todas=$versiones; Paquete=$paquete }
        } catch {
            $versiones = @("2.4.46","2.4.48","2.4.51","2.4.53","2.4.55")
            return @{ LTS="2.4.46"; Latest="2.4.55"; Todas=$versiones; Paquete=$paquete }
        }
    }
}

function Obtener-VersionesNginx {
    $paquete = "nginx"
    try {
        $versiones = Consultar-APIChocolatey -NombrePaquete $paquete -Cantidad 40
        if (-not $versiones -or @($versiones).Count -eq 0) { throw "sin resultados" }
        $versiones = @($versiones)
        $lts = $versiones | Where-Object {
            $_ -match "^\d+\.(\d+)\." -and ([int]$Matches[1] % 2 -eq 0)
        } | Select-Object -Last 1
        $latest = $versiones | Select-Object -Last 1
        if (-not $lts) { $lts = $latest }
        return @{ LTS=$lts; Latest=$latest; Todas=$versiones; Paquete=$paquete }
    } catch {
        try {
            $salida = choco search $paquete --exact --all-versions 2>&1
            $versiones = @($salida | ForEach-Object {
                if ($_ -match "^$paquete\s+([\d]+\.[\d]+[\.\d]*)") { $Matches[1] }
            } | Select-Object -Unique |
              Sort-Object { [version]($_ -replace "[^0-9\.].*","") })
            if ($versiones.Count -eq 0) { throw "sin resultados" }
            $lts = $versiones | Where-Object {
                $_ -match "^\d+\.(\d+)\." -and ([int]$Matches[1] % 2 -eq 0)
            } | Select-Object -Last 1
            $latest = $versiones | Select-Object -Last 1
            if (-not $lts) { $lts = $latest }
            return @{ LTS=$lts; Latest=$latest; Todas=$versiones; Paquete=$paquete }
        } catch {
            return @{ LTS="1.26.2"; Latest="1.27.4"; Todas=@("1.26.2","1.27.4"); Paquete=$paquete }
        }
    }
}

function Mostrar-MenuVersiones {
    param([string]$Servicio, [hashtable]$Versiones)
    Write-Host ""
    Write-Host "  Versiones disponibles - $Servicio" -ForegroundColor White
    Write-Host "  [1] Estable  : $($Versiones.LTS)"
    Write-Host "  [2] Reciente : $($Versiones.Latest)"
    Write-Host ""
    do { $seleccion = Read-Host "  Seleccione [1-2]" } while ($seleccion -notmatch "^[12]$")
    if ($seleccion -eq "1") { return $Versiones.LTS } else { return $Versiones.Latest }
}

function Crear-UsuarioServicio {
    param([string]$NombreServicio, [string]$DirectorioWeb = "C:\inetpub\wwwroot")
    $usuario = "svc_$($NombreServicio.ToLower())"
    if (-not (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
        $caracteres = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$'
        $contrasena = -join ((1..16) | ForEach-Object { $caracteres[(Get-Random -Maximum $caracteres.Length)] })
        $contrasenaSegura = ConvertTo-SecureString -String $contrasena -AsPlainText -Force
        New-LocalUser `
            -Name                 $usuario `
            -Password             $contrasenaSegura `
            -PasswordNeverExpires:$true `
            -UserMayNotChangePassword:$true `
            -Description          "Cuenta de servicio $NombreServicio" | Out-Null
    }
    if (Test-Path $DirectorioWeb) {
        try {
            $acl  = Get-Acl -Path $DirectorioWeb
            $sid  = (Get-LocalUser -Name $usuario).SID
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sid, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow")
            $acl.SetAccessRule($regla)
            Set-Acl -Path $DirectorioWeb -AclObject $acl
        } catch {}
    }
    return $usuario
}

function Instalar-IIS {
    param([int]$Puerto)
    Escribir-Mensaje "Instalando IIS..." "INFO"
    $caracteristicas = @("Web-Server","Web-Common-Http","Web-Static-Content","Web-Default-Doc",
                         "Web-Http-Errors","Web-Security","Web-Filtering","Web-Http-Logging",
                         "Web-Mgmt-Tools","Web-Mgmt-Console")
    foreach ($c in $caracteristicas) {
        Install-WindowsFeature -Name $c -IncludeManagementTools -EA SilentlyContinue | Out-Null
    }
    Import-Module WebAdministration -ErrorAction Stop
    Configurar-PuertoIIS    -Puerto $Puerto
    Aplicar-SeguridadIIS
    Crear-UsuarioServicio   -NombreServicio "IIS" -DirectorioWeb "C:\inetpub\wwwroot"
    $version = (Obtener-VersionIIS).LTS
    Crear-PaginaInicio      -DirectorioWeb "C:\inetpub\wwwroot" -Servicio "IIS" -Version $version -Puerto $Puerto
    Configurar-Firewall     -Puerto $Puerto
    Start-Service W3SVC -ErrorAction SilentlyContinue
    Escribir-Mensaje "IIS instalado correctamente." "OK"
}

function Instalar-Apache {
    param([string]$Version, [int]$Puerto, [string]$Paquete = "apache-httpd")
    Escribir-Mensaje "Instalando Apache $Version..." "INFO"
    $argumentos = @("install",$Paquete,"--confirm","--no-progress","-y")
    if ($Version -notmatch "^(latest|stable)$") { $argumentos += "--version"; $argumentos += $Version }
    & choco @argumentos *>&1 | Out-Null

    $apacheExiste = Test-Path "$env:APPDATA\Apache24\bin\httpd.exe"
    if ($LASTEXITCODE -ne 0 -and -not $apacheExiste) {
        Escribir-Mensaje "Error al instalar Apache." "ERROR"
        return $false
    }

    $raiz = @(
        "$env:APPDATA\Apache24",
        "C:\Apache24",
        "C:\Program Files\Apache24",
        "C:\Apache",
        (Get-ChildItem "$env:APPDATA" -Filter "Apache24" -Directory -EA SilentlyContinue |
            Select-Object -First 1 -Expand FullName),
        (Get-ChildItem "C:\ProgramData\chocolatey\lib\apache-httpd" -Filter "Apache24" -Recurse -Directory -EA SilentlyContinue |
            Select-Object -First 1 -Expand FullName)
    ) | Where-Object { $_ -and (Test-Path "$_\bin\httpd.exe") } | Select-Object -First 1

    if (-not $raiz) {
        $encontrado = Get-ChildItem "$env:APPDATA","C:\" -Filter "httpd.exe" -Recurse -EA SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) { $raiz = $encontrado.DirectoryName -replace "\\bin$","" }
    }
    if (-not $raiz) { Escribir-Mensaje "No se encontro el directorio de Apache." "ERROR"; return $false }

    Configurar-PuertoApache   -Puerto $Puerto -RaizApache $raiz
    Aplicar-SeguridadApache   -RaizApache $raiz
    Crear-UsuarioServicio     -NombreServicio "Apache" -DirectorioWeb "$raiz\htdocs"
    Crear-PaginaInicio        -DirectorioWeb "$raiz\htdocs" -Servicio "Apache" -Version $Version -Puerto $Puerto
    Configurar-Firewall       -Puerto $Puerto

    $httpd = "$raiz\bin\httpd.exe"
    if (Test-Path $httpd) {
        foreach ($nombre in @("Apache","Apache2.4","httpd")) {
            $servicio = Get-Service -Name $nombre -EA SilentlyContinue
            if ($servicio -and $servicio.Status -eq "Running") {
                Stop-Service $nombre -Force -EA SilentlyContinue
            }
        }
        & $httpd -k uninstall 2>&1 | Out-Null
        & $httpd -k install  2>&1 | Out-Null
        Start-Service Apache2.4 -EA SilentlyContinue
        Start-Sleep -Seconds 2
        $estado = Get-Service Apache2.4 -EA SilentlyContinue
        if ($estado -and $estado.Status -eq "Running") {
            Escribir-Mensaje "Apache instalado correctamente." "OK"
        } else {
            Escribir-Mensaje "Apache no pudo iniciarse. Revise los logs." "ERROR"
            return $false
        }
    } else {
        Escribir-Mensaje "httpd.exe no encontrado." "ERROR"
        return $false
    }
    return $true
}

function Instalar-Nginx {
    param([string]$Version, [int]$Puerto, [string]$Paquete = "nginx")
    Escribir-Mensaje "Instalando Nginx $Version..." "INFO"
    $argumentos = @("install",$Paquete,"--confirm","--no-progress","-y")
    if ($Version -notmatch "^(latest|stable)$") { $argumentos += "--version"; $argumentos += $Version }
    & choco @argumentos *>&1 | Out-Null

    $nginxExe = Get-ChildItem "C:\ProgramData\chocolatey\lib\nginx\tools" `
                    -Filter "nginx.exe" -Recurse -EA SilentlyContinue | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -and -not $nginxExe) {
        Escribir-Mensaje "Error al instalar Nginx." "ERROR"
        return $false
    }
    if (-not $nginxExe) {
        Escribir-Mensaje "nginx.exe no encontrado." "ERROR"
        return $false
    }

    $raiz         = $nginxExe.DirectoryName
    $directorioWeb = "$raiz\html"
    $archivoConf  = "$raiz\conf\nginx.conf"

    if (Test-Path $archivoConf) {
        $primerosTres = [System.IO.File]::ReadAllBytes($archivoConf) | Select-Object -First 3
        if ($primerosTres[0] -eq 239 -and $primerosTres[1] -eq 187 -and $primerosTres[2] -eq 191) {
            $contenido = Get-Content $archivoConf
            $sinBOM = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllLines($archivoConf, $contenido, $sinBOM)
        }
        Configurar-PuertoNginx -Puerto $Puerto -ArchivoConf $archivoConf
    }

    Crear-UsuarioServicio -NombreServicio "Nginx" -DirectorioWeb $directorioWeb
    Crear-PaginaInicio    -DirectorioWeb $directorioWeb -Servicio "Nginx" -Version $Version -Puerto $Puerto
    Configurar-Firewall   -Puerto $Puerto

    Get-Process nginx -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep 1
    $proceso = Start-Process $nginxExe.FullName -WorkingDirectory $raiz -WindowStyle Hidden -PassThru
    Start-Sleep 2

    $escuchando = Test-NetConnection -ComputerName localhost -Port $Puerto `
                      -WarningAction SilentlyContinue -EA SilentlyContinue
    if ($escuchando.TcpTestSucceeded) {
        Escribir-Mensaje "Nginx instalado correctamente." "OK"
    } else {
        Escribir-Mensaje "Nginx no responde en puerto $Puerto." "ERROR"
        return $false
    }
    return $true
}

function Configurar-PuertoIIS {
    param([int]$Puerto)
    Import-Module WebAdministration -EA SilentlyContinue
    $sitio = "Default Web Site"
    Get-WebBinding -Name $sitio | Remove-WebBinding
    New-WebBinding -Name $sitio -Protocol http -Port $Puerto -IPAddress "*" | Out-Null
}

function Configurar-PuertoApache {
    param([int]$Puerto, [string]$RaizApache = "C:\Apache24")
    $conf = "$RaizApache\conf\httpd.conf"
    if (-not (Test-Path $conf)) { return }
    (Get-Content $conf) -replace "(?m)^Listen \d+", "Listen $Puerto" |
        Set-Content $conf -Encoding UTF8
}

function Configurar-PuertoNginx {
    param([int]$Puerto, [string]$ArchivoConf)
    if (-not (Test-Path $ArchivoConf)) { return }
    $contenido = (Get-Content $ArchivoConf) -replace "listen\s+\d+;", "listen $Puerto;"
    $sinBOM = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($ArchivoConf, $contenido, $sinBOM)
}

function Aplicar-SeguridadIIS {
    Import-Module WebAdministration -EA SilentlyContinue
    $sitio  = "Default Web Site"
    $filtro = "system.webServer/httpProtocol/customHeaders"
    try {
        Remove-WebConfigurationProperty -PSPath "IIS:\Sites\$sitio" `
            -Filter $filtro -Name "." -AtElement @{name="X-Powered-By"} -EA SilentlyContinue
    } catch {}
    try {
        $existentes = @(Get-WebConfigurationProperty -PSPath "IIS:\Sites\$sitio" `
                            -Filter $filtro -Name "." -EA Stop |
                        ForEach-Object { $_.Attributes["name"].Value })
    } catch { $existentes = @() }
    @{
        "X-Frame-Options"        = "SAMEORIGIN"
        "X-Content-Type-Options" = "nosniff"
        "X-XSS-Protection"       = "1; mode=block"
    }.GetEnumerator() | ForEach-Object {
        if ($existentes -notcontains $_.Key) {
            Add-WebConfigurationProperty -PSPath "IIS:\Sites\$sitio" `
                -Filter $filtro -Name "." -Value @{name=$_.Key; value=$_.Value} -EA SilentlyContinue
        }
    }
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering" `
        -Name "removeServerHeader" -Value $true -EA SilentlyContinue
    $filtroVerbs = "system.webServer/security/requestFiltering/verbs"
    try {
        $verbsActual = @(Get-WebConfigurationProperty -PSPath "IIS:\" `
                             -Filter $filtroVerbs -Name "." -EA Stop |
                         ForEach-Object { $_.Attributes["verb"].Value })
    } catch { $verbsActual = @() }
    foreach ($metodo in @("TRACE","TRACK","DELETE","PUT")) {
        if ($verbsActual -notcontains $metodo) {
            Add-WebConfigurationProperty -PSPath "IIS:\" `
                -Filter $filtroVerbs -Name "." `
                -Value @{verb=$metodo; allowed="false"} -EA SilentlyContinue
        }
    }
}

function Aplicar-SeguridadApache {
    param([string]$RaizApache = "C:\Apache24")
    $conf = "$RaizApache\conf\httpd.conf"
    if (-not (Test-Path $conf)) { return }
    $bloque = @"

ServerTokens Prod
ServerSignature Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
</IfModule>

<Location />
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>
"@
    Add-Content -Path $conf -Value $bloque -Encoding UTF8
}

function Configurar-Firewall {
    param([int]$Puerto)
    $nombre = "HTTP-Script-$Puerto"
    if (-not (Get-NetFirewallRule -DisplayName $nombre -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $nombre -Direction Inbound `
            -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    }
    foreach ($p in @(80,8080)) {
        if ($p -ne $Puerto) {
            $vieja = "HTTP-Script-$p"
            if (Get-NetFirewallRule -DisplayName $vieja -EA SilentlyContinue) {
                Remove-NetFirewallRule -DisplayName $vieja | Out-Null
            }
        }
    }
}

function Crear-PaginaInicio {
    param([string]$DirectorioWeb, [string]$Servicio, [string]$Version, [int]$Puerto)
    if (-not (Test-Path $DirectorioWeb)) { New-Item -ItemType Directory -Path $DirectorioWeb -Force | Out-Null }
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$Servicio Desplegado</title>
</head>
<body>

<h1>$Servicio</h1>
<hr>

<table border="1" cellpadding="5" cellspacing="0">
  <tr>
    <th>Campo</th>
    <th>Valor</th>
  </tr>
  <tr>
    <td>Servicio</td>
    <td>$Servicio</td>
  </tr>
  <tr>
    <td>Version</td>
    <td>$Version</td>
  </tr>
  <tr>
    <td>Puerto</td>
    <td>$Puerto</td>
  </tr>
  <tr>
    <td>Instalado el</td>
    <td>$fecha</td>
  </tr>
</table>

<hr>
<p>Desplegado automaticamente - Tarea 6 Administracion de Sistemas</p>

</body>
</html>
"@
    Set-Content -Path "$DirectorioWeb\index.html" -Value $html -Encoding UTF8
}
