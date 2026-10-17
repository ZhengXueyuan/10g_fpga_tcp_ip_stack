#!/bin/bash
# =============================================================================
# b2a_arm.sh -- p9_board_0x2A_20261017 peer-side arm runner
#
#   Usage: bash b2a_arm.sh <TAG> <GEN:0x28|0x2A> <MODE> [args...]
#     MODE = oneprobe | fast | orphan | basin | zerowin | churn
#
#   Env overrides:
#     DUR       observation window seconds (orphan/zerowin/basin/churn; default 140)
#     SECS      sink --seconds (default DUR+120)
#     MB        sink --maxbytes (default 2000000000)
#     RCVBUF    sink --rcvbuf (default 2920)
#     CONNS     sink --conns (default 1)
#     EXTRA     extra sink args (default empty)
#     RECOVER   1 = orphan mode also does RESUME_PROBE + new-connection test (0x2A arm)
#     SINK_BIN  default /tmp/p7b_biz/p7b_tcp_sink
#     CHURN     default /tmp/p7b_biz/p7b_tcp_churn
#     NW / EXPECT_BID / UNIMPL_ADDR / KW  (snapshot geometry; derived from GEN if unset)
#
#   Skeleton/vocabulary = p9_slowbasin_gc_20261017/tools/arm_basin.sh and
#   p9_c1_board_20261017/tools/c1_arm.sh (pcap hard gates, identity gate, snap ring,
#   nstat pre/post, RUN_TIMEOUT).  Peer-side artifact prefix = b2a_<TAG>_* only.
#   Snapshot tool = /tmp/b2a_snap.sh (76-word-capable read side, md5 pinned).
#   never touches QSPI (no burn here; see burn/burn_round_b2a.sh).
# =============================================================================
set -u
TAG=${1:?usage: b2a_arm.sh TAG GEN MODE [args...]}
GEN=${2:?}; MODE=${3:?}
shift 3
IF_=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/b2a_snap.sh
SINK_BIN=${SINK_BIN:-/tmp/p7b_biz/p7b_tcp_sink}
CHURN=${CHURN:-/tmp/p7b_biz/p7b_tcp_churn}
DUR=${DUR:-140}
SECS=${SECS:-$((DUR+120))}
MB=${MB:-2000000000}
RCVBUF=${RCVBUF:-2920}
CONNS=${CONNS:-1}
EXTRA=${EXTRA-}
RECOVER=${RECOVER:-0}
RING_C=${RING_C:-256}; RING_W=${RING_W:-4}
RUN_TIMEOUT=${RUN_TIMEOUT:-$((DUR+120))}

case "$GEN" in
  0x28) NW=${NW:-75}; EXPECT_BID=${EXPECT_BID:-0x00000028}; UNIMPL_ADDR=${UNIMPL_ADDR:-0x15C}
        KW=${KW:-'5 20 43 51 52 55 63 64 71 72 73 74'} ;;
  0x2A) NW=${NW:-76}; EXPECT_BID=${EXPECT_BID:-0x0000002A}; UNIMPL_ADDR=${UNIMPL_ADDR:-0x160}
        KW=${KW:-'5 20 43 51 52 55 63 64 71 72 73 74 75'} ;;
  *) echo "GEN must be 0x28 or 0x2A"; exit 3 ;;
esac
export NW EXPECT_BID UNIMPL_ADDR KW

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root"; exit 3; }
[ -x "$SINK_BIN" ] || { echo "PRECHECK_FAIL SINK_BIN $SINK_BIN"; exit 3; }
[ -f "$S" ] || { echo "PRECHECK_FAIL SNAP $S"; exit 3; }

echo "### B2A_BEGIN tag=$TAG gen=$GEN mode=$MODE dur=$DUR secs=$SECS mb=$MB rcvbuf=$RCVBUF conns=$CONNS recover=$RECOVER extra='$EXTRA' $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID UNIMPL=$UNIMPL_ADDR KW='$KW'"

echo "--- leftover precheck (must be empty) ---"
pgrep -a p7b_tcp_sink && { echo "PRECHECK_FAIL leftover p7b_tcp_sink"; exit 3; }
pgrep -a p7b_tcp_churn && { echo "PRECHECK_FAIL leftover p7b_tcp_churn"; exit 3; }
pgrep -a tcpdump && { echo "PRECHECK_FAIL leftover tcpdump"; exit 3; }
echo "LEFTOVER_CLEAN"
rm -f /tmp/b2a_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/b2a_${TAG}_*"; exit 3; }

