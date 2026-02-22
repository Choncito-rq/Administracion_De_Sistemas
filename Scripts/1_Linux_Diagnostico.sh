#!/bin/bash
echo "===== DIAGNOSTICO DEL SISTEMA ====="
echo "Nombre del equipo:"
hostname

echo ""
echo "Direcciones IP:"
ip a | grep inet | grep -v 127.0.0.1

echo ""
echo "Espacio en disco:"
df -h /

