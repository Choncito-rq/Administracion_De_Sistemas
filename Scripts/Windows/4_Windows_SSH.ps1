. .\Funtions_Win.ps1

while ($true){
Clear-Host
Write-Host "-------------------------------"
Write-Host "      ADMINISTRACION SSH"
Write-Host "-------------------------------"
Write-Host "1- Instalar SSH"
Write-Host "2- Reinstalar SSH"
Write-Host "3- Configurar IP fija"
Write-Host "4- Monitorear estado"
Write-Host "5- Salir"
$op = Read-Host "Selecciona opcion"

switch ($op) {
"1" { Install-SSHService }
"2" { Install-SSHService -Reinstall }
"3" { Set-SSHNetwork }
"4" { Test-SSHStatus; Read-Host "Presione Enter para volver" }
"5" { exit }
default { Write-Host "Opcion invalida" }

}
}
