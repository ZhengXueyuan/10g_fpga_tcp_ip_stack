#!/bin/bash
# b0_env_setup_0x36.sh -- 0x36 (P11 APP8 CDC) board round environment (same netns recipe as P2 0x2D §3.1).
#   nsa: p1 enp1s0f1np1 = 192.168.100.1/32  <-> IP_A 192.168.100.2 (J8/ch1)
#   nsb: p0 enp1s0f0np0 = 192.168.100.101/32 <-> IP_B 192.168.100.4 (J7/ch0)
#   Real ARP first (remove static neigh -> ping -> let both sides learn), then re-add
#   permanent neigh for the wrong-port negative controls.
set -u
I1=enp1s0f1np1
I0=enp1s0f0np0
S=/tmp/p7b_snap.sh
echo "=== ENV_SETUP_BEGIN $(date +%s.%N) $(date)"
nmcli device set $I1 managed no 2>&1 | sed 's/^/NM: /'
nmcli device set $I0 managed no 2>&1 | sed 's/^/NM: /'
ip link set $I1 down 2>&1
ip link set $I0 down 2>&1
ip netns delete nsa 2>/dev/null; ip netns delete nsb 2>/dev/null
ip netns add nsa; ip netns add nsb
ip link set $I1 netns nsa; echo "MOVE_${I1}_RC=$?"
ip link set $I0 netns nsb; echo "MOVE_${I0}_RC=$?"
ip -n nsa addr add 192.168.100.1/32 dev $I1
ip -n nsb addr add 192.168.100.101/32 dev $I0
ip -n nsa link set $I1 up
ip -n nsb link set $I0 up
ip -n nsa route add 192.168.100.2/32 dev $I1
ip -n nsb route add 192.168.100.4/32 dev $I0
ip netns exec nsa sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.$I1.rp_filter=0 net.ipv4.conf.$I1.arp_ignore=1 net.ipv4.conf.$I1.arp_announce=2
ip netns exec nsb sysctl -qw net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.$I0.rp_filter=0 net.ipv4.conf.$I0.arp_ignore=1 net.ipv4.conf.$I0.arp_announce=2
ip netns exec nsa ethtool -C $I1 adaptive-rx off rx-usecs 0 2>&1 | sed 's/^/ETHTOOL_A: /'
ip netns exec nsb ethtool -C $I0 adaptive-rx off rx-usecs 0 2>&1 | sed 's/^/ETHTOOL_B: /'
sleep 4

echo "--- real ARP priming (no static neigh) ---"
ip netns exec nsa ip neigh del 192.168.100.2 dev $I1 2>/dev/null
ip netns exec nsb ip neigh del 192.168.100.4 dev $I0 2>/dev/null
ip netns exec nsa ping -c 2 -W 1 -I $I1 192.168.100.2 2>&1 | tail -4
ip netns exec nsb ping -c 2 -W 1 -I $I0 192.168.100.4 2>&1 | tail -4

echo "--- static neighbours for wrong-port controls (board MAC) ---"
ip -n nsa neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I1
ip -n nsb neigh replace 192.168.100.2 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I0

echo "--- nsa ---"
ip netns exec nsa ip -br addr show
ip netns exec nsa ip route show
ip netns exec nsa ip neigh show
echo -n "NSA_CARRIER="; ip netns exec nsa cat /sys/class/net/$I1/carrier 2>&1
echo -n "NSA_SPEED="; ip netns exec nsa cat /sys/class/net/$I1/speed 2>&1
echo "--- nsb ---"
ip netns exec nsb ip -br addr show
ip netns exec nsb ip route show
ip netns exec nsb ip neigh show
echo -n "NSB_CARRIER="; ip netns exec nsb cat /sys/class/net/$I0/carrier 2>&1
echo -n "NSB_SPEED="; ip netns exec nsb cat /sys/class/net/$I0/speed 2>&1
echo "--- board identity (0x36: NW=98 BID=0x36 UNIMPL=0x1B8) ---"
NW=98 EXPECT_BID=0x00000036 UNIMPL_ADDR=0x1B8 bash $S id; echo ID_RC=$?
echo "=== ENV_SETUP_END $(date +%s.%N)"
