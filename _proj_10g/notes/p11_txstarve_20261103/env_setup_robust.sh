#!/bin/bash
# env_setup_robust.sh -- 0x36/0x38 board env with netns-move retries (2026-11-03).
set -u
I1=enp1s0f1np1
I0=enp1s0f0np0
pkill -x tcpdump 2>/dev/null
sleep 1
nmcli device set $I1 managed no 2>&1 | sed 's/^/NM: /'
nmcli device set $I0 managed no 2>&1 | sed 's/^/NM: /'
ip link set $I1 down 2>/dev/null
ip link set $I0 down 2>/dev/null
ip netns delete nsa 2>/dev/null; ip netns delete nsb 2>/dev/null
sleep 1
ip netns add nsa; ip netns add nsb
# retry the moves: physical interfaces may return from a deleted netns asynchronously
for try in 1 2 3; do
  ip link set $I1 netns nsa 2>/dev/null && break
  sleep 1
done
echo "MOVE_${I1}_RC=$?"
for try in 1 2 3; do
  ip link set $I0 netns nsb 2>/dev/null && break
  sleep 1
done
echo "MOVE_${I0}_RC=$?"
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
sleep 3
ip netns exec nsa ip neigh del 192.168.100.2 dev $I1 2>/dev/null
ip netns exec nsb ip neigh del 192.168.100.4 dev $I0 2>/dev/null
ip netns exec nsa ping -c 2 -W 1 -I $I1 192.168.100.2 2>&1 | tail -3
ip netns exec nsb ping -c 2 -W 1 -I $I0 192.168.100.4 2>&1 | tail -3
ip -n nsa neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I1
ip -n nsb neigh replace 192.168.100.2 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I0
echo -n "NSA_CARRIER="; ip netns exec nsa cat /sys/class/net/$I1/carrier 2>&1
echo -n "NSB_CARRIER="; ip netns exec nsb cat /sys/class/net/$I0/carrier 2>&1
echo -n "NSB_SPEED="; ip netns exec nsb cat /sys/class/net/$I0/speed 2>&1
