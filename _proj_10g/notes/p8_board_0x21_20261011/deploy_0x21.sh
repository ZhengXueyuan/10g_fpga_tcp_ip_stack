#!/bin/bash
# deploy_0x21.sh -- P8 板级 A/B 轮 (0x21): 对端部署到**本轮新目录** /tmp/p8_board_0x21/
#   纪律: ① 只读核 /tmp/p7b_biz (现役, 一字未动); ② 从 /tmp/p8_board 只读**拷贝**冻结工具
#        (镜像轮的部署件 = 上轮记录: mir_dump 25af63df / udp_src e0d4da58);
#        ③ p7b_snap.sh 用**仓库现树**件 (md5 15eb5384 = 0x21 BID 同步后的读侧件);
#        ④ run_arm.sh 用本轮 _tools/ 件; ⑤ 部署后当场 md5 双核 + 复读 /tmp/p7b_biz 证明未动。
#   用法: PEER_PW=<pw> bash deploy_0x21.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g     # ⚠️ --put 的**本机**参数必须 Windows 式 (paramiko 在 Windows Python 下不认 /d/...)
OUT=$ROOT/_proj_10g/notes/p8_board_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
# ⚠️ 本轮实测两坑 (2026-10-11): ① 不设 MSYS_NO_PATHCONV=1 时, **远端**参数 /tmp/... 会被 MSYS
#   改写成 C:/Users/.../Temp/... ⇒ 远端报 FileNotFoundError[Errno 2]; ② 设了之后, **本机**参数
#   必须 Windows 式 (D:/...); 用 /d/... 报 WinError 3。⇒ 本脚本两条同时满足。
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/DEPLOY_0x21_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== DEPLOY_BEGIN $(date +%s.%N)"

echo "--- ① 部署前: /tmp/p7b_biz md5 (现役; 部署后要复读证明未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h; ls -la /tmp/p7b_biz/ | md5sum"

echo "--- ② 建本轮目录 + 从 /tmp/p8_board 只读拷贝冻结工具 ---"
$SSH "mkdir -p /tmp/p8_board_0x21 && cp -p /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_udp_src /tmp/p8_board/p7b_pattern.h /tmp/p8_board/p7b_affinity.h /tmp/p8_board_0x21/ && echo CP_OK"

echo "--- ③ sftp put: 仓库 p7b_snap.sh (0x21 读侧件) + 本轮 run_arm.sh ---"
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_snap.sh" /tmp/p8_board_0x21/p7b_snap.sh
$SSH --put "$ROOTW/_proj_10g/notes/p8_board_0x21_20261011/_tools/run_arm.sh" /tmp/p8_board_0x21/run_arm.sh

echo "--- ④ 部署后 md5 双核 (对端 vs 本机期望) ---"
echo "[对端]"
$SSH "cd /tmp/p8_board_0x21 && md5sum p7b_mir_dump p7b_udp_src p7b_snap.sh p7b_pattern.h p7b_affinity.h run_arm.sh; ls -la"
echo "[本机期望]"
md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$OUT/_tools/run_arm.sh"
echo "EXPECT: mir_dump=25af63df72993195469761d167005533 udp_src=e0d4da5834cb95d67afb0cc523d1f92f snape=15eb5384d188a31eeaa40529aff28858"

echo "--- ⑤ 复读 /tmp/p7b_biz (与 ① 逐字比 = 未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h; ls -la /tmp/p7b_biz/ | md5sum"
echo "--- ⑥ 复读 /tmp/p8_board 与 /tmp/p8_board_0x20 (只读核对 = 未动) ---"
$SSH "md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_udp_src /tmp/p8_board_0x20/p7b_mir_dump /tmp/p8_board_0x20/p7b_udp_src"
echo "=== DEPLOY_END $(date +%s.%N)"
