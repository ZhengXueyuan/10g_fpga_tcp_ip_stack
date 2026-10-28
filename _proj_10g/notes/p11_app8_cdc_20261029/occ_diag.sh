#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9; }
kill_sinks; sleep 0.5
echo "SINKS_LEFT=$(ps -eo args | grep -c '[p]7b_tcp_sink_multi')"
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 2
$T/reg_rw $D 0x08 w 0x4 >/dev/null
echo STALL_SET
cd /tmp/p7b_biz
rm -f /tmp/occ_diag.txt
( ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 \
    --maxbytes 4294967296 --seconds 15 --check seq --send-conns 1 --send-bytes 16384 \
    > /tmp/occ_diag.txt 2>&1 & )
sleep 1.5
echo "SINK_ALIVE=$(ps -eo args | grep -c '[p]7b_tcp_sink_multi')"
echo "SINK_HEAD:"; head -4 /tmp/occ_diag.txt
for K in 1 2; do
  $T/reg_rw $D 0x18 w 0x1 >/dev/null; sleep 0.05
  printf 'K%s_W62=' $K; $T/reg_rw $D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'
  printf 'K%s_W97=' $K; $T/reg_rw $D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'
  sleep 0.7
done
rm -f /tmp/occ_diag.pcap
ip netns exec nsb timeout 2 tcpdump -i any -nn -s 96 -w /tmp/occ_diag.pcap 'tcp and src host 192.168.100.4' 2>/tmp/tcpd_err.txt
ls -l /tmp/occ_diag.pcap; tail -2 /tmp/tcpd_err.txt
python3 /tmp/occ_win.py /tmp/occ_diag.pcap 8
$T/reg_rw $D 0x08 w 0x0 >/dev/null
kill_sinks || true
echo SINK_TAIL:; tail -4 /tmp/occ_diag.txt
echo DIAG_END
