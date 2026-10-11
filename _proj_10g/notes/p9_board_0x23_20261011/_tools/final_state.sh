#!/bin/bash
# final_state.sh -- P9 0x23 收尾: 板上留 **0x23** + 受控停流 (0x08 = 0x2) + MIR_CTRL=0
#   + 最终态读数 + 残留进程 + /tmp/p7b_biz 复读 (证明全程未动) + 对端改动台账
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x23_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/FINAL_STATE_0x23.txt") 2>&1
echo "=== FINAL_STATE_BEGIN $(date +%s.%N)"
echo "--- 停流前: NIC 收速率 (2 s 窗) + carrier ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- 写 0x08 = 0x2 (受控停流) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
echo "--- 写 MIR_CTRL = 0 (采集口回冻结默认态; bit1=0 ⇒ 无 clr 脉冲) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x144 w 0x0 2>&1 | tail -1"
sleep 4
echo "--- 停流后: NIC 收速率 (2 s 窗) + carrier + link ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'LINK='; ethtool enp1s0f1np1 | grep -o 'Link detected: .*'"
echo "--- 最终态寄存器 ---"
$SSH --sudo 'T='$T'; \
  echo -n "MAGIC_0x00="; $T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n "BID_0x04=";   $T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n "SCRATCH_0x08="; $T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n "MIR_STATUS_0x13C="; $T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n "MIR_CTRL_0x144="; $T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n "MIR_DMA_CNT_0x148="; $T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1; \
  echo -n "UNIMPL_0x14C="; $T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1'
echo "--- 最终态快照 (触发式; W5/W11/W13/W70) ---"
$SSH --sudo "cd /tmp/p9_board_0x23 && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap final 5 11 13 70 2>&1 | tail -7"
echo "--- 残留进程 (对端) ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump|dma_from' | grep -v grep; echo PROC_SCAN_DONE"
echo "--- /tmp/p7b_biz 复读 (全程未动; 期望 = 开工时 md5: a3faafd3…/ba2faf79…/b2f2e962…/b0322279…) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h"
echo "--- 历史目录只读核对 (未动) ---"
$SSH "md5sum /tmp/p8_board_0x21/p7b_mir_dump /tmp/p8_board_0x21/p7b_udp_src /tmp/p9_board_0x22/p7b_mir_dump /tmp/p9_board_0x22/p7b_udp_src 2>/dev/null"
echo "--- 对端改动台账 (全部可回退) ---"
$SSH "echo '1) 新增目录 /tmp/p9_board_0x23/ (本轮部署+现编+抓样+日志+tail_S5.bin); 回退 = rm -rf /tmp/p9_board_0x23'; \
  echo '2) 设备级 remove+rescan ×3 (0x23 首烧 / 0x21 对照臂 / 0x23 烧回); 状态 = 生效中'; \
  echo '3) 本轮新增 /tmp/p9_board_0x23/{mir_*.bin,mir_*.log,src_*.log,tail_S5.bin,drain?}; 随 1) 一起回退'; \
  echo -n '4) sysctl/qdisc/coalesce/nmcli 未动: '; tc qdisc show dev enp1s0f1np1 | head -2; \
  ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | head -3; \
  echo -n '5) 网络面: '; ip -4 addr show enp1s0f1np1 | grep inet; nmcli -g GENERAL.STATE device show enp1s0f1np1"
echo "--- dmesg 尾部 (本轮是否有新报错; 上一条已知 = P2B 首跑的 read#2 超时) ---"
$SSH --sudo "dmesg 2>/dev/null | tail -6"
echo "=== FINAL_STATE_END $(date +%s.%N)"
