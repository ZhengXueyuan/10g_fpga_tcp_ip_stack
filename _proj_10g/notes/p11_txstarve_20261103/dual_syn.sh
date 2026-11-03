#!/bin/bash
# dual_syn.sh -- flood .4 (port0/J7) and capture SYN-ACKs on BOTH peer NICs.
#   If >1 SYN-ACK appears on nsa (port1/J8), the slow path is misrouting by port.
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
rm -f /tmp/syn_nsb.pcap /tmp/syn_nsa.pcap /tmp/dual_run.txt
ip netns exec nsb timeout 25 tcpdump -i any -nn -s 80 -w /tmp/syn_nsb.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' >/dev/null 2>&1 &
P1=$!
ip netns exec nsa timeout 25 tcpdump -i any -nn -s 80 -w /tmp/syn_nsa.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' >/dev/null 2>&1 &
P2=$!
sleep 1.5
ip netns exec nsb timeout 30 $B/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 4294967296 --seconds 10 --check seq > /tmp/dual_run.txt 2>&1
sleep 1; kill $P1 $P2 2>/dev/null; sleep 0.5
echo "=== CONNS ==="; grep -E 'MULTI_CONN|MULTI_SUM' /tmp/dual_run.txt
echo "=== NSB (port0/.4) ==="
echo "SYN_OUT=$(tcpdump -nn -r /tmp/syn_nsb.pcap 2>/dev/null | grep -c 'Out IP 192.168.100.101.*Flags \[S\]')"
echo "SYNACK_IN=$(tcpdump -nn -r /tmp/syn_nsb.pcap 2>/dev/null | grep -c 'In  IP 192.168.100.4.*Flags \[S.\]')"
tcpdump -nn -r /tmp/syn_nsb.pcap 2>/dev/null | awk '$3=="In"{print $5,$7}' | sort | uniq -c | head -12
echo "=== NSA (port1/.2) ==="
echo "SYNACK_ANY=$(tcpdump -nn -r /tmp/syn_nsa.pcap 2>/dev/null | grep -c 'Flags \[S.\]')"
echo "SYN_ANY=$(tcpdump -nn -r /tmp/syn_nsa.pcap 2>/dev/null | grep -c 'Flags \[S\]')"
tcpdump -nn -r /tmp/syn_nsa.pcap 2>/dev/null | head -20
