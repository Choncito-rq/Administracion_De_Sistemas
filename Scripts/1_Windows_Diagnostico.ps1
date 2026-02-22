Write-Host "===== DIAGNOSTICO DEL SISTEMA ====="

Write-Host "Nombre del equipo:"
hostname

Write-Host ""
Write-Host "Direcciones IP:"
ipconfig

Write-Host ""
Write-Host "Espacio en disco:"
Get-PSDrive C

