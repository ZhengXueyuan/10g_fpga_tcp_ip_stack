#!/bin/bash
# step0_selfcheck.sh -- P8 板级轮 (2026-10-11): 只读自检
#   目的 = 在烧 0x1F 之前, 核: 归档位流 sha256 / 对端可达 / 工具名册与 md5 / 网络面 /
#          板上现态 / /dev/xdma* 节点 / 无残留进程。
#   ⚠️ 本步不烧录、不写寄存器(除 reg_rw 只读读)、不动 /tmp/p7b_biz/。
#   用法: PEER_PW=<pw> bash step0_selfcheck.sh     (口令只作 --sudo 前缀, 不落盘)
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_board_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
SSH="$PY $ROOTW/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW 环境变量 (只用于 --sudo, 不落盘)"; exit 3; }

mkdir -p "$OUT/_tools" "$OUT/runs" "$OUT/burn"
exec > >(tee "$OUT/STEP0_selfcheck.txt") 2>&1

echo "### STEP0_BEGIN $(date +%Y-%m-%dT%H:%M:%S%z)"

echo
echo "### A) 归档位流 0x1F (派单指定源; 只烧这个目录里的 wrapper_p4.bit)"
F=$ROOT/_proj_10g/notes/p7b_build_0x1F/wrapper_p4.bit
sha256sum "$F"
stat -c 'BIT %n size=%s mtime=%y' "$F"
grep -n 'wrapper_p4.bit' "$ROOT/_proj_10g/notes/p7b_build_0x1F/SHA256SUMS.txt" | head -3
echo "WANT_0x1F=e365c5ca4fd25335f6713b2a960b4de5af5b42e0bda238c20d41011ca7460133"

echo
echo "### B) 对端可达 + 本部署件 md5 (新目录 /tmp/p8_board; 现役 /tmp/p7b_biz 只读不动)"
$SSH "echo PEER_OK; hostname; date; uptime | head -1"
echo "--- 现役 /tmp/p7b_biz (只读核对, 不许改) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_tcp_sink 2>&1 | head -4"
echo "--- 本轮新部署 /tmp/p8_board ---"
$SSH "cd /tmp/p8_board && echo '--来源源码 md5--' && md5sum *.cpp *.h *.sh 2>/dev/null && echo '--编译件 md5--' && md5sum p7b_mir_dump p7b_udp_src p8_udp_rx_check p8_mocktest_fix p8_mocktest_orig 2>/dev/null && echo '--二进制大小--' && stat -c '%n %s' p7b_mir_dump p7b_udp_src p8_udp_rx_check"
echo "--- 仓库侧对照 md5 (现核) ---"
md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_udp_src.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_pattern.h" "$ROOT/_proj_pcie/p7b_biz/p7b_affinity.h" "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$ROOT/_tools/na" 2>/dev/null | head -6
echo "--- read-side 默认值 (仓库 p7b_snap.sh, 已同步 0x1F?) ---"
grep -nE '^NW=|^EXPECT_BID=|^UNIMPL_ADDR=' "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh"
echo "--- 对端 g++ / python3 / 空间 ---"
$SSH "g++ --version | head -1; python3 -V 2>&1; df -h /tmp | tail -1"

echo
echo "### C) 网络面 (每次测量前现取): /32 路由 + NetworkManager 托管位 + link + coalesce + neigh"
$SSH "ip -4 addr show enp1s0f1np1 | grep -E 'inet |state'; echo ---; nmcli device show enp1s0f1np1 2>/dev/null | grep -E 'GENERAL.STATE|GENERAL.CONNECTION'; echo ---; ip route get 192.168.100.2 | head -2; echo ---; ip neigh show 192.168.100.2; echo ---; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; echo ---; ethtool -c enp1s0f1np1 | grep -E 'Adaptive|rx-usecs' | head -4"

echo
echo "### D) 板上现态 (烧 0x1F 之前) —— 期望: sndwnd 轮留下的 0x1E / 70 字"
$SSH --sudo "T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \
  echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x138='; \$T/reg_rw /dev/xdma0_user 0x138 w 2>&1 | tail -1; \
  echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; \
  lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'"

echo
echo "### E) 零构建项 ①: /dev/xdma* 节点 (我们的位流下 c2h_0/h2c_0 是否存在)"
$SSH "ls -la /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_control 2>&1; echo '---节点总数---'; ls /dev/xdma* 2>/dev/null | wc -l"
$SSH --sudo "dmesg 2>/dev/null | grep -iE 'xdma|identify_bars|probe_one' | tail -8"

echo
echo "### F) 残留进程 (对端: sink/tcpdump/探针/我轮工具; 本地: python/vivado/xsim)"
$SSH "pgrep -a p7b_tcp_sink; pgrep -a tcpdump; pgrep -af '[s]tall_probe|[p]ersist_client'; pgrep -a p8_udp_rx_check; echo '(空 = 无残留)'"
echo "--- 本地 ---"
tasklist 2>/dev/null | grep -iE 'python|vivado|xsim' | head -10 || true

echo
echo "### STEP0_END $(date +%Y-%m-%dT%H:%M:%S%z)"
