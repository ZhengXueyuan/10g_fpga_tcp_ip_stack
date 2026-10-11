#!/bin/bash
# final_state_tcp.sh -- P8 TCP 臂收尾: 端口核对 + 清 sticky + 受控停流 + 撤 fq + 进程扫描 + 最终态
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_tcp_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/FINAL_STATE_TCP_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "### FINAL_BEGIN $(date +%Y-%m-%dT%H:%M:%S%z)"
echo "--- A) 端口核对 (派单写 8081; 板上 TCP 服务端口 = 8080 —— hls/src/layer_tcp.cpp:17) ---"
$SSH "echo -n 'CONNECT_8081='; timeout 3 bash -c 'exec 3<>/dev/tcp/192.168.100.2/8081 && echo OK' 2>&1 || echo RC=\$?; echo -n 'CONNECT_8080='; timeout 3 bash -c 'exec 3<>/dev/tcp/192.168.100.2/8080 && echo OK' 2>&1 || echo RC=\$?"
echo "--- B) 清 sticky (clr) 后置冻结默认态 ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x144 w 0x2 2>&1 | tail -1; \$T/reg_rw /dev/xdma0_user 0x144 w 0x0 2>&1 | tail -1"
echo "--- C) 受控停流 (0x08=0x2) ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
sleep 3
echo "--- D) 撤 fq 根 qdisc (回 mq) ---"
$SSH --sudo "tc qdisc del dev enp1s0f1np1 root 2>&1; tc qdisc show dev enp1s0f1np1 | head -3"
echo "--- E) 残留进程扫描 (对端) ---"
$SSH "ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE"
echo "--- F) 对端最终态 ---"
$SSH "echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ip -4 addr show enp1s0f1np1 | grep -E 'inet |state'; nmcli device show enp1s0f1np1 2>/dev/null | grep -E 'GENERAL.STATE'"
echo "--- G) 板侧最终态 (只读) ---"
$SSH --sudo "T=$T; for a in 0x00 0x04 0x08 0x14C 0x13C 0x144 0x148 0xF4 0xF8 0x138 0x4C 0x54; do echo -n \"R_\$a=\"; \$T/reg_rw /dev/xdma0_user \$a w 2>&1 | tail -1; done; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:'"
echo "--- H) 触发式快照 (最终 W53/W54/W70/W11/W13) ---"
$SSH --sudo "cd /tmp/p8_tcp_0x21 && NW=71 EXPECT_BID=0x00000021 bash ./p7b_snap.sh snap FINAL 53 54 70 11 13 5 43 20 2>&1"
echo "--- I) 未动复读 (只读核对两个旧目录 + 现役工具) ---"
$SSH "md5sum /tmp/p7b_biz/p7b_tcp_src /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h 2>&1; ls /tmp/p7b_biz/ | md5sum; md5sum /tmp/p8_board/p7b_mir_dump /tmp/p8_board/p7b_tcp_src; ls /tmp/p8_board/ | md5sum"
echo "### FINAL_END $(date +%Y-%m-%dT%H:%M:%S%z)"
