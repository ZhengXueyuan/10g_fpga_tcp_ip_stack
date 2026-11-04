#!/bin/bash
set -u
B=/tmp/p7b_biz; P=/home/a/p11_bench
mk(){ ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 16777216 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin 2>&1; }
sleep 2
for r in 1 2 3; do
  mk > $P/pair_${r}a.txt & mk > $P/pair_${r}b.txt &
  wait
  echo "R$r A=$(grep -oE 'conn_ms=[0-9.]+' $P/pair_${r}a.txt | tail -1) $(grep -oE 'bytes=[0-9]+' $P/pair_${r}a.txt | tail -1)"
  echo "R$r B=$(grep -oE 'conn_ms=[0-9.]+' $P/pair_${r}b.txt | tail -1) $(grep -oE 'bytes=[0-9]+' $P/pair_${r}b.txt | tail -1)"
  sleep 2
done
