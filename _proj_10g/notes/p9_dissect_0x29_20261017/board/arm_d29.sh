#!/bin/bash
# arm_d29.sh -- 0x29 拆刀轮: S-0 LEGACY 构型执行件 (同锚复跑件)
#   母本 = p9_s0bisect_board_20261016/_tools/arm_s0.sh (逐字保留其三条抓包硬门 + 身份闸 + NIC 见证)
#   本轮差异 (四处, 明示):
#     ① sink 二进制改为**同锚件** /tmp/d29_p7b_tcp_sink_6d9b14f2
#        (md5 必须 = 6d9b14f24725fa326ffe5b169f77e30f = bisect 轮 TABLE 的 SINK_MD5;
#         现役 /tmp/p7b_biz/p7b_tcp_sink = f6229929 (sinkdelta 新件) -- 不用它, 见 SUMMARY)
#     ② TAG 前缀文件 /tmp/d29_${TAG}_* (派单文件所有权: 对端只写 d29_*)
#     ③ 新增 ### SINKBIN_MD5 见证行
#     ④ 其余 (KW / 参数 / 判据 / 顺序) 逐字同 arm_s0.sh
#   用法: EXPECT_BID=0x... NW=.. UNIMPL_ADDR=0x.. bash arm_d29.sh <TAG> <RCVBUF> <CONNS> <SECS> <MAXBYTES> [RING_C RING_W SINK_EXTRA]
set -u
TAG=${1:?usage: arm_d29.sh TAG RCVBUF CONNS SECS MAXBYTES [RING_C RING_W SINK_EXTRA]}
RCVBUF=${2:?}; CONNS=${3:?}; SECS=${4:?}; MAXBYTES=${5:?}; RING_C=${6:-200}; RING_W=${7:-6}; SINK_EXTRA=${8:-}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
SINK_BIN=${SINK_BIN:-/tmp/d29_p7b_tcp_sink_6d9b14f2}
KW='5 20 43 51 14 15 55 57 58'
KW2='43 51 20 5 14 15'
P=/tmp/d29_${TAG}
export EXPECT_BID=${EXPECT_BID:?arm_d29.sh: 需要 EXPECT_BID (该代 BID)}
export NW=${NW:?arm_d29.sh: 需要 NW (该代快照字长)}
export UNIMPL_ADDR=${UNIMPL_ADDR:?arm_d29.sh: 需要 UNIMPL_ADDR (该代未实现地址: 70字=0x138 / 71字=0x14C / 75字=0x15C)}

# ---- 前置硬门 (B1 血泪: 非 root => 日志写不进/空读数) ----
[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root (跑法: peer_ssh.py --sudo)"; exit 3; }
[ -x "$SINK_BIN" ] || { echo "PRECHECK_FAIL sink 不存在/不可执行: $SINK_BIN"; exit 3; }
rm -f ${P}_* 2>/dev/null || { echo "PRECHECK_FAIL 清不掉 ${P}_*"; exit 3; }

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
  echo "$n 未在 15 s 内退出 => KILL -9"; kill -9 "$p" 2>/dev/null; return 1
}

echo "### D29_BEGIN tag=$TAG rcvbuf=$RCVBUF conns=$CONNS secs=$SECS maxbytes=$MAXBYTES ring=${RING_C}MBx${RING_W} sink_extra='$SINK_EXTRA' $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINKBIN=$SINK_BIN"
echo "### SINK_MD5 $(md5sum $SINK_BIN | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID UNIMPL_ADDR=$UNIMPL_ADDR KW='$KW'"
echo "### TCPDUMP $(tcpdump --version 2>/dev/null | head -1)"

echo "--- 板侧身份闸 (跑前) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "NETADDR="; ip -4 addr show $IF | grep -o 'inet [0-9./]*'
echo -n "ROUTE_GET="; ip route get $BOARD | head -1
echo -n "ADAPTIVE_RX="; ethtool -c $IF 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | tr '\n' ' '; echo
echo -n "NM_MANAGED="; nmcli device show $IF 2>/dev/null | grep -i 'managed' || echo '(nmcli 无输出)'
echo "--- NIC 硬件计数 (跑前) ---"
ethtool -S $IF 2>/dev/null | grep -E '^ +(port_rx_good_bytes|port_rx_packets|port_rx_bad|rx_eth_crc_err|rx_nodesc_drops):' | tee ${P}_nicpre.txt

echo "--- 抓包 ①: 控制帧普查 (FIN/RST, 全窗) ---"
nohup tcpdump -i $IF -s 0 -w ${P}_ctl.pcap \
   "tcp port 8080 and (tcp[tcpflags] & (tcp-fin|tcp-rst) != 0)" \
   </dev/null > ${P}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump ${P}_ctl.err || exit 4

echo "--- 抓包 ②: 环形全帧 (板->对端) ---"
rm -f ${P}_full*
nohup tcpdump -i $IF -s 0 -B 262144 -C $RING_C -W $RING_W -w ${P}_full.pcap \
   "tcp port 8080 and src host $BOARD" </dev/null > ${P}_full.err 2>&1 &
FULLPID=$!
arm_tcpdump ${P}_full.err || exit 4
echo "FULL_PID=$FULLPID CTL_PID=$CTLPID"

echo "--- 板侧快照环 (后台; 每 0.15s 一点) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > ${P}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- 对端内核计数 (跑前) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > ${P}_nstat_pre.txt
cat ${P}_nstat_pre.txt

echo "--- ⭐ SNAP_PRE (显式) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee ${P}_pre.txt
echo "PRE_RC=$?"

echo "--- 主跑: sink (S-0 构型; --check lane8) ---"
T0=$(date +%s.%N)
timeout -k 5 $((SECS+240)) $SINK_BIN --host $BOARD --port 8080 \
  --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
  > ${P}_sink.txt 2>&1
RC=$?
T1=$(date +%s.%N)
echo "### SINK_RC=$RC T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
if [ ! -s ${P}_sink.txt ]; then echo "SINK_LOG_EMPTY => 停止"; exit 4; fi
grep -q '^SINK_SUM' ${P}_sink.txt || echo "SINK_SUM_MISSING (跑未到底; RC=$RC)"

echo "--- ⭐ SNAP_POST (显式; sink 退出后立即) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee ${P}_post.txt
echo "POST_RC=$?"

echo "--- 对端内核计数 (跑后) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > ${P}_nstat_post.txt
cat ${P}_nstat_post.txt

echo "--- 收尾: 停快照环 + 抓包 (SIGINT 优雅停) ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $FULLPID full
stop_tcpdump $CTLPID ctl

echo "--- 抓包统计 (tcpdump 自报; 丢包/缺包 = 判据污染的见证) ---"
echo "[ctl]";  tail -3 ${P}_ctl.err
echo "[full]"; tail -3 ${P}_full.err
ls -la ${P}_*.pcap* 2>&1
sha256sum ${P}_*.pcap* 2>&1

echo "--- NIC 硬件计数 (跑后) ---"
ethtool -S $IF 2>/dev/null | grep -E '^ +(port_rx_good_bytes|port_rx_packets|port_rx_bad|rx_eth_crc_err|rx_nodesc_drops):' | tee ${P}_nicpost.txt

echo "--- sink 摘要 (逐字) ---"
grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_CONN|^SINK_SUM' ${P}_sink.txt | head -60

echo "--- 板侧态 (跑后) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(空=无残留进程)"
echo "### D29_END tag=$TAG $(date +%s.%N)"
