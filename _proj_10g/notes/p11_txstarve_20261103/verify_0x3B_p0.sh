#!/bin/bash
# verify_0x3B_p0.sh -- 0x3B DIAG3B 打 .2（ch1/J8, u_app_ctrl + app_multi8 所在口）
#   W51=0xEC ready[15:0]; W52=0xF0 {ev_cnt,estab_cnt}; W53=0xF4 init_ovf
#   与 verify_0x3B.sh 的唯一差异：sink 在 nsa 里打 192.168.100.2。
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
rd(){ echo "W51=$(reg 0xEC) W52=$(reg 0xF0) W53=$(reg 0xF4) W97=$(reg 0x1A4) W6=$(reg 0x38) W7=$(reg 0x3C) W18=$(reg 0x68)"; }
echo "=== ENV ==="
pkill -x tcpdump 2>/dev/null; sleep 1
bash /tmp/env_setup_robust.sh >/tmp/v3bp0_env.log 2>&1
grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/v3bp0_env.log | tail -4
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$(reg 0x04)"
snap; echo "T0 $(rd)"
echo "=== START 8 staggered sinks to .2 (nsa, 0.5s) ==="
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 4294967296 --seconds 8 --check seq > /tmp/v3bp0_$i.txt 2>&1 &
  sleep 0.5
  if [ "$i" = "3" ] || [ "$i" = "7" ]; then snap; echo "T_at_P$i $(rd)"; fi
done
wait
snap; echo "T_end $(rd)"
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_SUM' /tmp/v3bp0_$i.txt | tail -1)"
done
