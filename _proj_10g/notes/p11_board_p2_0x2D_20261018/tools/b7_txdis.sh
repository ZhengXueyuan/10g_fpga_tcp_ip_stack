#!/bin/bash
# b7_txdis.sh -- P11 P2 B-7 single-port TX_DIS isolation, judged by PEER carrier/NIC (not W83/W84)
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
TAG=${1:-B7}
car(){ ip netns exec $1 cat /sys/class/net/$2/carrier 2>&1; }
chg(){ ip netns exec $1 cat /sys/class/net/$2/carrier_changes 2>&1; }
nrx(){ ip netns exec $1 ethtool -S $2 2>/dev/null | awk '/port_rx_packets:/{print $2}'; }
state(){ echo "STATE t=$(date +%s.%N) 0x08=$( $T/reg_rw $D 0x08 w 2>/dev/null | tail -1 | sed 's/.*: *//') p1(car=$(car nsa $I1) chg=$(chg nsa $I1) rxpk=$(nrx nsa $I1)) p0(car=$(car nsb $I0) chg=$(chg nsb $I0) rxpk=$(nrx nsb $I0))"; }
echo "=== B7_BEGIN tag=$TAG $(date +%s.%N) $(date)"
$T/reg_rw $D 0x08 w 0x0 >/dev/null 2>&1
state
echo "--- SET bit0=1 (sfp1_tx_dis = J7/ch0) ---"
$T/reg_rw $D 0x08 w 0x1 >/dev/null 2>&1
sleep 5; state
sleep 3; state
echo "--- RESTORE 0x0 ---"
$T/reg_rw $D 0x08 w 0x0 >/dev/null 2>&1
sleep 6; state
echo "--- SET bit1=1 (sfp2_tx_dis = J8/ch1) ---"
$T/reg_rw $D 0x08 w 0x2 >/dev/null 2>&1
sleep 5; state
sleep 3; state
echo "--- RESTORE 0x0 ---"
$T/reg_rw $D 0x08 w 0x0 >/dev/null 2>&1
sleep 6; state
echo "=== B7_END tag=$TAG $(date +%s.%N)"
