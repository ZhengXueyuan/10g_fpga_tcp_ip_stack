#!/bin/bash
# final_state.sh -- P9 收尾轮收尾: 板上留 0x23 + 受控停流 (0x08=0x2) + MIR_CTRL=0
#   + 撤临时 fq + 最终态读数 + 残留进程 + /tmp/p7b_biz 复读 + 对端改动台账
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/FINAL_STATE_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== FINAL_STATE_BEGIN $(date +%s.%N)"
echo "--- ① 停流前: NIC 收速率 (2 s 窗) + carrier ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- ② 写 0x08 = 0x2 (受控停流) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
echo "--- ③ 写 MIR_CTRL = 0 (cap_en=0 / clr 电平 0 / src_sel=0 / dma_en=0) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x144 w 0x0 2>&1 | tail -1"
echo "--- ④ 撤临时 fq 根 qdisc (回 mq) ---"
$SSH --sudo "tc qdisc del dev enp1s0f1np1 root 2>&1; tc qdisc show dev enp1s0f1np1 | head -3"
sleep 4
echo "--- ⑤ 停流后: NIC 速率 (2 s 窗) + carrier + link ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'LINK='; ethtool enp1s0f1np1 | grep -o 'Link detected: .*'"
echo "--- ⑥ 最终态寄存器 ---"
$SSH --sudo "T=$T; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1"
echo "--- ⑦ 最终态快照 (触发式) ---"
$SSH --sudo "cd /tmp/p9_final && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap final 53 54 70 11 13 5 43 20 2>&1 | tail -11"
echo "--- ⑧ 残留进程 (对端) ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump|dma_from|dma_to' | grep -v grep; echo PROC_SCAN_DONE"
echo "--- ⑨ /tmp/p7b_biz 复读 (全程未动; 开工基线 = a3faafd3…/ba2faf79…/b2f2e962…/b0322279…) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h"
echo "--- ⑩ 历史目录只读核对 (未动) ---"
$SSH "md5sum /tmp/p9_board_0x23/p7b_mir_dump /tmp/p9_board_0x23/p7b_udp_src /tmp/p9_board_0x23/p7b_snap.sh /tmp/p8_tcp_0x21/p7b_mir_dump /tmp/p8_tcp_0x21/p7b_tcp_src 2>/dev/null"
echo "--- ⑪ 对端改动台账 (全部可回退) ---"
$SSH "echo '1) 新增目录 /tmp/p9_final/ (本轮部署: 工具只读拷贝 + t1/t2 远端脚本 + h2c_*.bin + mir_*/src_*/ss_* 日志与抓样); 回退 = rm -rf /tmp/p9_final'; \
  echo '2) 板上 0x08: 0x2 → 0x0 (T2 恢复 carrier; 02:09 段) → 已写回 0x2 (本步 ②)'; \
  echo '3) 板上 MIR_CTRL (0x144): 被 t2 工具 arm/收尾若干次 → 已写回 0x0 (本步 ③)'; \
  echo '4) 临时 fq 根 qdisc (T2 pacing 前置) → 已撤 (本步 ④)'; \
  echo -n '5) sysctl/nmcli/coalesce 未动: '; nmcli -g GENERAL.STATE device show enp1s0f1np1; \
  ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | head -3; \
  echo -n '6) 网络面: '; ip -4 addr show enp1s0f1np1 | grep inet"
echo "--- ⑫ dmesg 尾部 (本轮是否有新报错; T1 三档 0 新行) ---"
$SSH --sudo "dmesg | wc -l; dmesg | tail -8"
echo "=== FINAL_STATE_END $(date +%s.%N)"
