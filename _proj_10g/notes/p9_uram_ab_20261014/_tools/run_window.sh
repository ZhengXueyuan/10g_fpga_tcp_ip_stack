#!/bin/bash
# run_window.sh <TAG> <NPROC> <EXPECT_BID> -- P9 URAM A/B 轮单窗驱动 (对端 root 起; /dev/xdma* 是 root-only)
#   构型 (与 0x24 板级轮主臂同构型): K=1GiB · chunk 4MiB · --dual 2 · unpaced(MBPS=0) · --src udp ·
#     --readlog 1 · --no-verify · SECS=6 · SAMPLE_MS=1000 · BUFMB=1024 · FIXOFF=0 · NW=71
#   TOOL = /tmp/p7b_biz/p7b_mir_dump (修复版; 每窗 stdout 有 TOOL_MD5= 现取行, 不符即停并如实报)
#   NPROC=1 => S 臂 (单源) ; NPROC=4 => F 臂 (4 源)
#   产物: runs/WIN_<TAG>_<ts>.txt (= 窗口完整 stdout) + RUNLOG_<TAG>_<ts>.txt (驱动转录)
#   用法: PEER_PW=<pw> bash run_window.sh S_A1 1 0x00000023
set -u
TAG=${1:?tag}
NPROC=${2:?nproc}
BID=${3:?expect_bid}
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_uram_ab_20261014
OUTW=$ROOTW/_proj_10g/notes/p9_uram_ab_20261014
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
RD=/tmp/p9_uram_ab
WANT_TOOL_MD5=48dcbcb26a4db45f576fc9664638a089
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT/runs"
WINLOG=$OUT/runs/WIN_${TAG}_${TS}.txt
LOGD=$OUT/runs/RUNLOG_${TAG}_${TS}.txt
exec > >(tee "$LOGD") 2>&1

echo "=== RUN_WINDOW TAG=$TAG NPROC=$NPROC BID=$BID $(date +%s.%N) $(date)"
echo "--- 工具指纹现取 ---"
$SSH "md5sum /tmp/p7b_biz/p7b_mir_dump $RD/p7b_udp_src $RD/run_win_hw.sh 2>&1; echo -n 'CARRIER_NOW='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- 启动窗口 (对端 root, 后台 + 轮询) ---"
CMD="cd $RD && nohup env D=$RD TAG=$TAG K=1073741824 MBPS=0 PAYLEN=1472 BATCH=32 SECS=6 SAMPLE_MS=1000 CHUNK=4194304 READLOG=1 AIO=0 DUAL=2 BUFMB=1024 FIXOFF=0 DECL=--no-verify NPROC=$NPROC NW=71 EXPECT_BID=$BID TOOL=/tmp/p7b_biz/p7b_mir_dump OUT=/dev/null bash run_win_hw.sh > win_${TAG}.log 2>&1 & echo LAUNCHED_PID=\$!"
$SSH --sudo "$CMD"
sleep 10
DONE=0
for i in $(seq 1 40); do
  R=$($SSH --sudo "tail -c 400 $RD/win_${TAG}.log 2>/dev/null | tr -d '\r' | tail -3; echo '---'; grep -c '^=== END ${TAG}' $RD/win_${TAG}.log 2>/dev/null || echo 0")
  echo "[poll $i $(date +%s)] $R"
  case "$R" in *"=== END"*) DONE=1;; esac
  [ "$DONE" = "1" ] && break
  sleep 12
done
if [ "$DONE" != "1" ]; then
  echo "WINDOW_TIMEOUT_or_HANG tag=$TAG (未看到 '=== END'); 停在现场, 不重启"
fi
echo "--- 取回窗口 stdout + 原始日志 ---"
$SSH --sudo "ls -la $RD/win_${TAG}.log $RD/mir_${TAG}.log $RD/rstat_${TAG}.log 2>&1; ls -la $RD/src_${TAG}_p*.log 2>&1"
$SSH --sudo "cat $RD/win_${TAG}.log" > "$WINLOG" 2>&1
sync
echo "--- 窗口 stdout 已归档: $WINLOG ($(wc -c < "$WINLOG") B) ---"
echo "--- 原始件取回 (mir/rstat/src) ---"
$PY $ROOTW/tools/peer_ssh.py --get "$RD/mir_${TAG}.log" "$OUTW/runs/mir_${TAG}_${TS}.log" 2>&1
$PY $ROOTW/tools/peer_ssh.py --get "$RD/rstat_${TAG}.log" "$OUTW/runs/rstat_${TAG}_${TS}.log" 2>&1
for p in $(seq 1 "$NPROC"); do
  $PY $ROOTW/tools/peer_ssh.py --get "$RD/src_${TAG}_p${p}.log" "$OUTW/runs/src_${TAG}_p${p}_${TS}.log" 2>&1
done
echo "--- 关键读数摘 (现取) ---"
grep -aE "^TOOL_MD5=|^CARRIER_PRE=|^SRC_RC=|^TOOL_RC=|^MIR_ID |^MIR_STREAM_ACCT |^MIR_STREAM_IDA |^MIR_STREAM_IDB |^MIR_STREAM_GAP |^MIR_STREAM_DONE |^MIR_STREAM_QUIESCE |host_miss_pct|^NIC_PRE:|^READER_CPU|^OFF_FIX" "$WINLOG" | head -30
echo "TOOL_MD5_EXPECT=$WANT_TOOL_MD5"
if grep -aq "^TOOL_MD5=" "$WINLOG"; then
  GOT=$(grep -am1 '^TOOL_MD5=' "$WINLOG" | cut -d= -f2)
  [ "$GOT" = "$WANT_TOOL_MD5" ] && echo "TOOL_MD5_MATCH=yes" || echo "TOOL_MD5_MATCH=no (GOT=$GOT)"
else
  echo "TOOL_MD5_LINE_MISSING"
fi
echo "=== RUN_WINDOW_END TAG=$TAG $(date +%s.%N)"
