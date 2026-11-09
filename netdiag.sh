#!/usr/bin/env bash
# NetDiag-Orellana - Script de medición activa (Fase 1)
# Mide: ping, traceroute, dig, iperf3 (TCP y UDP). Sin captura de paquetes.
set -u

CICLOS="${CICLOS:-5}"
INTERVALO="${INTERVALO:-900}"   # segundos entre inicios de ciclo (900 = 15 min)
PING_N=20
IPERF_T=10

# Servidores iperf3 (cambiar cuando los tengas; "CAMBIAR" = se omite iperf3)
IPERF_INST="CAMBIAR"
IPERF_EXT="CAMBIAR"

# nombre|tipo|host(ping/traceroute)|dominio(dig)|servidor_iperf|puerto
DESTINOS=(
  "espoch|INSTITUCIONAL|www.espoch.edu.ec|www.espoch.edu.ec|$IPERF_INST|5201"
  "externo|EXTERNO|1.1.1.1|google.com|$IPERF_EXT|5201"
)

SESION=$(date +%Y%m%d_%H%M%S)
mkdir -p data "logs/$SESION"
CSV="data/sesion_${SESION}.csv"
LOGDIR="logs/$SESION"
echo "timestamp,ciclo,destino,tipo,host,metrica,valor,unidad,estado" > "$CSV"

reg() { echo "$(date -Iseconds),$CICLO,$nombre,$tipo,$host,$1,$2,$3,$4" >> "$CSV"; }

medir_ping() {
  local out loss lista min med max jit
  out=$(ping -c "$PING_N" -i 0.5 -W 2 "$host" 2>&1)
  loss=$(echo "$out" | grep -oP '[0-9.]+(?=% packet loss)')
  lista=$(echo "$out" | grep -oP 'time=\K[0-9.]+')
  if [ -z "$lista" ]; then
    reg ping_icmp_loss "${loss:-100}" % ICMP_BLOQUEADO
    medir_tcp
    return
  fi
  min=$(echo "$lista" | sort -n | head -1)
  max=$(echo "$lista" | sort -n | tail -1)
  med=$(echo "$lista" | sort -n | awk '{a[NR]=$1} END{printf "%.3f",(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')
  jit=$(echo "$lista" | awk 'NR>1{d=$1-p;if(d<0)d=-d;s+=d;n++}{p=$1}END{if(n>0)printf "%.3f",s/n;else print 0}')
  reg ping_rtt_min "$min" ms OK
  reg ping_rtt_mediana "$med" ms OK
  reg ping_rtt_max "$max" ms OK
  reg ping_loss "$loss" % OK
  reg ping_jitter "$jit" ms OK
}

medir_tcp() {
  local lista="" fallos=0 t i n min med max jit loss
  for ((i=1; i<=PING_N; i++)); do
    t=$(curl -sI -o /dev/null -m 3 -w '%{time_connect}' "https://$host" 2>/dev/null)
    if [ -n "$t" ] && [ "$t" != "0.000000" ]; then
      lista+="$(awk -v t="$t" 'BEGIN{printf "%.3f",t*1000}')"$'\n'
    else
      fallos=$((fallos+1))
    fi
    sleep 0.5
  done
  lista=$(printf "%s" "$lista" | sed '/^$/d')
  loss=$(awk -v f="$fallos" -v n="$PING_N" 'BEGIN{printf "%.1f",100*f/n}')
  if [ -z "$lista" ]; then
    reg tcp_loss "$loss" % ERROR
    return
  fi
  min=$(echo "$lista" | sort -n | head -1)
  max=$(echo "$lista" | sort -n | tail -1)
  med=$(echo "$lista" | sort -n | awk '{a[NR]=$1} END{printf "%.3f",(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}')
  jit=$(echo "$lista" | awk 'NR>1{d=$1-p;if(d<0)d=-d;s+=d;n++}{p=$1}END{if(n>0)printf "%.3f",s/n;else print 0}')
  reg tcp_rtt_min "$min" ms OK
  reg tcp_rtt_mediana "$med" ms OK
  reg tcp_rtt_max "$max" ms OK
  reg tcp_loss "$loss" % OK
  reg tcp_jitter "$jit" ms OK
}

