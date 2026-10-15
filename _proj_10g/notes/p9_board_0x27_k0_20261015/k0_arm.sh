#!/bin/bash
# k0_arm.sh -- K0 判据单臂执行件（对端机；板->对端 TCP 8080 下行流 + 板侧快照环 + 环形全帧抓包）
#   依据 = `p9_fix_upok_design_20261014/DESIGN_v2.md` §5.2（S2/S3 最小实验）+ S-0 的 run_s0.sh 骨架
#   用法: bash k0_arm.sh <TAG> <RCVBUF> <CONNS> <SECS> <MAXBYTES> [RING_C_MB RING_W] [SINK_EXTRA]
#   臂身份: EXPECT_BID 环境变量（正臂 = 0x00000027 / 负对照臂 = 0x00000024）
#   ⚠️ 快照环 kw = 5 20 43 51 52 14 15 55 57 58（0x27 几何 71 字全含；W51 = app 下行载荷字节）
#
#   三条"抓包正确性"硬门（2026-10-15 首跑实测补齐 —— 缺任一 ⇒ K0 读数不可用）:
#     ① **arming 门**: 等 stderr 出现 `listening on` 才开跑（首跑：arm 后 ~30 ms 就开跑 ⇒
#        丢了流的**头 4 段** ⇒ K0 被读成 5840，而 sink 自报 first_mismatch=-1 = S-0 的 M-1 伪影同族）
#     ② **优雅停**: `kill -INT` + 等退出（首跑：kill setsid pid 无效 ⇒ 尾部 ~130 包滞留）
#     ③ **丢包门**: tcpdump 自报 `dropped by kernel` 必须 = 0 且 captured == received（否则 = 流有洞）
#     ⚠️ 相对 S-0 run_s0.sh 的口径差异: 去掉 `-U`（逐包写盘会拖速；改为 SIGINT 优雅 flush）、
#        buffer -B 65536 → 262144 KiB（S3 可到 ~9 Gbps）
set -u
TAG=${1:?usage: k0_arm.sh TAG RCVBUF CONNS SECS MAXBYTES [RING_C RING_W] [SINK_EXTRA]}
RCVBUF=${2:?}; CONNS=${3:?}; SECS=${4:?}; MAXBYTES=${5:?}; RING_C=${6:-300}; RING_W=${7:-8}; SINK_EXTRA=${8:-}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
KW='5 20 43 51 52 14 15 55 57 58'
export EXPECT_BID=${EXPECT_BID:-0x00000027} NW=${NW:-71}

# ---- 前置硬门 (血泪: 首跑用非 root ⇒ 日志写不进/空读数; 且 `fs.protected_regular` 会让后来的 root 也
#      写不进**别人拥有的**旧 /tmp 文件 ⇒ 本脚本一律 root 跑 + 先清自己的命名空间) ----
[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root ⇒ tcpdump/reg_rw 全禁 (跑法: peer_ssh.py --sudo 'bash k0_arm.sh ...')"; exit 3; }
rm -f /tmp/k0_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL 清不掉 /tmp/k0_${TAG}_* (别人拥有?)"; exit 3; }

arm_tcpdump(){  # arm_tcpdump <stderr 文件>  —— 等 'listening on' (判据), 15 s 超时 = 硬失败
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $f (waited ~$((t/10))s)"; return 0; }
    sleep 0.1; t=$((t+1))
  done
  echo "TCPDUMP_ARM_FAIL 15s 未见 'listening on': $f"; return 1
}
stop_tcpdump(){  # stop_tcpdump <pid> <name>  —— SIGINT 优雅停 + 等退出 (flush 判据的载体)
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
grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_CONN|^SINK_SUM' /tmp/k0_${TAG}_sink.txt | head -40

echo "--- 板侧态 (跑后) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(空=无残留进程)"
echo "### K0_END tag=$TAG $(date +%s.%N)"
