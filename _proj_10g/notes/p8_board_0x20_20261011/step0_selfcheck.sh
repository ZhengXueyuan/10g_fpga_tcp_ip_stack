#!/bin/bash
# step0_selfcheck.sh -- P8 板级 A/B 轮 (位流 0x20): 只读自检
#   目的 = 烧 0x20 之前核: 归档位流 sha256 / 对端可达 / 工具名册 md5 / 网络面 / 板上现态 /
#          /dev/xdma* 节点 / 无残留进程 / 背景泛洪量 (板->对端)。
#   ⚠️ 本步不烧录、不写寄存器 (只读)、不动 /tmp/p7b_biz/、不改 /tmp/p8_board/ 里的任何件。
#   用法: PEER_PW=<pw> bash step0_selfcheck.sh     (口令只作 --sudo 前缀, 不落盘)
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_board_0x20_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW 环境变量 (只用于 --sudo, 不落盘)"; exit 3; }
mkdir -p "$OUT/runs" "$OUT/burn" "$OUT/_tools"
exec > >(tee "$OUT/STEP0_selfcheck.txt") 2>&1

echo "### STEP0_BEGIN $(date +%Y-%m-%dT%H:%M:%S%z)"

echo; echo "### A) 归档位流 0x20 (派单指定源; 只烧这个目录里的 wrapper_p4.bit)"
F=$ROOT/_proj_10g/notes/p8_build_0x20/wrapper_p4.bit
sha256sum "$F"
stat -c 'BIT %n size=%s mtime=%y' "$F"
grep -n "wrapper_p4.bit" "$ROOT/_proj_10g/notes/p8_build_0x20/SHA256SUMS.txt" | head -3
echo "WANT_0x20=998ff90f31907750f31024d2aa62828a8e08c3cd097b03fc9eb15a82b037d244"

echo; echo "### B) 对端可达 + 部署件 md5 (现役 /tmp/p8_board; 只读核对)"
$SSH "echo PEER_OK; hostname; date; uptime | head -1"
echo "--- /tmp/p8_board 部署件 md5 (期望 = 上轮记录: mir_dump 25af63df… / udp_src e0d4da58…) ---"
$SSH "cd /tmp/p8_board && md5sum p7b_mir_dump p7b_udp_src p7b_snap.sh p7b_pattern.h p7b_affinity.h 2>&1; echo '--- size ---'; stat -c '%n %s' p7b_mir_dump p7b_udp_src"
echo "--- 仓库侧对照 md5 (现核; ★ = 上轮记录的源码 md5) ---"
md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_udp_src.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_pattern.h" "$ROOT/_proj_pcie/p7b_biz/p7b_affinity.h" "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh"
echo "--- 对端 g++ ---"
$SSH "g++ --version | head -1"

echo; echo "### C) 网络面 (每次测量前现取): /32 路由 + 托管位 + link + coalesce + neigh"
$SSH "ip -4 addr show enp1s0f1np1 | grep -E 'inet |state'; echo ---; nmcli device show enp1s0f1np1 2>/dev/null | grep -E 'GENERAL.STATE|GENERAL.CONNECTION'; echo ---; ip route get 192.168.100.2 | head -2; echo ---; ip neigh show 192.168.100.2; echo ---; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; echo ---; ethtool -c enp1s0f1np1 | grep -E 'Adaptive|rx-usecs' | head -4"

echo; echo "### C2) 背景泛洪量 (板 -> 对端): NIC rx 计数 2 s 差分 + 板侧 W43/W20 两次读"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '--- 2s later ---'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; echo -n 'W43a=';\$T/reg_rw /dev/xdma0_user 0xCC w 2>&1 | tail -1; echo -n 'W20a=';\$T/reg_rw /dev/xdma0_user 0x70 w 2>&1 | tail -1; sleep 2; echo -n 'W43b=';\$T/reg_rw /dev/xdma0_user 0xCC w 2>&1 | tail -1; echo -n 'W20b=';\$T/reg_rw /dev/xdma0_user 0x70 w 2>&1 | tail -1"

echo; echo "### D) 板上现态 (烧 0x20 之前) —— 期望: 上轮留下的 0x1F"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; echo -n 'MAGIC_0x00=';\$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';\$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08=';\$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C=';\$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'W11_0x4C=';\$T/reg_rw /dev/xdma0_user 0x4C w 2>&1 | tail -1; \
  echo -n 'W70_0x138=';\$T/reg_rw /dev/xdma0_user 0x138 w 2>&1 | tail -1; \
  echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; \
  lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'"

echo; echo "### E) /dev/xdma* 节点 + 残留进程 (对端)"
$SSH "ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 2>&1; echo '---节点总数---'; ls /dev/xdma* 2>/dev/null | wc -l"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE"
$SSH --sudo "dmesg 2>/dev/null | grep -iE 'xdma|identify_bars' | tail -4"

echo; echo "### STEP0_END $(date +%Y-%m-%dT%H:%M:%S%z)"
