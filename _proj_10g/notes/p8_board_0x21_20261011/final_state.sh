#!/bin/bash
# final_state.sh -- P8 板级 A/B 轮 (0x21) 收尾: 受控停流 (0x08 = 0x2 ⇒ carrier = 0) + MIR_CTRL=0
#   + 最终态读数 + 残留进程 (对端) + /tmp/p7b_biz 复读 (证明全程未动)
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_board_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/FINAL_STATE_0x21.txt") 2>&1
echo "=== FINAL_STATE_BEGIN $(date +%s.%N)"
echo "--- 停流前: NIC 收速率 (2 s 窗) + carrier ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- 写 0x08 = 0x2 (受控停流) ---"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
echo "--- 写 MIR_CTRL = 0 (采集口回冻结默认态: cap_en=0 / dma_en=0) ---"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \$T/reg_rw /dev/xdma0_user 0x144 w 0x0 2>&1 | tail -1"
sleep 4
echo "--- 停流后: NIC 收速率 (2 s 窗) + carrier + 最终态寄存器 ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'LINK_DETECTED='; ethtool enp1s0f1np1 | grep -o 'Link detected: .*'"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1"
echo "--- 最终态快照 (触发式; W5/W11/W13/W70) ---"
$SSH --sudo "cd /tmp/p8_board_0x21 && NW=71 EXPECT_BID=0x00000021 bash ./p7b_snap.sh snap final 5 11 13 70 2>&1 | tail -7"
echo "--- 残留进程 (对端) ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE"
echo "--- /tmp/p7b_biz 复读 (全程未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h"
echo "--- /tmp/p8_board 与 /tmp/p8_board_0x20 复读 (只读核对) ---"
$SSH "md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_udp_src /tmp/p8_board_0x20/p7b_mir_dump /tmp/p8_board_0x20/p7b_udp_src /tmp/p8_board_0x20/run_arm.sh"
echo "=== FINAL_STATE_END $(date +%s.%N)"