arm_tcpdump(){
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $f (waited ~$((t/10))s)"; return 0; }
    sleep 0.1; t=$((t+1))
  done
  echo "TCPDUMP_ARM_FAIL 15s without 'listening on': $f"; return 1
}
stop_tcpdump(){
  local p=$1 n=$2 i=0
  kill -INT "$p" 2>/dev/null
  while [ $i -lt 150 ]; do kill -0 "$p" 2>/dev/null || { echo "$n STOPPED_GRACEFULLY (~$((i/10))s)"; return 0; }; sleep 0.1; i=$((i+1)); done
  echo "$n did not exit in 15 s => KILL -9"; kill -9 "$p" 2>/dev/null; return 1
}
port_of(){
  ss -tinH state established "( dport = :8080 )" 2>/dev/null | grep -oE '192\.168\.100\.100:[0-9]+' | head -1 | cut -d: -f2
}
bytes_of(){
  # $1 = local port; sum bytes_received over matching socket lines
  ss -tinH state established "( dport = :8080 )" 2>/dev/null | awk -v p=":$1" '
    index($0,"192.168.100.100" p){insock=1; next}
    insock && /bytes_received:/{for(i=1;i<=NF;i++) if($i ~ /^bytes_received:/){split($i,a,":"); s+=a[2]}; insock=0}
    END{print s+0}'
}

IPT_PRE=/tmp/b2a_${TAG}_iptables_pre.txt
IPT_POST=/tmp/b2a_${TAG}_iptables_post.txt
IPT_CLEAN=/tmp/b2a_${TAG}_iptables_clean.txt
IPT_PORT_FILE=/tmp/b2a_${TAG}_port.txt
IPT_ACTIVE=0
PORT=""
cleanup_iptables(){
  [ "$IPT_ACTIVE" = "1" ] || return 0
  local p="$PORT"
  echo "--- iptables cleanup (delete the two DROP rules for port $p) ---"
  iptables -D INPUT -s 192.168.100.2 -p tcp --sport 8080 -d 192.168.100.100 --dport "$p" -j DROP 2>&1
  echo "DEL_INPUT_RC=$?"
  iptables -D OUTPUT -p tcp -s 192.168.100.100 --sport "$p" -d 192.168.100.2 --dport 8080 -j DROP 2>&1
  echo "DEL_OUTPUT_RC=$?"
  iptables -S > "$IPT_CLEAN" 2>&1
  echo "IPTABLES_CLEAN_SNAPSHOT:"; cat "$IPT_CLEAN"
  if diff -q "$IPT_PRE" "$IPT_CLEAN" >/dev/null 2>&1; then
    echo "IPTABLES_CLEAN_OK (post == pre)"
  else
    echo "IPTABLES_CLEAN_MISMATCH (post != pre) -- inspect $IPT_CLEAN"
  fi
  IPT_ACTIVE=0
}
cleanup_all(){
  cleanup_iptables
  [ -n "${SINKPID:-}" ] && kill -TERM $SINKPID 2>/dev/null; [ -n "${SINKPID:-}" ] && kill -9 $SINKPID 2>/dev/null
  [ -n "${SINKPID2:-}" ] && kill -9 $SINKPID2 2>/dev/null
  pkill -9 -x p7b_tcp_sink 2>/dev/null; pkill -9 -x p7b_tcp_churn 2>/dev/null
  [ -n "${SNAPPID:-}" ] && kill $SNAPPID 2>/dev/null
  [ -n "${SSPID:-}" ] && kill $SSPID 2>/dev/null
  [ -n "${CTLPID:-}" ] && stop_tcpdump $CTLPID ctl
}
trap cleanup_all EXIT

echo "--- environment witnesses ---"
echo -n "NIC_COALESCE "; ethtool -c $IF_ 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | tr '\n' ' '; echo
echo -n "NMCLI "; nmcli device status 2>/dev/null | grep $IF_
echo -n "ROUTE_GET "; ip route get $BOARD | head -1

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF_/carrier

echo "--- iptables baseline snapshot ---"
iptables -S > "$IPT_PRE" 2>&1; cat "$IPT_PRE"

echo "--- pcap (single, full 'tcp port 8080', snaplen 128, ${RING_C}MBx${RING_W} ring) ---"
nohup tcpdump -i $IF_ -s 128 -B 262144 -C $RING_C -W $RING_W -w /tmp/b2a_${TAG}_ctl.pcap \
   "tcp port 8080" </dev/null > /tmp/b2a_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/b2a_${TAG}_ctl.err || exit 4
echo "CTL_PID=$CTLPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/b2a_${TAG}_nstat_pre.txt
cat /tmp/b2a_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit, before ring starts) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW > /tmp/b2a_${TAG}_pre.txt 2>&1; echo "SNAP_PRE_RC=$?"; cat /tmp/b2a_${TAG}_pre.txt

