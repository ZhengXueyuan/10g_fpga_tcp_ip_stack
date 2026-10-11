#!/bin/bash
# step0_tcp.sh -- P8 TCP 臂 (位流 0x21): 只读自检 (不烧/不写寄存器/不动任何 /tmp 目录)
#   用法: PEER_PW=<pw> bash step0_tcp.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_tcp_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
mkdir -p "$OUT/runs" "$OUT/_tools"
exec > >(tee "$OUT/runs/STEP0_TCP_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "### STEP0_BEGIN $(date +%Y-%m-%dT%H:%M:%S%z)"
echo; echo "### A) 对端 + 现役/历史工具名册 (只读)"
$SSH "hostname; date; uname -r"
echo "--- /tmp/p7b_biz (现役) ---"; $SSH "ls -la /tmp/p7b_biz/ 2>&1 | head -20"
echo "--- md5 现役关键件 ---"; $SSH "md5sum /tmp/p7b_biz/p7b_tcp_src /tmp/p7b_biz/p7b_mir_dump /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h 2>&1"
echo "--- /tmp/p8_board (镜像轮件) ---"; $SSH "md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_tcp_src /tmp/p8_board/p7b_snap.sh 2>&1"
echo "--- /tmp/p8_board_0x21 (上轮 0x21 件) ---"; $SSH "ls -la /tmp/p8_board_0x21/ 2>&1 | head -20; md5sum /tmp/p8_board_0x21/p7b_mir_dump /tmp/p8_board_0x21/p7b_snap.sh 2>&1"
echo; echo "### B) 仓库侧对照 md5 (现核)"
md5sum "$ROOT/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_tcp_src.cpp" "$ROOT/_proj_pcie/p7b_biz/p7b_snap.sh" "$ROOT/_proj_pcie/p7b_biz/p7b_pattern.h" "$ROOT/_proj_pcie/p7b_biz/p7b_affinity.h"
echo; echo "### C) 网络面 (每次测量前现取)"
$SSH "ip -4 addr show enp1s0f1np1 | grep -E 'inet |state'; echo ---; nmcli device show enp1s0f1np1 2>/dev/null | grep -E 'GENERAL.STATE|GENERAL.CONNECTION'; echo ---; ip route get 192.168.100.2 | head -2; echo ---; ip neigh show 192.168.100.2; echo ---; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; echo ---; ethtool -c enp1s0f1np1 | grep -E 'Adaptive|rx-usecs' | head -4; echo ---; tc qdisc show dev enp1s0f1np1 | head -3"
echo; echo "### D) 板上现态 (只读; 期望 BID=0x21 / 0x08=0x2 受控停流)"
$SSH --sudo "T=$T; for a in 0x00 0x04 0x08 0x14C 0x4C 0x54 0xF4 0xF8 0x138 0x13C 0x144 0x148; do echo -n \"R_\$a=\"; \$T/reg_rw /dev/xdma0_user \$a w 2>&1 | tail -1; done; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'"
echo; echo "### E) /dev/xdma* + 残留进程 + dmesg"
$SSH "ls -la /dev/xdma0_user /dev/xdma0_c2h_0 2>&1; echo '--- nodes ---'; ls /dev/xdma* 2>/dev/null | wc -l"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE"
echo "### STEP0_END $(date +%Y-%m-%dT%H:%M:%S%z)"
