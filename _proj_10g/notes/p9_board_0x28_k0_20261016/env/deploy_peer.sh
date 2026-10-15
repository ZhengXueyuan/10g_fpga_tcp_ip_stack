#!/bin/bash
# deploy_peer.sh -- B4 轮：对端 (/tmp/p7b_biz) 工具全量重部署 + 自验
#   配方 = `_proj_10g/notes/p7b_affinity/BUILD.md` §1-§3 + §6（编译口径 = g++ -O3 -pthread）
#   母本 = B1 轮 deploy_peer.sh（逐字保留清单与步骤）; B4 增补 = k0_arm_b4.sh + k0_analyze.sh
#   本脚本不改任何仓内文件；只 --put + 对端编译 + md5 记录 + 板外自检
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
B=/d/repo/XCKU5PMini/udp_hls_10g
BW=D:/repo/XCKU5PMini/udp_hls_10g
P=/c/Users/zhxue/anaconda3/python.exe
SSH="$P $BW/tools/peer_ssh.py"
OUT=$B/_proj_10g/notes/p9_board_0x28_k0_20261016/env
mkdir -p "$OUT"

FILES=(
 _proj_pcie/p7b_biz/p7b_affinity.h
 _proj_pcie/p7b_biz/p7b_io.h
 _proj_pcie/p7b_biz/p7b_spsc.h
 _proj_pcie/p7b_biz/p7b_pattern.h
 _proj_pcie/p7b_biz/p7b_tcp_sink.cpp
 _proj_pcie/p7b_biz/p7b_tcp_src.cpp
 _proj_pcie/p7b_biz/p7b_udp_src.cpp
 _proj_pcie/p7b_biz/p7b_rate2_bench.cpp
 _proj_pcie/p7b_biz/p7b_mir_dump.cpp
 _proj_pcie/p7b_biz/p7b_snap.sh
 _proj_pcie/p7b_biz/p7b_selftest.sh
 _proj_pcie/p7b_biz/p7b_dualthread_selftest.sh
 _proj_pcie/p7b_biz/p7b_lane8_selftest.sh
 _proj_pcie/p7b_biz/aff_selftest.sh
 _proj_10g/notes/p7b_biz_tcpreg/p7b_tcp_src_fix.cpp
 _proj_10g/notes/p7b_biz_tcpreg/p7b_tcp_src_diag.cpp
 _proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh
 _proj_10g/notes/p7b_board_stageb/p7b_tcp_src_rate.cpp
 _proj_10g/notes/p7b_board_stagec/p7b_tcp_sink_rate.cpp
 _proj_10g/notes/p7b_board_stagec/pcap_off_dryrun.sh
)
# K0 分析件（B1 轮交付, 冻结） + B4 本轮执行件
ROUND_FILES=(
 _proj_10g/notes/p9_board_0x27_k0_20261015/_tools/align_check2_fixed.py
 _proj_10g/notes/p9_board_0x27_k0_20261015/_tools/split_conn_pcap.py
 _proj_10g/notes/p9_board_0x28_k0_20261016/k0_arm_b4.sh
 _proj_10g/notes/p9_board_0x28_k0_20261016/k0_analyze.sh
)

echo "=== DEPLOY_BEGIN $(date +%s.%N) $(date) ==="
echo "--- 0) 对端现态 ---"
$SSH "hostname; uptime -s; ls -la /tmp/p7b_biz 2>&1 | head -3"

echo "--- 1) mkdir + --put 源/脚本/工具 ---"
$SSH "mkdir -p /tmp/p7b_biz /tmp/p7b_biz_k0"
RC_PUT=0
for f in "${FILES[@]}" "${ROUND_FILES[@]}"; do
  if $SSH --put "$BW/$f" "/tmp/p7b_biz/$(basename "$f")" >/dev/null 2>&1; then
    echo "PUT_OK  $(basename "$f")"
  else
    echo "PUT_FAIL $(basename "$f")"; RC_PUT=1
  fi
done
[ $RC_PUT -eq 0 ] || { echo "PUT_FAIL => 停止"; exit 1; }

echo "--- 2) 上传件 md5 (对端现读; 与仓内本地逐件比) ---"
$SSH "cd /tmp/p7b_biz && md5sum p7b_affinity.h p7b_io.h p7b_spsc.h p7b_pattern.h p7b_tcp_sink.cpp p7b_tcp_src.cpp p7b_udp_src.cpp p7b_rate2_bench.cpp p7b_mir_dump.cpp p7b_snap.sh p7b_selftest.sh p7b_dualthread_selftest.sh p7b_lane8_selftest.sh aff_selftest.sh p7b_tcp_src_fix.cpp p7b_tcp_src_diag.cpp tcpreg_j6.sh p7b_tcp_src_rate.cpp p7b_tcp_sink_rate.cpp pcap_off_dryrun.sh align_check2_fixed.py split_conn_pcap.py k0_arm_b4.sh k0_analyze.sh"

echo "--- 3) 编译 9 个产物 (g++ -O3 -pthread) ---"
$SSH "cd /tmp/p7b_biz && for n in p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench p7b_mir_dump; do g++ -O3 -pthread -o \$n \$n.cpp 2>&1 | sed \"s/^/  [\$n] /\"; [ -x \$n ] || echo COMPILE_FAIL \$n; done; echo COMPILE_DONE_RC=\$?"

echo "--- 4) 产物 md5 + 字节数 (对 B1 §2.1 表逐条自验) ---"
$SSH "cd /tmp/p7b_biz && md5sum p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench p7b_mir_dump; stat -c '%n %s' p7b_tcp_sink p7b_tcp_src p7b_udp_src p7b_tcp_src_fix p7b_tcp_sink_rate p7b_tcp_src_rate p7b_tcp_src_diag p7b_rate2_bench p7b_mir_dump"

echo "--- 5) 板外自检 5 项 (都不碰板子) ---"
$SSH "cd /tmp/p7b_biz && bash p7b_selftest.sh 18901 2>&1 | tail -4; echo SELFTEST_RC=\$?"
$SSH "cd /tmp/p7b_biz && bash p7b_dualthread_selftest.sh 18902 2>&1 | tail -3; echo DUAL_RC=\$?"
$SSH "cd /tmp/p7b_biz && bash p7b_lane8_selftest.sh 18903 2>&1 | tail -3; echo LANE8_RC=\$?"
$SSH "cd /tmp/p7b_biz && SKIP_NET=1 bash aff_selftest.sh 2>&1 | tail -3; echo AFF_RC=\$?"
$SSH "cd /tmp/p7b_biz && bash pcap_off_dryrun.sh 2>&1 | tail -3; echo PCDRY_RC=\$?"
$SSH "cd /tmp/p7b_biz && python3 align_check2_fixed.py 2>&1 | head -2; echo ALIGN2_NOARG_RC=\$?"
$SSH "cd /tmp/p7b_biz && bash -n k0_arm_b4.sh && echo K0ARM_B4_SYNTAX_OK; bash -n k0_analyze.sh && echo K0AN_SYNTAX_OK"

echo "=== DEPLOY_END $(date +%s.%N) ==="
