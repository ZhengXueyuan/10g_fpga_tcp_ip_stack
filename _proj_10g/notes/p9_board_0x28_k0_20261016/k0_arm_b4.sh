#!/bin/bash
# k0_arm_b4.sh -- B4 轮 K0 单臂执行件 (对端机; 板->对端 TCP 8080 下行流 + 板侧快照环 + 环形全帧抓包)
#   母本 = B1 轮 k0_arm.sh (逐字保留其三条"抓包正确性"硬门: arming / 优雅停 / 丢包门)
#   B4 差异 (三处, 明示):
#     ① KW 加 **71 72 73 74** (E12 四观测计数器) + 11 (app_rx_bytes 参照)
#     ② 默认 EXPECT_BID/NW = **0x00000028 / 75** (B1 件默认 0x27/71 ⇒ 跑本件不必 export)
#     ③ 新增显式 **SNAP_PRE / SNAP_POST** 两读 (W71..74 + W51/W20 对账字) —— 快照环 (0.15s)
#        照跑; 两读用于"事件计数在跑窗内的净增量"(快照环的末点可能早于 sink 收尾)
#   用法: bash k0_arm_b4.sh <TAG> <RCVBUF> <CONNS> <SECS> <MAXBYTES> [RING_C_MB RING_W] [SINK_EXTRA]
set -u
TAG=${1:?usage: k0_arm_b4.sh TAG RCVBUF CONNS SECS MAXBYTES [RING_C RING_W] [SINK_EXTRA]}
RCVBUF=${2:?}; CONNS=${3:?}; SECS=${4:?}; MAXBYTES=${5:?}; RING_C=${6:-300}; RING_W=${7:-8}; SINK_EXTRA=${8:-}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
KW='5 20 43 51 52 14 15 55 57 58 71 72 73 74'
KW2='71 72 73 74 51 20 43 5'   # SNAP_PRE/POST 的显式子集 (事件四字 + 对账两字 + 时钟 + 帧数)
export EXPECT_BID=${EXPECT_BID:-0x00000028} NW=${NW:-75}

# ---- 前置硬门 (B1 血泪: 非 root ⇒ 日志写不进/空读数; fs.protected_regular 让后来 root 也写不进别人拥有的旧 /tmp 件) ----
[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root ⇒ tcpdump/reg_rw 全禁 (跑法: peer_ssh.py --sudo 'bash k0_arm_b4.sh ...')"; exit 3; }
rm -f /tmp/k0_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL 清不掉 /tmp/k0_${TAG}_* (别人拥有?)"; exit 3; }

arm_tcpdump(){  # 等 'listening on' (判据), 15 s 超时 = 硬失败
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $f (waited ~$((t/10))s)"; return 0; }
    sleep 0.1; t=$((t+1))
  done
  echo "TCPDUMP_ARM_FAIL 15s 未见 'listening on': $f"; return 1
}
stop_tcpdump(){  # SIGINT 优雅停 + 等退出 (flush 判据的载体)
  local p=$1 n=$2 i=0
  kill -INT "$p" 2>/dev/null
  while [ $i -lt 150 ]; do kill -0 "$p" 2>/dev/null || { echo "$n STOPPED_GRACEFULLY (~$((i/10))s)"; return 0; }; sleep 0.1; i=$((i+1)); done
  echo "$n 未在 15 s 内退出 ⇒ KILL -9"; kill -9 "$p" 2>/dev/null; return 1
}

echo "### K0_BEGIN tag=$TAG rcvbuf=$RCVBUF conns=$CONNS secs=$SECS maxbytes=$MAXBYTES ring=${RING_C}MBx${RING_W} sink_extra='$SINK_EXTRA' $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINK_MD5 $(md5sum /tmp/p7b_biz/p7b_tcp_sink | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID KW='$KW'"
echo "### TCPDUMP $(tcpdump --version 2>/dev/null | head -1)"

echo "--- 板侧身份闸 (跑前) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "NETADDR="; ip -4 addr show $IF | grep -o 'inet [0-9./]*'
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- 抓包 ①: 控制帧普查 (FIN/RST, 全窗; 音量极小) ---"
nohup tcpdump -i $IF -s 0 -w /tmp/k0_${TAG}_ctl.pcap \
   "tcp port 8080 and (tcp[tcpflags] & (tcp-fin|tcp-rst) != 0)" \
   </dev/null > /tmp/k0_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/k0_${TAG}_ctl.err || exit 4

echo "--- 抓包 ②: 环形全帧 (板->对端) ---"
rm -f /tmp/k0_${TAG}_full*
nohup tcpdump -i $IF -s 0 -B 262144 -C $RING_C -W $RING_W -w /tmp/k0_${TAG}_full.pcap \
   "tcp port 8080 and src host $BOARD" </dev/null > /tmp/k0_${TAG}_full.err 2>&1 &
FULLPID=$!
arm_tcpdump /tmp/k0_${TAG}_full.err || exit 4
echo "FULL_PID=$FULLPID CTL_PID=$CTLPID"

echo "--- 板侧快照环 (后台; 每 0.15s 一点) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/k0_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- 对端内核计数 (跑前) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_pre.txt
cat /tmp/k0_${TAG}_nstat_pre.txt

echo "--- ⭐ SNAP_PRE (显式; 事件四计数器 + 对账字) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/k0_${TAG}_pre.txt
echo "PRE_RC=$?"

echo "--- 主跑: sink (现役部署件; --check lane8) ---"
T0=$(date +%s.%N)
timeout -k 5 $((SECS+180)) /tmp/p7b_biz/p7b_tcp_sink --host $BOARD --port 8080 \
  --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
  > /tmp/k0_${TAG}_sink.txt 2>&1
RC=$?
T1=$(date +%s.%N)
echo "### SINK_RC=$RC T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
# 新鲜度硬门: 日志必须是本次写的且跑到底 (坑: 陈旧日志被当成新读数 —— 全局 #72 同族)
if [ ! -s /tmp/k0_${TAG}_sink.txt ]; then echo "SINK_LOG_EMPTY => 停止"; exit 4; fi
grep -q '^SINK_SUM' /tmp/k0_${TAG}_sink.txt || echo "SINK_SUM_MISSING (跑未到底; RC=$RC)"

echo "--- ⭐ SNAP_POST (显式; sink 退出后立即) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/k0_${TAG}_post.txt
echo "POST_RC=$?"

echo "--- 对端内核计数 (跑后) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_post.txt
cat /tmp/k0_${TAG}_nstat_post.txt

echo "--- 收尾: 停快照环 + 抓包 (SIGINT 优雅停) ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $FULLPID full
stop_tcpdump $CTLPID ctl

echo "--- 抓包统计 (tcpdump 自报; 丢包/缺包 = 判据污染的见证) ---"
echo "[ctl]";  tail -3 /tmp/k0_${TAG}_ctl.err
echo "[full]"; tail -3 /tmp/k0_${TAG}_full.err
ls -la /tmp/k0_${TAG}_*.pcap* 2>&1
sha256sum /tmp/k0_${TAG}_*.pcap* 2>&1

echo "--- sink 摘要 (逐字) ---"
grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_CONN|^SINK_SUM' /tmp/k0_${TAG}_sink.txt | head -60

echo "--- 板侧态 (跑后) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(空=无残留进程)"
echo "### K0_END tag=$TAG $(date +%s.%N)"
