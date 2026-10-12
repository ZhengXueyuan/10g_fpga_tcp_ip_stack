#!/bin/bash
# 01_deploy.sh -- p9 bench restore 2026-10-13: 重部署台架到对端 /tmp/p7b_biz/ + /tmp/p9_board_0x23/
#   配方依据: HANDOFF §6-新块 A.2 + p7b_affinity/BUILD.md §2(唯一编译口径) §6(部署原文)
#             + p7b_env_restore_20261009/04_deploy.txt(27 件清单)
#   纪律: 编译口径 = `g++ -O3 -pthread -o <name> <name>.cpp` (BUILD.md §2, 不加 -std=)
#   ⛔ 只部署, 不烧录, 不写任何寄存器。
#   用法: PEER_PW=<pw> bash 01_deploy.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_bench_restore_20261013
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW (只用于 --sudo)"; exit 3; }
exec > >(tee "$OUT/01_deploy_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== DEPLOY_BEGIN $(date +%s.%N) $(date)"

echo "--- 0) 建目录 + 部署前清单 (重启后 /tmp 应空) ---"
$SSH "mkdir -p /tmp/p7b_biz /tmp/p9_board_0x23 && echo MKDIR_OK; ls -la /tmp/p7b_biz /tmp/p9_board_0x23"

echo "--- 1) put 源件 (仓库现树) ---"
FAILS=0
for f in \
  _proj_pcie/p7b_biz/p7b_affinity.h \
  _proj_pcie/p7b_biz/p7b_io.h \
  _proj_pcie/p7b_biz/p7b_spsc.h \
  _proj_pcie/p7b_biz/p7b_pattern.h \
  _proj_pcie/p7b_biz/p7b_tcp_sink.cpp \
  _proj_pcie/p7b_biz/p7b_tcp_src.cpp \
  _proj_pcie/p7b_biz/p7b_udp_src.cpp \
  _proj_pcie/p7b_biz/p7b_rate2_bench.cpp \
  _proj_pcie/p7b_biz/p7b_mir_dump.cpp \
  _proj_10g/notes/p7b_biz_tcpreg/p7b_tcp_src_fix.cpp \
  _proj_10g/notes/p7b_biz_tcpreg/p7b_tcp_src_diag.cpp \
  _proj_10g/notes/p7b_board_stageb/p7b_tcp_src_rate.cpp \
  _proj_10g/notes/p7b_board_stagec/p7b_tcp_sink_rate.cpp \
  _proj_pcie/p7b_biz/p7b_selftest.sh \
  _proj_pcie/p7b_biz/p7b_dualthread_selftest.sh \
  _proj_pcie/p7b_biz/p7b_lane8_selftest.sh \
  _proj_pcie/p7b_biz/aff_selftest.sh \
  _proj_pcie/p7b_biz/p7b_snap.sh \
  _proj_pcie/p7b_biz/p7b_fake_board.py \
  _proj_10g/notes/p7b_affinity/p7baff_faultinject.cpp \
  _proj_10g/notes/p7b_board_stagec/stc_dl.sh \
  _proj_10g/notes/p7b_board_stagec/stc_bidir.sh \
  _proj_10g/notes/p7b_board_stagec/j6_stagec.sh \
  _proj_10g/notes/p7b_board_stagec/pcap_off_dryrun.sh \
  _proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh \
  _proj_10g/notes/p7b_longflow_board/lf_dl.sh \
  _proj_10g/notes/p7b_longflow_board/calc_lf.py \
  _proj_10g/notes/p7b_longflow_board/nicdelta.py \
  ; do
  B=$(basename "$f")
  if $SSH --put "$ROOTW/$f" "/tmp/p7b_biz/$B"; then :; else echo "PUT_FAIL $f"; FAILS=$((FAILS+1)); fi
done
echo "PUT_FAILS=$FAILS"

echo "--- 2) put 0x23 板级测试目录件 (/tmp/p9_board_0x23/) ---"
PUT2=0
for pair in \
  "_proj_pcie/p7b_biz/p7b_mir_dump.cpp p7b_mir_dump.cpp" \
  "_proj_pcie/p7b_biz/p7b_pattern.h p7b_pattern.h" \
  "_proj_pcie/p7b_biz/p7b_affinity.h p7b_affinity.h" \
  "_proj_pcie/p7b_biz/p7b_udp_src.cpp p7b_udp_src.cpp" \
  "_proj_pcie/p7b_biz/p7b_snap.sh p7b_snap.sh" \
  "_proj_10g/notes/p9_board_0x23_20261011/_tools/run_arm.sh run_arm.sh" \
  "_proj_10g/notes/p9_board_0x23_20261011/_tools/stop_probe.sh stop_probe.sh" \
  "_proj_10g/notes/p9_board_0x23_20261011/_tools/final_state.sh final_state.sh" \
  ; do
  SRC=$(echo "$pair" | cut -d' ' -f1); DST=$(echo "$pair" | cut -d' ' -f2)
  if $SSH --put "$ROOTW/$SRC" "/tmp/p9_board_0x23/$DST"; then PUT2=$((PUT2+1)); else echo "PUT2_FAIL $SRC"; fi
done
echo "PUT2_OK=$PUT2/8"

echo "--- 3) 对端现编 8 个产物 (BUILD.md §2 唯一口径) + p7b_mir_dump ---"
$SSH "cd /tmp/p7b_biz && for n in p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench; do g++ -O3 -pthread -o \$n \$n.cpp 2> \$n.build.err; RC=\$?; EB=\$(wc -c < \$n.build.err); echo \"BUILD \$n rc=\$RC errbytes=\$EB\"; [ \$RC -ne 0 ] && cat \$n.build.err; done; g++ -O3 -pthread -o p7b_mir_dump p7b_mir_dump.cpp 2> mir.build.err; echo \"BUILD p7b_mir_dump rc=\$? errbytes=\$(wc -c < mir.build.err)\"; g++ --version | head -1"

echo "--- 4) 0x23 目录现编 (mir_dump + udp_src; 口径 = g++ -O3 -pthread -Wall, 同 p9 轮) ---"
$SSH "cd /tmp/p9_board_0x23 && g++ -O3 -pthread -Wall -o p7b_mir_dump p7b_mir_dump.cpp 2> mir.build.err; echo MIR_BUILD_RC=\$? errbytes=\$(wc -c < mir.build.err); g++ -O3 -pthread -Wall -o p7b_udp_src p7b_udp_src.cpp 2> src.build.err; echo SRC_BUILD_RC=\$? errbytes=\$(wc -c < src.build.err)"

echo "--- 5) md5 双核 (对端 vs 本机仓库现树) ---"
echo "[对端 /tmp/p7b_biz 源+产物]"
$SSH "cd /tmp/p7b_biz && md5sum p7b_affinity.h p7b_io.h p7b_spsc.h p7b_pattern.h p7b_tcp_sink.cpp p7b_tcp_src.cpp p7b_udp_src.cpp p7b_rate2_bench.cpp p7b_mir_dump.cpp p7b_tcp_src_fix.cpp p7b_tcp_src_diag.cpp p7b_tcp_src_rate.cpp p7b_tcp_sink_rate.cpp p7b_snap.sh p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench p7b_mir_dump"
echo "[对端 /tmp/p9_board_0x23]"
$SSH "cd /tmp/p9_board_0x23 && md5sum p7b_mir_dump p7b_udp_src p7b_mir_dump.cpp p7b_snap.sh p7b_pattern.h p7b_affinity.h run_arm.sh stop_probe.sh final_state.sh"
echo "[本机仓库现树 期望]"
md5sum "$ROOT"/_proj_pcie/p7b_biz/{p7b_affinity.h,p7b_io.h,p7b_spsc.h,p7b_pattern.h,p7b_tcp_sink.cpp,p7b_tcp_src.cpp,p7b_udp_src.cpp,p7b_rate2_bench.cpp,p7b_mir_dump.cpp,p7b_snap.sh} \
       "$ROOT"/_proj_10g/notes/p7b_biz_tcpreg/{p7b_tcp_src_fix.cpp,p7b_tcp_src_diag.cpp} \
       "$ROOT"/_proj_10g/notes/p7b_board_stageb/p7b_tcp_src_rate.cpp \
       "$ROOT"/_proj_10g/notes/p7b_board_stagec/p7b_tcp_sink_rate.cpp \
       "$ROOT"/_proj_10g/notes/p9_board_0x23_20261011/_tools/{run_arm.sh,stop_probe.sh,final_state.sh}

echo "--- 6) reg_rw 在位 + 工具自检 (不碰板子) ---"
$SSH "ls -la /home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools/reg_rw /home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools/dma_from_device"
$SSH "cd /tmp/p9_board_0x23 && ./p7b_mir_dump --selftest > selftest_mir.txt 2>&1; echo SELFTEST_MIR_RC=\$?; tail -3 selftest_mir.txt; grep -c ' OK' selftest_mir.txt; ./p7b_udp_src --selftest > selftest_src.txt 2>&1; echo SELFTEST_SRC_RC=\$?"
echo "=== DEPLOY_END $(date +%s.%N)"