medir_traceroute() {
  local out saltos ultimo
  out=$(traceroute -n -q 1 -w 2 -m 20 "$host" 2>&1)
  if echo "$out" | tail -1 | grep -qE '^ *[0-9]+ +\*'; then
    [ "$(id -u)" -eq 0 ] && out=$(traceroute -T -p 443 -n -q 1 -w 2 -m 20 "$host" 2>&1)
  fi
  echo "$out" > "$LOGDIR/traceroute_${nombre}_c${CICLO}.txt"
  saltos=$(echo "$out" | grep -cE '^ *[0-9]+ ')
  ultimo=$(echo "$out" | tail -1)
  if echo "$ultimo" | grep -qE '^ *[0-9]+ +\*'; then
    reg traceroute_saltos "$saltos" saltos INCOMPLETO
  else
    reg traceroute_saltos "$saltos" saltos OK
  fi
}

medir_dns() {
  local out st qt
  out=$(dig +tries=1 +time=3 "$dominio" A 2>&1)
  st=$(echo "$out" | grep -oP 'status: \K[A-Z]+')
  qt=$(echo "$out" | grep -oP 'Query time: \K[0-9]+')
  if [ "$st" = "NOERROR" ] && [ -n "$qt" ]; then
    reg dns_query_time "$qt" ms OK
  else
    reg dns_query_time "" ms ERROR
  fi
}

medir_iperf() {
  local out mbps jit loss
  if [ "$srv" = "CAMBIAR" ]; then
    reg iperf_tcp_mbps "" Mbps NO_CONFIGURADO
    reg iperf_udp_mbps "" Mbps NO_CONFIGURADO
    return
  fi
  out=$(timeout $((IPERF_T+15)) iperf3 -c "$srv" -p "$port" -t "$IPERF_T" -J 2>/dev/null)
  mbps=$(echo "$out" | jq -r '.end.sum_received.bits_per_second // empty' 2>/dev/null)
  if [ -n "$mbps" ]; then
    reg iperf_tcp_mbps "$(awk -v b="$mbps" 'BEGIN{printf "%.2f",b/1e6}')" Mbps OK
  else
    reg iperf_tcp_mbps "" Mbps ERROR
  fi
  out=$(timeout $((IPERF_T+15)) iperf3 -c "$srv" -p "$port" -u -b 10M -t "$IPERF_T" -J 2>/dev/null)
  mbps=$(echo "$out" | jq -r '.end.sum.bits_per_second // empty' 2>/dev/null)
  jit=$(echo "$out" | jq -r '.end.sum.jitter_ms // empty' 2>/dev/null)
  loss=$(echo "$out" | jq -r '.end.sum.lost_percent // empty' 2>/dev/null)
  if [ -n "$mbps" ]; then
    reg iperf_udp_mbps "$(awk -v b="$mbps" 'BEGIN{printf "%.2f",b/1e6}')" Mbps OK
    reg iperf_udp_jitter "$jit" ms OK
    reg iperf_udp_loss "$loss" % OK
  else
    reg iperf_udp_mbps "" Mbps ERROR
  fi
}

{
  echo "hostname: $(hostname)"
  echo "usuario: $(whoami)"
  echo "ip: $(hostname -I)"
  echo "inicio: $(date -Iseconds)"
  echo "ciclos: $CICLOS  intervalo(s): $INTERVALO"
} > "$LOGDIR/sesion.txt"

INICIO=$(date +%s)
for ((CICLO=1; CICLO<=CICLOS; CICLO++)); do
  objetivo=$((INICIO + (CICLO-1)*INTERVALO))
  ahora=$(date +%s)
  [ "$ahora" -lt "$objetivo" ] && sleep $((objetivo-ahora))
  echo "[$(date +%T)] Ciclo $CICLO/$CICLOS"
  for d in "${DESTINOS[@]}"; do
    IFS='|' read -r nombre tipo host dominio srv port <<< "$d"
    echo "   -> $nombre ($host)"
    medir_ping; medir_traceroute; medir_dns; medir_iperf
  done
done

echo "fin: $(date -Iseconds)" >> "$LOGDIR/sesion.txt"
echo "Listo. Dataset: $CSV"
[ -n "${SUDO_USER:-}" ] && chown -R "$SUDO_USER": data logs
