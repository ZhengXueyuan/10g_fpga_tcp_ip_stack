#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-pathed/XDMA/linux-kernel/tools
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
rd(){ echo "W6=$(reg 0x38) W7=$(reg 0x3C) W16=$(reg 0x60) W17=$(reg 0x64) W18=$(reg 0x68) W51=$(reg 0xEC) W52=$(reg 0xF0)"; }
mk(){ ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 --maxbytes 16777216 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin 2>&1; }
snap; echo "T0 $(rd)"
mk > $P/sc1.txt; snap; echo "AFTER1 $(rd)"
mk > $P/sc2.txt; snap; echo "AFTER2 $(rd)"
