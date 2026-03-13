#Requires -RunAsAdministrator

$null = & cmd /c "chcp 65001" 2>$null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$lib = Join-Path $PSScriptRoot "http_functions.ps1"
if (-not (Test-Path $lib)) {
    Write-Host "  ERROR: http_functions.ps1 no encontrado." -ForegroundColor Red
    exit 1
}
. $lib

function Mostrar-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ================================================" -ForegroundColor White
    Write-Host "                    Despliegue HTTP               " -ForegroundColor White
    Write-Host "  ================================================" -ForegroundColor White
    Write-Host ""
}

function Mostrar-Menu {
    Write-Host "  Seleccione el servidor a instalar:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache"
    Write-Host "  [3] Nginx"
    Write-Host "  [4] Salir"
    Write-Host ""
    do { $opcion = Read-Host "  Opcion" } while ($opcion -notmatch "^[1-4]$")
    return $opcion
}

function Mostrar-Finalizacion {
    param([string]$Servicio, [int]$Puerto)
    Write-Host ""
    Write-Host "  ------------------------------------------------" -ForegroundColor White
    Escribir-Mensaje "$Servicio desplegado correctamente." "OK"
    Write-Host ""
    Write-Host "  Verificar con:" -ForegroundColor White
    Write-Host "  http://<IP_SERVIDOR>:$Puerto" -ForegroundColor White
    Write-Host "  ------------------------------------------------" -ForegroundColor White
    Write-Host ""
    Read-Host "  Presione Enter para continuar"
}

function Flujo-IIS {
    Mostrar-Banner
    Write-Host "  [ IIS ]" -ForegroundColor White
    Write-Host ""
    $version = Obtener-VersionIIS
    Write-Host "  Version: $($version.LTS)"
    Write-Host ""
    $puerto = Leer-Puerto
    Write-Host ""
    Write-Host "  Servicio : IIS $($version.LTS)"
    Write-Host "  Puerto   : $puerto"
    Write-Host ""
    $confirmacion = Read-Host "  Confirmar instalacion [S/N]"
    if ($confirmacion -notmatch "^[sS]$") { return }
    Instalar-IIS -Puerto $puerto
    Mostrar-Finalizacion -Servicio "IIS" -Puerto $puerto
}

function Flujo-Apache {
    Mostrar-Banner
    Write-Host "  [ Apache ]" -ForegroundColor White
    Write-Host ""
    Instalar-Chocolatey
    $versiones = Obtener-VersionesApache
    $elegida   = Mostrar-MenuVersiones -Servicio "Apache" -Versiones $versiones
    $puerto    = Leer-Puerto
    Write-Host ""
    Write-Host "  Servicio : Apache $elegida"
    Write-Host "  Puerto   : $puerto"
    Write-Host ""
    $confirmacion = Read-Host "  Confirmar instalacion [S/N]"
    if ($confirmacion -notmatch "^[sS]$") { return }
    $resultado = Instalar-Apache -Version $elegida -Puerto $puerto -Paquete $versiones.Paquete
    if ($resultado) { Mostrar-Finalizacion -Servicio "Apache" -Puerto $puerto }
    else { Escribir-Mensaje "La instalacion de Apache finalizo con errores." "ERROR"; Read-Host "  Presione Enter" }
}

function Flujo-Nginx {
    Mostrar-Banner
    Write-Host "  [ Nginx ]" -ForegroundColor White
    Write-Host ""
    Instalar-Chocolatey
    $versiones = Obtener-VersionesNginx
    $elegida   = Mostrar-MenuVersiones -Servicio "Nginx" -Versiones $versiones
    $puerto    = Leer-Puerto
    Write-Host ""
    Write-Host "  Servicio : Nginx $elegida"
    Write-Host "  Puerto   : $puerto"
    Write-Host ""
    $confirmacion = Read-Host "  Confirmar instalacion [S/N]"
    if ($confirmacion -notmatch "^[sS]$") { return }
    $resultado = Instalar-Nginx -Version $elegida -Puerto $puerto -Paquete $versiones.Paquete
    if ($resultado) { Mostrar-Finalizacion -Servicio "Nginx" -Puerto $puerto }
    else { Escribir-Mensaje "La instalacion de Nginx finalizo con errores." "ERROR"; Read-Host "  Presione Enter" }
}

function Iniciar {
    Verificar-Administrador
    $salir = $false
    do {
        Mostrar-Banner
        $opcion = Mostrar-Menu
        switch ($opcion) {
            "1" { Flujo-IIS    }
            "2" { Flujo-Apache }
            "3" { Flujo-Nginx  }
            "4" { $salir = $true }
        }
    } while (-not $salir)
}

Iniciar 
