# NetDiag-Orellana

Script de medición activa (Fase 1, línea base y diagnóstico). Mide ping, traceroute, dig e iperf3 (TCP/UDP) hacia un destino institucional (ESPOCH) y uno externo. No realiza captura de paquetes ni inspecciona tráfico de terceros.

## Requisitos (Ubuntu)

    sudo apt install -y iputils-ping traceroute dnsutils iperf3 git jq curl

## Ejecución

    sudo env CICLOS=5 INTERVALO=900 ./netdiag.sh

- `CICLOS`: número de ciclos de medición (por defecto 5).
- `INTERVALO`: segundos entre inicios de ciclo (por defecto 900 = 15 min).
- Se usa `sudo` para el traceroute TCP de respaldo cuando ICMP está bloqueado.

## Configuración

En `netdiag.sh`: variables `IPERF_INST` e `IPERF_EXT` (servidores iperf3) y el arreglo `DESTINOS`. Si un servidor vale `CAMBIAR`, iperf3 se omite y se marca `NO_CONFIGURADO`.

## Salidas

- `data/sesion_<fecha>.csv`: `timestamp,ciclo,destino,tipo,host,metrica,valor,unidad,estado`
- `logs/<fecha>/sesion.txt`: hostname, usuario, IP, inicio y fin.
- `logs/<fecha>/traceroute_*.txt`: salida cruda de traceroute.
- `data/pruebas/` y `logs/pruebas/`: pruebas de depuración fuera del laboratorio.

## Notas

Si el destino bloquea ICMP, el script mide RTT, pérdida y jitter por TCP 443 (`tcp_*`) y lo marca como `ICMP_BLOQUEADO`.
