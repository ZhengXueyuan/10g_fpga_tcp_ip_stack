#!/bin/bash
# read_final_state.sh -- B1 轮收尾读数（板态 / NIC / 部署件指纹 / 残留进程）—— 供 B2/B3 复用
#   用法: PEER_PW=<pw> bash read_final_state.sh <TAG>
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x27_k0_20261015/env
TAG=${1:-FINAL}
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
exec > >(tee "$OUT/FINAL_STATE_$TAG.txt") 2>&1
echo "=== FINAL_STATE_BEGIN $TAG $(date +%s.%N) $(date)"
echo "--- 板侧 (板 = 插在对端 PCIe 槽的卡) ---"
$SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  NW=71 EXPECT_BID=0x00000027 bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"
$SSH --sudo "lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'; ls /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1"
echo "--- NIC ---"
$SSH "ip route get 192.168.100.2 | head -1; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo; \
  ip -4 addr show enp1s0f1np1 | grep inet; nmcli device status | grep enp1s0f1np1; \
  ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; ethtool -c enp1s0f1np1 | grep -E 'Adaptive RX|rx-usecs:'; \
  systemctl is-active irqbalance"
echo "--- 残留进程 ---"
$SSH --sudo "pgrep -af '[p]7b_' || echo NO_P7B_PROCS; pgrep -af '[t]cpdump' || echo NO_TCPDUMP; pgrep -af '[k]0_' || echo NO_K0"
echo "--- 对端 /tmp 本轮残留 (供 B2/B3 判可复用性) ---"
$SSH --sudo "ls -la /tmp | grep -E 'k0_|k0run|k0an|k0_split' | awk '{print \$5, \$9}' | head -40; df -h /tmp | tail -1"
echo "--- 部署件 md5 (对端现读; 与 env/DEPLOY 表逐条比) ---"
$SSH "cd /tmp/p7b_biz && md5sum p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench p7b_mir_dump p7b_snap.sh align_check2_fixed.py split_conn_pcap.py k0_arm.sh k0_analyze.sh 2>&1"
echo "=== FINAL_STATE_END $TAG $(date +%s.%N)"
