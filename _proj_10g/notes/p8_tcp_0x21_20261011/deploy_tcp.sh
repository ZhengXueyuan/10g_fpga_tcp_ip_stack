#!/bin/bash
# deploy_tcp.sh -- P8 TCP 臂: 对端部署到**本轮新目录** /tmp/p8_tcp_0x21/
#   纪律: ① 只读核 /tmp/p7b_biz 与 /tmp/p8_board (现役/上轮件, 一字不动);
#        ② 从 /tmp/p8_board 只读**拷贝**冻结工具 (mir_dump 25af63df / tcp_src 79be2a09
#           = 0x1F 轮 TCP 臂的同一件 ⇒ 与那一轮只差位流);
#        ③ p7b_snap.sh 用**仓库现树**件 (15eb5384 = 0x21 读侧件);
#        ④ run_tcp_arm.sh 用本轮 _tools/ 件; ⑤ 部署后 md5 双核 + 复读两个旧目录证明未动。
#   用法: PEER_PW=<pw> bash deploy_tcp.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g     # ⚠️ --put 的**本机**参数必须 Windows 式
OUT=$ROOT/_proj_10g/notes/p8_tcp_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/DEPLOY_TCP_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "=== DEPLOY_BEGIN $(date +%s.%N)"
echo "--- ① 部署前: /tmp/p7b_biz 与 /tmp/p8_board md5 (只读; 部署后要复读证明未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_tcp_src /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h 2>&1; ls /tmp/p7b_biz/ | md5sum; echo ---; md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_tcp_src /tmp/p8_board/p7b_pattern.h /tmp/p8_board/p7b_affinity.h 2>&1; ls /tmp/p8_board/ | md5sum"
echo "--- ② 建本轮目录 + 从 /tmp/p8_board 只读拷贝冻结工具 ---"
$SSH "mkdir -p /tmp/p8_tcp_0x21 && cp -p /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_tcp_src /tmp/p8_board/p7b_pattern.h /tmp/p8_board/p7b_affinity.h /tmp/p8_tcp_0x21/ && echo CP_OK"
echo "--- ③ sftp put: 仓库 p7b_snap.sh (0x21 读侧件) + 本轮 run_tcp_arm.sh ---"
$SSH --put "$ROOTW/_proj_pcie/p7b_biz/p7b_snap.sh" /tmp/p8_tcp_0x21/p7b_snap.sh
$SSH --put "$ROOTW/_proj_10g/notes/p8_tcp_0x21_20261011/_tools/run_tcp_arm.sh" /tmp/p8_tcp_0x21/run_tcp_arm.sh
echo "--- ④ 部署后 md5 双核 (对端 vs 本机期望) ---"
echo "[对端]"; $SSH "cd /tmp/p8_tcp_0x21 && md5sum p7b_mir_dump p7b_tcp_src p7b_snap.sh p7b_pattern.h p7b_affinity.h run_tcp_arm.sh; ls -la"
echo "[本机期望]"; md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$OUT/_tools/run_tcp_arm.sh"
echo "EXPECT: mir_dump=25af63df72993195469761d167005533 tcp_src=79be2a09024206b7c678dc13a3b9051d snape=15eb5384d188a31eeaa40529aff28858"
echo "--- ⑤ 复读两个旧目录 (与 ① 逐字比 = 未动) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_tcp_src /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h 2>&1; ls /tmp/p7b_biz/ | md5sum; echo ---; md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_tcp_src 2>&1"
echo "=== DEPLOY_END $(date +%s.%N)"
