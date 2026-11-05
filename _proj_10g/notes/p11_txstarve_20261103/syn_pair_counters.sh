#!/bin/bash
# syn_pair_counters.sh -- 双 SYN 同发时，0.5s（重传前）读慢路径计数，定位丢在哪一段
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
rd(){ echo "W6=$(reg 0x38) W7=$(reg 0x3C) W16=$(reg 0x60) W17=$(reg 0x64) W18=$(reg 0x68) W45=$(reg 0xD4) W46=$(reg 0xD8) W47=$(reg 0xDC) W48=$(reg 0xE0) W49=$(reg 0xE4) W59=$(reg 0x10C) W60=$(reg 0x110)"; }
mk(){ ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 16777216 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin 2>&1; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "WARMUP $(mk > $P/cw_warm.txt; grep -oE 'conn_ms=[0-9.]+' $P/cw_warm.txt | tail -1)"
sleep 1
for r in 1 2 3; do
  B0=$(rd); echo "R$r BASE $B0"
  mk > $P/cw_${r}a.txt & mk > $P/cw_${r}b.txt &
  sleep 0.5
  echo "R$r MID  $(rd)"
  wait
  echo "R$r END  $(rd)"
  echo "R$r A=$(grep -oE 'conn_ms=[0-9.]+' $P/cw_${r}a.txt | tail -1) B=$(grep -oE 'conn_ms=[0-9.]+' $P/cw_${r}b.txt | tail -1)"
  sleep 1
done
