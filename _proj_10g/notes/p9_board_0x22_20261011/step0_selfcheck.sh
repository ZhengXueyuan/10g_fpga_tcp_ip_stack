#!/bin/bash
# step0_selfcheck.sh -- P9 板级首测 (位流 0x22, XDMA 已切 AXIS): 开工前只读自检
#   ① 本机: 位流 sha256 双核 (派单值 c2e48a69…635a) / 工具源码 sha256 (f5e8d486…)
#   ② 对端: 连通 / /tmp 目录清单 / 残留进程 / 现役 /tmp/p7b_biz 指纹 (只读)
#   ③ 板: 现态寄存器 (**MM 对照臂**: 0x21 上的 identifier bit15 / alignments) + dmesg 引擎名
#   ⛔ 只读; 不烧 / 不写 / 不杀进程。用法: PEER_PW=<pw> bash step0_selfcheck.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x22_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW (只用于 --sudo)"; exit 3; }
exec > >(tee "$OUT/STEP0_selfcheck.txt") 2>&1
echo "=== STEP0_BEGIN $(date +%s.%N) $(date)"

echo "--- ① 本机: 位流 + 工具 sha256 双核 ---"
WANT_BIT=c2e48a6961fdb26ad453aa71198b8552e4bdd9c47bbdaf287a7dbd145127635a
sha256sum "$ROOT/_proj_10g/notes/p9_build_0x22/wrapper_p4.bit"
GOT=$(sha256sum "$ROOT/_proj_10g/notes/p9_build_0x22/wrapper_p4.bit" | cut -d' ' -f1)
echo "SHA_WANT want=$WANT_BIT"
[ "$GOT" = "$WANT_BIT" ] && echo "SHA_OK 位流 == 派单值" || echo "SHA_FAIL 位流 != 派单值"
sha256sum "$ROOT/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$ROOT/_proj_pcie/p7b_biz/p7b_udp_src.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_pattern.h" "$ROOT/_proj_pcie/p7b_biz/p7b_affinity.h"
echo "TOOL_WANT p7b_mir_dump.cpp = f5e8d486ff3816b3fcb016762a86175058190eeb3af8b3620eeffee556ac8eb1"

echo "--- ② 对端: 连通 + /tmp 清单 + 残留进程 + /tmp/p7b_biz 指纹(只读) ---"
$SSH "uname -r; echo '--- /tmp 清单 ---'; ls -d /tmp/p7b_biz /tmp/p8_board* /tmp/p9_* 2>/dev/null; echo '--- 残留进程 ---'; ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE"
echo "--- /tmp/p7b_biz 指纹 (只读; 本轮一字不动) ---"
$SSH "cd /tmp/p7b_biz 2>/dev/null && md5sum p7b_udp_src p7b_snap.sh p7b_pattern.h p7b_affinity.h 2>/dev/null; ls -la /tmp/p7b_biz | md5sum"

echo "--- ③ 板: 现态寄存器 (0x21 = MM 臂; 对照臂基线) ---"
$SSH --sudo 'T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \
  for a in 0x00 0x04 0x08 0x14C 0x144 0x13C 0x148; do printf "user %s=" $a; $T/reg_rw /dev/xdma0_user $a w 2>&1 | tail -1; done; \
  for a in 0x0000 0x1000 0x004C 0x104C; do printf "ctrl %s=" $a; $T/reg_rw /dev/xdma0_control $a r 2>&1 | tail -1; done; \
  echo "--- dmesg 引擎名 (MM 对照臂) ---"; dmesg 2>/dev/null | grep -i xdma | grep -E "C2H0|H2C0|streaming|identify_bars" | tail -8'
echo "--- 对端网络面 (每次测量前现取) ---"
$SSH "ip -4 addr show enp1s0f1np1 | grep inet; nmcli -g GENERAL.STATE device show enp1s0f1np1 2>/dev/null; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ip route get 192.168.100.2 2>&1 | head -2"
echo "=== STEP0_END $(date +%s.%N)"
