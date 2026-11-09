#!/usr/bin/env bash
# Registro de evidencia de ejecución (E4)
mkdir -p logs
OUT="logs/evidencia_$(date +%Y%m%d_%H%M%S).txt"
{
  echo "=== EVIDENCIA DE EJECUCION ==="
  echo "hostname : $(hostname)"
  echo "usuario  : $(whoami)"
  echo "fecha    : $(date '+%F %T %Z')"
  echo "ip local : $(hostname -I)"
  echo "gateway  : $(ip route | awk '/default/ {print $3; exit}')"
  echo "interfaz : $(ip route | awk '/default/ {print $5; exit}')"
  echo "red wifi : $(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2)"
  echo "ip publ. : $(curl -s -m 5 https://ifconfig.me)"
} | tee "$OUT"
