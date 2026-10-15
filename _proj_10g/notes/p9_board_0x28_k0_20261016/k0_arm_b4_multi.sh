#!/bin/bash
# k0_arm_b4_multi.sh -- B4 轮 高密度换流构型执行件 (NSINKS 个 sink **并行**、彼此**错开** STAGGER 秒)
#   动机 (实测): 单 sink 的连接是**顺序**的 (sink 源码 :353 for c in conns: connect→读满→close→下一个)
#     ⇒ 上一个连接的 ev_down 先于下一个连接的 ev_up ⇒ app 恒 idle ⇒ Δsw_req+Δup_pend=0
#     (B4P_S2/S3 实测逐条为 0) ⇒ 顺序构型**结构性地**碰不到触发面。
#   并行错开 = 让"下一个连接的 SYN/ADD"落在"上一个连接仍在服务"的窗口里 ⇒ ev_up 命中 active
#     ⇒ Δup_pend (异槽存活) 或 Δsw_req (同槽存活)。
#   ⚠️ 错开的理由 (不是装饰): up_pend_id 是**单寄存器、后写胜** ⇒ 同时到达的事件互相覆盖会饿死先到的
#     连接 (sink 侧表现为 STALL)。错开 ~0.3-1 s 保证在途连接 ≤ 2 (服务中的 + 一个 pending)。
#   三条抓包硬门与单臂件逐字相同 (arming / 优雅停 / 丢包门); 快照环 + 显式 PRE/POST 同单臂件。
#   用法: bash k0_arm_b4_multi.sh <TAG> <NSINKS> <STAGGER_S> <RCVBUF> <CONNS> <SECS> <MAXBYTES> [RING_C RING_W]
set -u
TAG=${1:?usage: k0_arm_b4_multi.sh TAG NSINKS STAGGER RCVBUF CONNS SECS MAXBYTES [RING_C RING_W]}
NSINKS=${2:?}; STAGGER=${3:?}; RCVBUF=${4:?}; CONNS=${5:?}; SECS=${6:?}; MAXBYTES=${7:?}; RING_C=${8:-300}; RING_W=${9:-8}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
# KW/KW2 可经环境覆盖 (0x24 臂: 无 E12 四字, 且 0x13C..0x148 在 0x24 几何里是 MIR 四字 ⇒ 必须去掉)
KW=${KW:-'5 20 43 51 52 14 15 55 57 58 71 72 73 74'}
KW2=${KW2:-'71 72 73 74 51 20 43 5'}
SINK_EXTRA=${SINK_EXTRA:-}   # 例如 '--poll-ms 1000 --stall-n 3' (压缩 stall 时长)
export EXPECT_BID=${EXPECT_BID:-0x00000028} NW=${NW:-75}

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root"; exit 3; }
rm -f /tmp/k0_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL 清不掉 /tmp/k0_${TAG}_*"; exit 3; }

arm_tcpdump(){
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $f (waited ~$((t/10))s)"; return 0; }
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

echo "### K0M_BEGIN tag=$TAG nsinks=$NSINKS stagger=$STAGGER rcvbuf=$RCVBUF conns=$CONNS secs=$SECS maxbytes=$MAXBYTES ring=${RING_C}MBx${RING_W} $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINK_MD5 $(md5sum /tmp/p7b_biz/p7b_tcp_sink | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID KW='$KW'"

echo "--- 板侧身份闸 (跑前) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- 抓包 ①: 控制帧普查 ---"
nohup tcpdump -i $IF -s 0 -w /tmp/k0_${TAG}_ctl.pcap \
   "tcp port 8080 and (tcp[tcpflags] & (tcp-fin|tcp-rst) != 0)" \
   </dev/null > /tmp/k0_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/k0_${TAG}_ctl.err || exit 4

echo "--- 抓包 ②: 环形全帧 ---"
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

echo "--- ⭐ SNAP_PRE $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/k0_${TAG}_pre.txt

echo "--- 主跑: $NSINKS 个 sink 并行 (错开 ${STAGGER}s) ---"
T0=$(date +%s.%N)
SPIDS=()
for i in $(seq 1 $NSINKS); do
  timeout -k 5 $((SECS+180)) /tmp/p7b_biz/p7b_tcp_sink --host $BOARD --port 8080 \
    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
    > /tmp/k0_${TAG}_sink${i}.txt 2>&1 &
  SPIDS+=($!)
  echo "SINK${i}_START pid=${SPIDS[-1]} t=$(date +%s.%N)"
  [ "$i" -lt "$NSINKS" ] && sleep $STAGGER
done
RC_SUM=0
for i in $(seq 0 $((NSINKS-1))); do
  wait ${SPIDS[$i]}; R=${?}; RC_SUM=$((RC_SUM+R)); echo "SINK$((i+1))_RC=$R"
done
T1=$(date +%s.%N)
echo "### SINK_RC_SUM=$RC_SUM T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
for i in $(seq 1 $NSINKS); do
  [ -s /tmp/k0_${TAG}_sink${i}.txt ] || echo "SINK${i}_LOG_EMPTY"
  grep -q '^SINK_SUM' /tmp/k0_${TAG}_sink${i}.txt || echo "SINK${i}_SUM_MISSING"
done

echo "--- ⭐ SNAP_POST $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/k0_${TAG}_post.txt

echo "--- 对端内核计数 (跑后) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_post.txt

echo "--- 收尾: 停快照环 + 抓包 ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $FULLPID full
stop_tcpdump $CTLPID ctl

echo "--- 抓包统计 ---"
echo "[ctl]";  tail -3 /tmp/k0_${TAG}_ctl.err
echo "[full]"; tail -3 /tmp/k0_${TAG}_full.err
ls -la /tmp/k0_${TAG}_*.pcap* 2>&1
sha256sum /tmp/k0_${TAG}_*.pcap* 2>&1

echo "--- sink 摘要 (逐字) ---"
for i in $(seq 1 $NSINKS); do
  echo "== SINK $i =="
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_CONN|^SINK_SUM' /tmp/k0_${TAG}_sink${i}.txt
done

echo "--- 板侧态 (跑后) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(空=无残留进程)"
echo "### K0M_END tag=$TAG $(date +%s.%N)"
