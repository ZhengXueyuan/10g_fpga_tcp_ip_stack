#!/bin/bash
# raw_probe_table.sh -- 卸载态直接测 HLS 空闲槽数：N 个原始 SYN（抑制 RST），看 W7 增量（SYN-ACK 数）。
#   用法: bash raw_probe_table.sh [N] [base_sport]
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
N=${1:-8}; BASE=${2:-41000}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
BID=$(reg 0x04); echo "BID=$BID"
ip netns exec nsa ip link set enp1s0f1np1 promisc on 2>/dev/null
ip netns exec nsa iptables -I OUTPUT -p tcp --tcp-flags RST RST -d 192.168.100.2 -j DROP
echo "IPT_RC=$? RULE_CHECK=$(ip netns exec nsa iptables -C OUTPUT -p tcp --tcp-flags RST RST -d 192.168.100.2 -j DROP; echo $?)"
snap; W7PRE=$(reg 0x3C); W52PRE=$(reg 0xF0); W6PRE=$(reg 0x38)
ip netns exec nsa python3 /tmp/raw_syn_burst.py "$N" "$BASE"
sleep 0.5
snap; W7POST=$(reg 0x3C); W52POST=$(reg 0xF0); W6POST=$(reg 0x38)
ip netns exec nsa iptables -D OUTPUT -p tcp --tcp-flags RST RST -d 192.168.100.2 -j DROP
echo "W6_PRE=$W6PRE W6_POST=$W6POST"
echo "W7_PRE=$W7PRE W7_POST=$W7POST"
echo "W52_PRE=$W52PRE W52_POST=$W52POST"
