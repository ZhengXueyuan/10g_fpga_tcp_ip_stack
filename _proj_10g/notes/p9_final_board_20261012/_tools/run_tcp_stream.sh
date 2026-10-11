#!/bin/bash
# run_tcp_stream.sh -- T2: AXIS (--stream) 上的 TCP 源臂 (src_sel=1)
#   步骤: ① 部署 (只读拷贝冻结工具到 /tmp/p9_final, md5 双核) ② 恢复 carrier (0x08=0)
#         ③ 临时 fq 根 qdisc (SO_MAX_PACING_RATE 生效前置; 与 p8 TCP 轮同手法) ④ 逐跑
#   判据 (读数, 不下 PASS/FAIL): ΔW70 / 式A / 式B / pc / taken / level_end / premise_level0 / 内容逐字节
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
OUT_W=D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_final_board_20261012
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/tmp/p9_final
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }

LOG=$OUT/runs/T2_TCPSTREAM_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== T2_DEPLOY $(date +%s.%N)"
$SSH "cd $D && cp /tmp/p9_board_0x23/p7b_mir_dump ./ && cp /tmp/p8_tcp_0x21/p7b_tcp_src ./ \
   && cp /tmp/p9_board_0x23/p7b_pattern.h ./ && cp /tmp/p9_board_0x23/p7b_affinity.h ./ \
   && md5sum p7b_mir_dump p7b_tcp_src p7b_pattern.h p7b_affinity.h p7b_snap.sh \
   && echo '--- 源件对照 (只读) ---' && md5sum /tmp/p9_board_0x23/p7b_mir_dump /tmp/p8_tcp_0x21/p7b_tcp_src \
   && ls -la"
echo "--- put t2_remote_step.sh ---"
$SSH --put "$OUT_W/_tools/t2_remote_step.sh" "$D/t2_remote_step.sh"
$SSH "md5sum $D/t2_remote_step.sh"

echo ""
echo "=== T2_CARRIER / fq $(date +%s.%N)"
$SSH "echo -n 'PRE_CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; tc qdisc show dev enp1s0f1np1 | head -3; ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | head -3"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x0 2>&1 | tail -1"
sleep 3
$SSH "echo -n 'POST_CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ethtool enp1s0f1np1 | grep -E 'Link detected'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'"
echo "--- 临时 fq (pacing 前置; 收尾撤销) ---"
$SSH --sudo "tc qdisc replace dev enp1s0f1np1 root fq && tc qdisc show dev enp1s0f1np1 | head -3"

echo ""
echo "############ T2A K=1048576 (r1) ############"
$SSH --sudo "K=1048576 PACE=2500000 TAG=T2A SECS=40 bash $D/t2_remote_step.sh"

echo ""
echo "############ T2B K=1048576 (r2 重复) ############"
$SSH --sudo "K=1048576 PACE=2500000 TAG=T2B SECS=40 bash $D/t2_remote_step.sh"

echo ""
echo "############ T2C K=262144 + 残拍见证 (k-bytes=SRC=262152) ############"
$SSH --sudo "K=262144 KBYTES=262152 SRC_BYTES=262152 PACE=2500000 TAG=T2C SECS=40 bash $D/t2_remote_step.sh"

echo ""
echo "=== T2_DONE $(date +%s.%N)"
