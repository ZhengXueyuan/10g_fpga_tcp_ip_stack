#!/bin/bash
# verify_0x39.sh -- read per-slot app_tx_ready / init counters on 0x39.
#   W98=0x1A8 ready0, W99=0x1AC ready1, W100=0x1B0 {ev_cnt,estab_cnt},
#   W101=0x1B4 init_ovf, W102=0x1B8 init_mism, W97=0x1A4 health.
#   Scenario: 8 single-conn sinks started 0.5 s apart (fresh burn); snapshots during.
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
rd(){ echo "W98=$(reg 0x1A8) W99=$(reg 0x1AC) W100=$(reg 0x1B0) W101=$(reg 0x1B4) W102=$(reg 0x1B8) W97=$(reg 0x1A4) W6=$(reg 0x38) W7=$(reg 0x3C) W18=$(reg 0x68)"; }
echo "=== ENV ==="
pkill -x tcpdump 2>/dev/null; sleep 1
bash /tmp/env_setup_robust.sh >/tmp/v39_env.log 2>&1
grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/v39_env.log | tail -4
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
snap; echo "T0 $(rd)"
echo "=== START 8 staggered sinks (0.5s) ==="
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsb timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.4 --port 8080 --conns 1 \
      --maxbytes 4294967296 --seconds 8 --check seq > /tmp/v39_$i.txt 2>&1 &
  sleep 0.5
  if [ "$i" = "3" ] || [ "$i" = "7" ]; then snap; echo "T_at_P$i $(rd)"; fi
done
wait
snap; echo "T_end $(rd)"
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_SUM' /tmp/v39_$i.txt | tail -1)"
done
