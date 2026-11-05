#!/bin/bash
# degraded_full_window.sh -- 退化态全计数器窗 (触发快照), 单项 connect 前后对比
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
rd(){ echo "W0=$(reg 0x20) W1=$(reg 0x24) W2=$(reg 0x28) W3=$(reg 0x2C) W4=$(reg 0x30) W5=$(reg 0x34) W6=$(reg 0x38) W7=$(reg 0x3C) W16=$(reg 0x60) W17=$(reg 0x64) W18=$(reg 0x68) W19=$(reg 0x6C) W20=$(reg 0x70) W22=$(reg 0x78) W24=$(reg 0x80) W26=$(reg 0x88) W32=$(reg 0xA0) W33=$(reg 0xA4) W34=$(reg 0xA8) W35=$(reg 0xAC) W38=$(reg 0xB8) W45=$(reg 0xD4) W46=$(reg 0xD8) W47=$(reg 0xDC) W48=$(reg 0xE0) W49=$(reg 0xE4) W52=$(reg 0xF0) W59=$(reg 0x10C) W60=$(reg 0x110) W83=$(reg 0x16C) W84=$(reg 0x170)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
snap; echo "PRE  $(rd)" | tee $P/fw_pre.txt
ip netns exec nsa timeout 20 $B/p7b_tcp_sink --host 192.168.100.2 --port 8080 --conns 1 --maxbytes 16777216 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin > $P/fw_sink.txt 2>&1
grep -hE 'SINK_CONN' $P/fw_sink.txt
snap; echo "POST $(rd)" | tee $P/fw_post.txt