echo "--- board snapshot ring (background; one point per ~0.2 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.1
  done ) > /tmp/b2a_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- ss sampler (background; 1 Hz per-socket bytes) ---"
( while :; do
    echo "SS_T $(date +%s.%N)"
    ss -tinH state established "( dport = :8080 )" 2>&1
    sleep 1
  done ) > /tmp/b2a_${TAG}_ss.log 2>&1 &
SSPID=$!
echo "SS_PID=$SSPID"

run_sink(){
  local tag=$1; shift
  timeout -k 5 $RUN_TIMEOUT $SINK_BIN --host $BOARD --port 8080 \
    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MB --check lane8 $EXTRA \
    > /tmp/b2a_${TAG}_${tag}.txt 2>&1 &
}

case "$MODE" in
oneprobe)
  # quick basin-presence binary: 1 connection, rcvbuf 2920, small MB, hard timeout
  RCVBUF=${RCVBUF:-2920}; CONNS=1
  MB=${MB:-8000000}; SECS=${SECS:-20}; RUN_TIMEOUT=${RUN_TIMEOUT:-25}
  T0=$(date +%s.%N); echo "### PROBE_BEGIN $T0"
  timeout -k 5 $RUN_TIMEOUT $SINK_BIN --host $BOARD --port 8080 --rcvbuf $RCVBUF --conns 1 \
     --seconds $SECS --maxbytes $MB --check lane8 $EXTRA > /tmp/b2a_${TAG}_sink1.txt 2>&1
  RC=$?; T1=$(date +%s.%N)
  echo "PROBE_RC=$RC T0=$T0 T1=$T1 wall=$(awk -v a=$T0 -v b=$T1 'BEGIN{printf "%.3f",b-a}')"
  grep -E '^SINK_CONN|^SINK_SUM|^SINK_DONE' /tmp/b2a_${TAG}_sink1.txt
  ;;

fast)
  RCVBUF=${RCVBUF:-2920}; CONNS=${CONNS:-1}
  T0=$(date +%s.%N); echo "### FAST_BEGIN $T0 dur=$DUR"
  run_sink sink1
  SINKPID=$!
  echo "SINK1_PID=$SINKPID"
  sleep $DUR
  echo "### FAST_END $(date +%s.%N)"
  kill -TERM $SINKPID 2>/dev/null; sleep 1; kill -9 $SINKPID 2>/dev/null
  SINKPID=""
  grep -E '^SINK_CONN|^SINK_SUM|^SINK_DONE|^SINK_OPTS|^SINK_CHECK' /tmp/b2a_${TAG}_sink1.txt
  ;;

