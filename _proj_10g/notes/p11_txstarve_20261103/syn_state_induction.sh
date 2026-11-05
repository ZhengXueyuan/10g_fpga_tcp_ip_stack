#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
rd(){ echo "W6=$(reg 0x38) W7=$(reg 0x3C) W16=$(reg 0x60) W17=$(reg 0x64) W18=$(reg 0x68) W51=$(reg 0xEC) W52=$(reg 0xF0) W59=$(reg 0x10C) W60=$(reg 0x110)"; }
mk(){ ip netns exec nsa timeout 60 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 --maxbytes "$1" --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin 2>&1; }
pair(){ mk 16777216 > $P/pi_a.txt & mk 16777216 > $P/pi_b.txt & wait; echo "PAIR A=$(grep -oE 'conn_ms=[0-9.]+' $P/pi_a.txt|tail -1) B=$(grep -oE 'conn_ms=[0-9.]+' $P/pi_b.txt|tail -1)"; }
snap; echo "T0 $(rd)"
echo "--- baseline pair ---"; pair; snap; echo "AFTER_BASE $(rd)"
echo "--- induce: 8 simultaneous 256MB ---"
for i in 0 1 2 3 4 5 6 7; do mk 268435456 > $P/ind_$i.txt & done
wait
snap; echo "AFTER_IND $(rd)"
for i in 0 1 2 3 4 5 6 7; do echo "IND$i $(grep -oE 'conn_ms=[0-9.]+|bytes=[0-9]+' $P/ind_$i.txt | tr '\n' ' ')"; done
echo "--- pair after induction (x2) ---"; pair; snap; echo "AFTER_P1 $(rd)"; sleep 1; pair; snap; echo "AFTER_P2 $(rd)"
