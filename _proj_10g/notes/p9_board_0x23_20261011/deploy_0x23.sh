#!/bin/bash
# deploy_0x23.sh -- P9 板级 A/B 轮 (位流 0x23): 对端部署到**本轮新目录** /tmp/p9_board_0x23/
#   纪律: ① /tmp/p7b_biz 与 /tmp/p8_board* /tmp/p9_board_0x22 一律只读 (部署前后复读 md5 双核);
#        ② p7b_snap.sh 用**仓库现树** 0x23 同步件; ③ 工具源码从仓库现树 put 后**对端现编**
#           (编译口径 = BUILD.md §2: g++ -O3 -pthread -o <name> <name>.cpp);
#        ④ 部署后当场 md5 双核 + 复读 /tmp/p7b_biz 证明未动。
#   用法: PEER_PW=<pw> bash deploy_0x23.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x23_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/DEPLOY_0x23_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== DEPLOY_BEGIN $(date +%s.%N)"
echo "--- ① 部署前: 现役/历史目录指纹 (只读; 部署后要复读证明未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h; md5sum /tmp/p9_board_0x22/p7b_mir_dump /tmp/p9_board_0x22/p7b_udp_src 2>/dev/null"

echo "--- ② 建本轮目录 + put 源件 (仓库现树) ---"
$SSH "mkdir -p /tmp/p9_board_0x23 && echo MKDIR_OK"
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" /tmp/p9_board_0x23/p7b_mir_dump.cpp
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_pattern.h"    /tmp/p9_board_0x23/p7b_pattern.h
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_affinity.h"   /tmp/p9_board_0x23/p7b_affinity.h
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_udp_src.cpp"  /tmp/p9_board_0x23/p7b_udp_src.cpp
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_snap.sh"      /tmp/p9_board_0x23/p7b_snap.sh
$SSH --put "$ROOTW/_proj_10g/notes/p9_board_0x23_20261011/_tools/run_arm.sh" /tmp/p9_board_0x23/run_arm.sh
$SSH --put "$ROOTW/_proj_10g/notes/p9_board_0x23_20261011/_tools/stop_probe.sh" /tmp/p9_board_0x23/stop_probe.sh

echo "--- ③ 对端现编 (口径 = g++ -O3 -pthread -Wall; -Wall 只作零告警见证) ---"
$SSH "cd /tmp/p9_board_0x23 && g++ -O3 -pthread -Wall -o p7b_mir_dump p7b_mir_dump.cpp && echo MIR_BUILD_RC=0; g++ -O3 -pthread -Wall -o p7b_udp_src p7b_udp_src.cpp && echo SRC_BUILD_RC=0; g++ --version | head -1"

echo "--- ④ 自检 (--selftest; 期望 T1–T14 全 OK / RC=0) ---"
$SSH "cd /tmp/p9_board_0x23 && ./p7b_mir_dump --selftest > selftest_mir.txt 2>&1; echo SELFTEST_RC=\$?; tail -3 selftest_mir.txt; grep -c ' OK' selftest_mir.txt; ./p7b_udp_src --selftest > selftest_src.txt 2>&1; echo SRC_SELFTEST_RC=\$?"

echo "--- ⑤ 部署后 md5 双核 ---"
echo "[对端]"
$SSH "cd /tmp/p9_board_0x23 && md5sum p7b_mir_dump p7b_udp_src p7b_mir_dump.cpp p7b_snap.sh p7b_pattern.h p7b_affinity.h run_arm.sh stop_probe.sh; ls -la"
echo "[本机期望 (仓库现树)]"
md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$ROOT/_proj_pcie/p7b_biz/p7b_pattern.h" "$ROOT/_proj_pcie/p7b_biz/p7b_udp_src.cpp" "$OUT/_tools/run_arm.sh" "$OUT/_tools/stop_probe.sh"

echo "--- ⑥ 复读 /tmp/p7b_biz 与历史目录 (与 ① 逐字比 = 未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h; md5sum /tmp/p9_board_0x22/p7b_mir_dump /tmp/p9_board_0x22/p7b_udp_src 2>/dev/null"
echo "--- ⑦ 网络面 (每次测量前现取) ---"
$SSH "ip -4 addr show enp1s0f1np1 | grep inet; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'"
echo "=== DEPLOY_END $(date +%s.%N)"