orphan)
  CONNS=1
  # keep the sink socket alive through the whole blackout (no FAIL_CONNECT/STALL close):
  EXTRA=${EXTRA:-'--poll-ms 1000 --stall-n 500'}
  T0=$(date +%s.%N); echo "### ORPHAN_BEGIN $T0"
  run_sink sink1
  SINKPID=$!
  echo "SINK1_PID=$SINKPID"

  PORT=""; RATE=""
  for i in $(seq 1 200); do
    P=$(port_of)
    if [ -n "$P" ]; then
      B1=$(bytes_of "$P"); T1=$(date +%s.%N); sleep 1
      B2=$(bytes_of "$P"); T2=$(date +%s.%N)
      RATE=$(awk -v a=$B1 -v b=$B2 -v t1=$T1 -v t2=$T2 'BEGIN{dt=t2-t1; if(dt>0) printf "%.1f",(b-a)*8/dt/1e6; else print 0}')
      PORT=$P
      [ "${RATE%.*}" -ge 700 ] 2>/dev/null && break
    fi
    sleep 0.2
  done
  echo "PORT=$PORT RATE_Mbps=$RATE"
  [ -n "$PORT" ] || { echo "ORPHAN_FAIL no established socket"; exit 5; }
  echo "$PORT" > "$IPT_PORT_FILE"

  echo "--- swap to blackout-window pcap (drop the fast-phase capture) $(date +%s.%N) ---"
  stop_tcpdump $CTLPID ctl
  nohup tcpdump -i $IF_ -s 112 -B 65536 -w /tmp/b2a_${TAG}_replay.pcap \
     "tcp port 8080" </dev/null > /tmp/b2a_${TAG}_ctl2.err 2>&1 &
  CTLPID=$!
  arm_tcpdump /tmp/b2a_${TAG}_ctl2.err || exit 4
  echo "REPLAY_PCAP_PID=$CTLPID"

  echo "--- install two iptables DROP rules (4-tuple) at $(date +%s.%N) ---"
  iptables -I INPUT 1 -s 192.168.100.2 -p tcp --sport 8080 -d 192.168.100.100 --dport "$PORT" -j DROP
  echo "ADD_INPUT_RC=$?"
  iptables -I OUTPUT 1 -p tcp -s 192.168.100.100 --sport "$PORT" -d 192.168.100.2 --dport 8080 -j DROP
  echo "ADD_OUTPUT_RC=$?"
  IPT_ACTIVE=1
  iptables -S > "$IPT_POST" 2>&1; echo "IPTABLES_POST_DROP:"; cat "$IPT_POST"
  echo "DROP_INSTALLED t=$(date +%s.%N) port=$PORT pre_rate_Mbps=$RATE"

  sleep $DUR
  echo "ORPHAN_WINDOW_END t=$(date +%s.%N)"

  # RESUME_PROBE: remove DROP, measure whether the OLD connection resumes (5 s)
  cleanup_iptables
  RB1=$(bytes_of "$PORT"); RT1=$(date +%s.%N)
  sleep 5
  RB2=$(bytes_of "$PORT"); RT2=$(date +%s.%N)
  RRATE=$(awk -v a=$RB1 -v b=$RB2 -v t1=$RT1 -v t2=$RT2 'BEGIN{dt=t2-t1; if(dt>0) printf "%.1f",(b-a)*8/dt/1e6; else print 0}')
  echo "RESUME_PROBE old_port=$PORT delta_bytes=$((RB2-RB1)) rate_Mbps=$RRATE"

  if [ "$RECOVER" = "1" ]; then
    echo "--- B2: kill old sink, start a NEW connection ---"
    kill -TERM $SINKPID 2>/dev/null; sleep 1; kill -9 $SINKPID 2>/dev/null; SINKPID=""
    sleep 1
    NEWMB=${NEWMB:-200000000}
    NEWSECS=${NEWSECS:-30}
    T3=$(date +%s.%N)
    timeout -k 5 90 $SINK_BIN --host $BOARD --port 8080 --rcvbuf 2920 --conns 1 \
       --seconds $NEWSECS --maxbytes $NEWMB --check lane8 --poll-ms 1000 --stall-n 60 \
       > /tmp/b2a_${TAG}_newconn.txt 2>&1
    NRC=$?; T4=$(date +%s.%N)
    echo "NEWCONN_RC=$NRC T0=$T3 T1=$T4 wall=$(awk -v a=$T3 -v b=$T4 'BEGIN{printf "%.3f",b-a}')"
    grep -E '^SINK_CONN|^SINK_SUM|^SINK_DONE|^SINK_OPTS|^SINK_CHECK' /tmp/b2a_${TAG}_newconn.txt
    echo "SNAP_AFTER_NEWCONN $(date +%s.%N)"
    bash $S snap ${TAG}_AFTER_NEWCONN $KW > /tmp/b2a_${TAG}_after_newconn.txt 2>&1; echo "SNAP_AFTER_NEWCONN_RC=$?"
  fi
  ;;

basin)
  RCVBUF=${RCVBUF:-2920}; CONNS=${CONNS:-6}
  EXTRA=${EXTRA:-'--poll-ms 1000 --stall-n 3'}
  NSINKS=${NSINKS:-2}; STAGGER=${STAGGER:-0.4}
  T0=$(date +%s.%N); echo "### BASIN_BEGIN $T0 nsinks=$NSINKS stagger=$STAGGER"
  run_sink sink1; SINKPID=$!
  echo "SINK1_PID=$SINKPID"
  sleep $STAGGER
  run_sink sink2; SINKPID2=$!
  echo "SINK2_PID=$SINKPID2"
  sleep $DUR
  echo "### BASIN_END $(date +%s.%N)"
  kill -TERM $SINKPID $SINKPID2 2>/dev/null; sleep 1; kill -9 $SINKPID $SINKPID2 2>/dev/null
  SINKPID=""; SINKPID2=""
  for f in sink1 sink2; do echo "== $f =="; grep -E '^SINK_CONN|^SINK_SUM|^SINK_DONE|^SINK_OPTS|^SINK_CHECK' /tmp/b2a_${TAG}_${f}.txt; done
  ;;

