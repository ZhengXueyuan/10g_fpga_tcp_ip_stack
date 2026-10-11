#!/bin/bash
# step0.sh -- P9 收尾板级轮 (0x23 补两格 PCIe 面) 只读自检
#   判据: ① 归档位流 sha256 双核 (本轮**不烧**) ② 对端连通 ③ 无残留进程
#         ④ 板上身份五判据 (0x04=0x23 / 71 字窗口无 0xffffffff / 0x14C 回 ffffffff / LnkSta x4 / 2 BARs)
#         ⑤ 现态读数 (0x08 / MIR_CTRL / MIR_STATUS / MIR_DMA_CNT / W53 W54 W70 W11 W13 W5)
#         ⑥ dmesg 尾部基线 (与 T1 对照用)
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }

LOG=$OUT/runs/STEP0_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== STEP0_BEGIN $(date +%s.%N)"
echo "--- ① 归档位流 sha256 (本轮不烧; 期望 066a3923…3126) ---"
B=$ROOT/_proj_10g/notes/p9_build_0x23/wrapper_p4.bit
ls -la "$B"
sha256sum "$B"
echo "--- (副本目录 p9_board_0x23/burn) ---"
sha256sum $ROOT/_proj_10g/notes/p9_board_0x23_20261011/burn/wrapper_p4_0x23.bit 2>&1

echo "--- ② 对端连通 + 本机/对端时钟 ---"
$SSH "date +%s.%N; uptime | head -1" || { echo "FATAL: 对端不可达"; exit 3; }

echo "--- ③ 残留进程 ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump|dma_from|dma_to' | grep -v grep; echo PROC_SCAN_DONE"

echo "--- ④ 板上身份五判据 (现读) ---"
$SSH --sudo "T=$T; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
echo "--- 71 字窗口逐字扫 (0x20..0x138; 期望 0 个 ffffffff) ---"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 70); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"
echo "--- 几何 71 字: 0x20+4*71 = 0x13C = MIR_STATUS (窗口内最后一字) ---"
echo "--- PCIe 面 ---"
$SSH "lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'"
$SSH --sudo "$T/../tools/identify_bars 2>/dev/null || true"
$SSH "ls -la /dev/xdma0_user /dev/xdma0_h2c_0 /dev/xdma0_c2h_0 /dev/xdma0_control"

echo "--- ⑤ 现态快照 (触发式; W53 W54 W70 W11 W13 W5) ---"
$SSH --sudo "cd /tmp/p9_board_0x23 && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap step0 53 54 70 11 13 5 2>&1 | tail -12"

echo "--- ⑥ NIC / 网络面 / carrier ---"
$SSH "ip -4 addr show enp1s0f1np1 | grep inet; nmcli -g GENERAL.STATE device show enp1s0f1np1; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'"
echo "--- ⑦ dmesg 尾部基线 (T1 对照用) ---"
$SSH --sudo "dmesg 2>/dev/null | wc -l; dmesg 2>/dev/null | tail -8"
echo "--- /tmp/p7b_biz md5 基线 (全程只读核对) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h 2>&1"
echo "=== STEP0_END $(date +%s.%N)"
