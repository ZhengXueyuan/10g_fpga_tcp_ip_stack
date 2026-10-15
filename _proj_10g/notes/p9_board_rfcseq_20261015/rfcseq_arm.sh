#!/bin/bash
# rfcseq_arm.sh -- B2 单臂执行件（对端机；peer->board 上行流 + SIGSTOP 冻结 + 注入 A/B + 板侧快照 + 静默窗抓包）
#   依据 = 设计件 v3r3 §7.2（本目录 EXEC_PLAN.md 为其执行清单）
#   用法: EXPECT_BID=0x00000027 bash rfcseq_arm.sh <TAG> [MAX_ATTEMPT]
#   臂身份: EXPECT_BID 环境变量（P27 = 0x27 / N25 = 0x25 / P26 = 0x26）
#
#   三条"抓包正确性"硬门（沿用 B1 教训）: ① arming 门（等 `listening on`）
#     ② 优雅停（kill -INT + 等退出） ③ 丢包门（tcpdump 自报 captured==received 且 dropped=0）
#   ⚠️ 与 B1 的口径差异（已登记）: 本轮主抓包 = **静默窗**（-s 96, 注入前后），非全窗环形。
set -u
TAG=${1:?usage: rfcseq_arm.sh TAG [MAX_ATTEMPT]}
MAXATT=${2:-4}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
BIN=/tmp/p7b_biz
ROUND=/tmp/rfcseq_${TAG}
INJPY=/tmp/rfcseq_tools/rfcseq_inject.py
KW='1 5 20 22 23 51 52 53 54 55 68 70'
FLOW_S=2
export EXPECT_BID=${EXPECT_BID:-0x00000027} NW=${NW:-71}

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root ⇒ tcpdump/reg_rw/AF_PACKET 全禁"; exit 3; }
mkdir -p $ROUND
rm -f ${ROUND}/* 2>/dev/null
echo "### RFCSEQ_ARM_BEGIN tag=$TAG expect_bid=$EXPECT_BID $(date +%s.%N) $(date)"

arm_wait(){  # arm_wait <stderr 文件> —— 等 'listening on'（15 s 超时 = 硬失败）
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $(basename $f) (~$((t/10))s)"; return 0; }
    sleep 0.1; t=$((t+1))
  done
  echo "TCPDUMP_ARM_FAIL 15s 未见 'listening on': $f"; return 1
}
stop_tcpdump(){
  local p=$1 n=$2 i=0
  kill -INT "$p" 2>/dev/null
  while [ $i -lt 150 ]; do kill -0 "$p" 2>/dev/null || { echo "$n STOPPED_GRACEFULLY (~$((i/10))s)"; return 0; }; sleep 0.1; i=$((i+1)); done
  echo "$n 未在 15 s 内退出 ⇒ KILL -9"; kill -9 "$p" 2>/dev/null; return 1
}

echo "--- 前置: 身份闸 + 通道 ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier; echo
echo -n "NETADDR="; ip -4 addr show $IF | grep -o 'inet [0-9./]*'
echo -n "ROUTE_GET="; ip route get $BOARD | head -1
echo -n "NEIGH="; ip neigh show $BOARD
pgrep -af '[p]7b_tcp_src|[t]cpdump|[r]fcseq_inject' || echo "NO_STALE_PROCS"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')  SRC_MD5 $(md5sum $BIN/p7b_tcp_src | awk '{print $1}')"
echo "### INJ_MD5 $(md5sum $INJPY | awk '{print $1}')"
echo "### TCPDUMP $(tcpdump --version 2>/dev/null | head -1)"

echo "--- 对端内核计数 (跑前) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtTCPACKSkippedChallenge) ' > $ROUND/nstat_pre.txt
cat $ROUND/nstat_pre.txt

echo "--- 快照 S_pre ---"
bash $S snap ${TAG}_pre $KW 2>&1 | tee $ROUND/snap_pre.txt

ATT=1
INJ_RC=99
while [ $ATT -le $MAXATT ]; do
  echo "=== ATTEMPT $ATT $(date +%s.%N) ==="
  # --- SYN 捕获 (独立见证: 连接建立时的 ISN; 在 src 之前 arm) ---
  rm -f $ROUND/syn_$ATT.pcap
  nohup tcpdump -i $IF -s 96 -c 1 -w $ROUND/syn_$ATT.pcap \
     "tcp and dst host $BOARD and dst port 8080 and tcp[tcpflags] & (tcp-syn|tcp-ack) == tcp-syn" \
     </dev/null > $ROUND/syn_$ATT.err 2>&1 &
  SYNPID=$!
  arm_wait $ROUND/syn_$ATT.err || exit 4
  # --- 源头 (peer->board 上行数据流) ---
  nohup $BIN/p7b_tcp_src --host $BOARD --port 8080 --seconds 300 \
     > $ROUND/src_$ATT.txt 2>&1 &
  SRCPID=$!
  echo "SRC_PID=$SRCPID"
  for i in $(seq 1 50); do grep -q '^SRC_CONNECTED' $ROUND/src_$ATT.txt 2>/dev/null && break; sleep 0.1; done
  grep -q '^SRC_CONNECTED' $ROUND/src_$ATT.txt || { echo "SRC_CONNECT_FAIL (attempt $ATT)"; cat $ROUND/src_$ATT.txt; kill -9 $SRCPID 2>/dev/null; ATT=$((ATT+1)); continue; }
  echo "SRC_CONNECTED ok ($(grep -m1 '^SRC_CONNECTED' $ROUND/src_$ATT.txt))"
  sleep $FLOW_S
  # --- 主抓包 (静默窗 + 注入窗; 两向) ---
  rm -f $ROUND/main_$ATT.pcap
  nohup tcpdump -U -i $IF -s 96 -B 65536 -w $ROUND/main_$ATT.pcap \
     "tcp and host $BOARD and port 8080" </dev/null > $ROUND/main_$ATT.err 2>&1 &
  MAINPID=$!
  arm_wait $ROUND/main_$ATT.err || { kill -9 $SRCPID; exit 4; }
  # --- 注入器 (fg; 内部会 SIGSTOP 源头) ---
  python3 $INJPY --stop-pid $SRCPID 2>&1 | tee $ROUND/inject_$ATT.txt
  INJ_RC=${PIPESTATUS[0]}
  echo "### INJECT_RC=$INJ_RC attempt=$ATT"
  grep -E '^(DISCOVER|SYNC_CHECK|SELFCHECK|INFEASIBLE|QUIET_ENTER|INJECT|POST_INJECT_BOARD_FRAME|OBS_SUMMARY|SUMMARY|INJ_DONE|WARN_)' $ROUND/inject_$ATT.txt > $ROUND/inject_$ATT.key.txt
  stop_tcpdump $MAINPID main
  echo "[main pcap 自报]"; tail -3 $ROUND/main_$ATT.err
  # --- 快照 S_post (每次尝试后都取; RC=3 时也要) ---
  bash $S snap ${TAG}_post_$ATT $KW 2>&1 | tee $ROUND/snap_post_$ATT.txt
  kill -9 $SRCPID 2>/dev/null
  sleep 0.3
  grep -E '^(SRC_SUM|SRC_DRAIN|SRC_EOF)' $ROUND/src_$ATT.txt | tail -3
  if [ "$INJ_RC" = "0" ]; then break; fi
  if [ "$INJ_RC" = "3" ]; then echo "INFEASIBLE ⇒ 重开连接 (attempt $ATT/$MAXATT)"; ATT=$((ATT+1)); continue; fi
  echo "INJECT_HARD_FAIL rc=$INJ_RC ⇒ 停止"; break
done

echo "--- 对端内核计数 (跑后) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtTCPACKSkippedChallenge) ' > $ROUND/nstat_post.txt
cat $ROUND/nstat_post.txt

echo "--- 收尾态 ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier; echo
pgrep -af '[p]7b_tcp_src|[t]cpdump|[r]fcseq_inject' || echo "NO_STALE_PROCS_END"
ls -la $ROUND/
sha256sum $ROUND/*.pcap 2>&1
echo "### RFCSEQ_ARM_END tag=$TAG INJ_RC=$INJ_RC attempts=$ATT $(date +%s.%N)"
