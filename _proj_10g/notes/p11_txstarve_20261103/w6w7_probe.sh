#!/bin/bash
# w6w7_probe.sh -- zero-build discriminator: did the HLS produce SYN-ACKs at all?
#   W6=0x38 (frames into slow path) W7=0x3C (slow_tx_adp frames) W16=0x60 (HLS bytes read)
#   W17=0x64 (HLS reset/starve) W18=0x68 (slow_tx_adp purge) W20=0x70 (MAC TX frames)
#   W59=0x10C (slow_tx_adp FIFO write rejects) W97=0x1A4 (health)
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.6; }
rd(){ echo "W6=$(reg 0x38) W7=$(reg 0x3C) W16=$(reg 0x60) W17=$(reg 0x64) W18=$(reg 0x68) W20=$(reg 0x70) W59=$(reg 0x10C) W97=$(reg 0x1A4)"; }
echo "=== ENV ==="; bash /tmp/b0_env_setup_0x36.sh >/tmp/w67_env.log 2>&1; grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/w67_env.log | tail -4
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
snap; echo "T0 $(rd)"
ip netns exec nsb "$B/p7b_tcp_sink_multi" --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 4294967296 --seconds 10 --check seq > /tmp/w67_run.txt 2>&1 &
FP=$!
sleep 2
snap; echo "T1 $(rd)"
wait $FP
snap; echo "T2 $(rd)"
echo "=== CONNS ==="; grep -E 'MULTI_CONN|MULTI_SUM' /tmp/w67_run.txt