zerowin)
  RCVBUF=${RCVBUF:-2920}; CONNS=1
  EXTRA=${EXTRA:-'--poll-ms 1000 --stall-n 500'}
  MB=${MB:-200000000000}; SECS=${SECS:-$((DUR+200))}
  T0=$(date +%s.%N); echo "### ZEROWIN_BEGIN $T0"
  # NO timeout wrapper: SIGSTOP must hit the sink binary itself (timeout's child is
  # what runs the sink; stopping the timeout process does NOT stop the reader).
  $SINK_BIN --host $BOARD --port 8080 --rcvbuf $RCVBUF --conns 1      --seconds $SECS --maxbytes $MB --check lane8 $EXTRA      > /tmp/b2a_${TAG}_sink1.txt 2>&1 &
  SINKPID=$!
  echo "SINK1_PID=$SINKPID (direct, no timeout wrapper)"
  # wait for the connection and some data, then SIGSTOP the sink (socket stays open in kernel)
  PORT=""
  for i in $(seq 1 100); do
    P=$(port_of); [ -n "$P" ] && { PORT=$P; break; }; sleep 0.2
  done
  [ -n "$PORT" ] || { echo "ZEROWIN_FAIL no established socket"; exit 5; }
  B1=$(bytes_of "$PORT"); sleep 1; B2=$(bytes_of "$PORT")
  echo "ZEROWIN_PORT=$PORT pre_stop_bytes=$((B2-B1))/s"
  kill -STOP $SINKPID
  echo "SINK_STOPPED t=$(date +%s.%N) port=$PORT"
  sleep $DUR
  echo "ZEROWIN_WINDOW_END t=$(date +%s.%N)"
  kill -CONT $SINKPID
  echo "SINK_CONT t=$(date +%s.%N)"
  RB1=$(bytes_of "$PORT"); sleep 10; RB2=$(bytes_of "$PORT")
  echo "ZEROWIN_RESUME delta_bytes=$((RB2-RB1)) over_10s"
  kill -TERM $SINKPID 2>/dev/null; sleep 1; kill -9 $SINKPID 2>/dev/null; SINKPID=""
  grep -E '^SINK_CONN|^SINK_SUM|^SINK_DONE|^SINK_OPTS|^SINK_CHECK' /tmp/b2a_${TAG}_sink1.txt
  ;;

churn)
  T0=$(date +%s.%N); echo "### CHURN_BEGIN $T0 dur=$DUR"
  timeout -k 5 $((DUR+90)) $CHURN --host $BOARD --port 8080 \
      --connect-interval-ms 10 --rcvbuf 1048576 --seconds $DUR \
      --max-conns 16000 --hold-s 5 \
      > /tmp/b2a_${TAG}_churn.txt 2> /tmp/b2a_${TAG}_churn.err
  CRC=$?
  echo "CHURN_RC=$CRC $(date +%s.%N)"
  grep -E '^CHURN_' /tmp/b2a_${TAG}_churn.txt | tail -20
  tail -5 /tmp/b2a_${TAG}_churn.err
  ;;

*) echo "MODE must be oneprobe|fast|orphan|basin|zerowin|churn"; exit 3 ;;
esac

echo "--- stop snapshot ring, then SNAP_POST (explicit) $(date +%s.%N) ---"
[ -n "${SNAPPID:-}" ] && kill $SNAPPID 2>/dev/null; sleep 0.3
bash $S snap ${TAG}_POST $KW > /tmp/b2a_${TAG}_post.txt 2>&1; echo "SNAP_POST_RC=$?"; cat /tmp/b2a_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/b2a_${TAG}_nstat_post.txt
cat /tmp/b2a_${TAG}_nstat_post.txt

echo "--- teardown ---"
[ -n "${SINKPID:-}" ] && kill -TERM $SINKPID 2>/dev/null; [ -n "${SINKPID:-}" ] && kill -9 $SINKPID 2>/dev/null
[ -n "${SINKPID2:-}" ] && kill -9 $SINKPID2 2>/dev/null
pkill -9 -x p7b_tcp_sink 2>/dev/null
[ -n "${SSPID:-}" ] && kill $SSPID 2>/dev/null
[ -n "${SNAPPID:-}" ] && kill $SNAPPID 2>/dev/null
sleep 0.3
[ -n "${CTLPID:-}" ] && stop_tcpdump $CTLPID ctl
trap - EXIT
cleanup_iptables
echo "--- pcap stats ---"
tail -3 /tmp/b2a_${TAG}_ctl.err 2>/dev/null
tail -3 /tmp/b2a_${TAG}_ctl2.err 2>/dev/null
ls -la /tmp/b2a_${TAG}_*.pcap* 2>&1
echo "--- ss log tail ---"; wc -l /tmp/b2a_${TAG}_ss.log 2>/dev/null; tail -4 /tmp/b2a_${TAG}_ss.log 2>/dev/null
echo "### B2A_END tag=$TAG $(date +%s.%N)"
