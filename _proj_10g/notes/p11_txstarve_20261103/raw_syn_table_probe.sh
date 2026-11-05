#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$($T/reg_rw /dev/xdma0_user 0x04 w 2>/dev/null | tail -1 | sed 's/.*: *//')"
ip netns exec nsa python3 /tmp/raw_syn_table_probe.py 8
