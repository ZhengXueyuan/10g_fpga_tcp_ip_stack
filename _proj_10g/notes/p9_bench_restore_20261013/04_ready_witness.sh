#!/bin/bash
# 04_ready_witness.sh -- 就绪态见证 (只读 + 快照触发; ⛔ 不写 0x08 / 不发业务流量)
#   ① pair 模式快照 ×3 (W5/W24/W43): 两点各自自证 gen+1 ⇒ 设计真的在走时钟
#   ② NIC 2 s 窗计数 (板应静止: 无自流)
#   ③ 最终寄存器 + 残留进程 + /tmp/p7b_biz 复读 + 环境台账
#   ④ p7b_selftest.sh (板外, 30 判据)
#   用法: PEER_PW=<pw> bash 04_ready_witness.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_bench_restore_20261013
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/04_ready_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== READY_BEGIN $(date +%s.%N) $(date)"
echo "--- ① 快照活体见证 (pair; 两点各自 gen+1) ---"
$SSH --sudo "cd /tmp/p7b_biz && for w in 5 24 43; do NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh pair \$w 2 LIVE_W\$w; done"
echo "--- ①b 一次 snap (W5 W20 W24 W43 W11 W13 W70; 板应静止: W20 不涨) ---"
$SSH --sudo "cd /tmp/p7b_biz && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap ready 5 20 24 43 11 13 70"

echo "--- ② NIC 2 s 窗计数 (板静止 ⇒ Δ 应 ~0) ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets|port_tx_bytes'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets|port_tx_bytes'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'OPERSTATE='; cat /sys/class/net/enp1s0f1np1/operstate; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'"

echo "--- ③ 最终寄存器 (全量身份面) ---"
$SSH --sudo "T=$T; for a in 0x00 0x04 0x08 0x0C 0x14 0x13C 0x144 0x148 0x14C; do printf 'user %s=' \$a; \$T/reg_rw /dev/xdma0_user \$a w 2>&1 | tail -1; done"

echo "--- ③b 残留进程 ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump|dma_from' | grep -v grep; echo PROC_SCAN_DONE"

echo "--- ③c /tmp/p7b_biz 复读 (部署件完整性) ---"
$SSH "cd /tmp/p7b_biz && md5sum p7b_affinity.h p7b_pattern.h p7b_snap.sh p7b_mir_dump p7b_tcp_sink p7b_udp_src p7b_io.h p7b_spsc.h; ls | wc -l"

echo "--- ③d 环境台账 (可回退项) ---"
$SSH "echo -n '1) nmcli: '; nmcli -g GENERAL.STATE device show enp1s0f1np1; echo -n '2) ip: '; ip -4 addr show enp1s0f1np1 | grep inet; echo -n '3) route: '; ip route show | grep 192.168.100; echo '4) coalesce:'; ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:'; echo -n '5) tc qdisc: '; tc qdisc show dev enp1s0f1np1 | head -1; echo -n '6) irqbalance: '; systemctl is-active irqbalance; echo -n '7) xdma: '; lsmod | grep -w xdma; echo -n '8) CLK kernel: '; uname -r"

echo "--- ④ p7b_selftest.sh (板外, 30 判据) ---"
$SSH "cd /tmp/p7b_biz && bash p7b_selftest.sh 18899 2>&1 | tail -6"
echo "=== READY_END $(date +%s.%N)"
