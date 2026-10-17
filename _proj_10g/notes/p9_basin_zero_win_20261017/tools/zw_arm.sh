#!/bin/bash
# =============================================================================
# zw_arm.sh -- p9_basin_zero_win_20261017 arm runner (zw_ prefix) (runs on the PEER box)
#
#   Purpose: measure the peer-advertised ZERO-WINDOW ACK ratio across an rcvbuf
#   ladder, inside vs outside the "slow basin" (session-level latent slow state).
#
#   Skeleton = p9_basin_probe_20261017/tools/bp_arm.sh (which itself = arm_fast_ab.sh).
#   Kept VERBATIM from it: pcap hard gates (arming / graceful stop / loss report),
#   identity gate, snapshot ring, SNAP_PRE/SNAP_POST, nstat pre/post, sink log layout,
#   RUN_TIMEOUT hard bound, ss -tin per-second sampler.
#
#   Deltas vs bp_arm.sh:
#     * peer-side file prefix = zw_<TAG>_*   (round ownership: this round only)
#     * default KW = 13 words incl. W63/64/65 (frm_wait / bp / mac_tx_idle)
#     * teardown: pkill -9 -x p7b_tcp_sink (bp_arm.sh relied on timeout wrapper only;
#       the 0x2A round registered D3: kill $PID killed timeout, not the sink)
#     * NW/EXPECT_BID defaults = 75 / 0x00000028 (board gen 0x28)
#
#   Usage: bash zw_arm.sh <TAG> <NSINKS> <STAGGER> <RCVBUF> <CONNS> <SECS> <MAXBYTES>
#   Env overrides: SINK_BIN SINK_EXTRA KW KW2 RING_C RING_W RUN_TIMEOUT NW EXPECT_BID
# =============================================================================
set -u
TAG=${1:?usage: zw_arm.sh TAG NSINKS STAGGER RCVBUF CONNS SECS MAXBYTES}
NSINKS=${2:?}; STAGGER=${3:?}; RCVBUF=${4:?}; CONNS=${5:?}; SECS=${6:?}; MAXBYTES=${7:?}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
SINK_BIN=${SINK_BIN:-/tmp/p7b_biz/p7b_tcp_sink}
SINK_EXTRA=${SINK_EXTRA-}
RING_C=${RING_C:-256}; RING_W=${RING_W:-4}
RUN_TIMEOUT=${RUN_TIMEOUT:-240}
NW=${NW:-75}; EXPECT_BID=${EXPECT_BID:-0x00000028}
KW=${KW:-'5 20 43 51 52 55 63 64 65 66 67 68 69'}
KW2=${KW2:-"$KW 71 72 73 74"}
# the snapshot tool is a CHILD process: NW/EXPECT_BID must be in its environment
export NW EXPECT_BID

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root => tcpdump/reg_rw blocked (run via peer_ssh.py --sudo)"; exit 3; }
[ -x "$SINK_BIN" ] || { echo "PRECHECK_FAIL SINK_BIN not executable: $SINK_BIN"; exit 3; }

echo "--- leftover precheck (must be empty) ---"
pgrep -a -x p7b_tcp_sink && { echo "PRECHECK_FAIL leftover p7b_tcp_sink"; exit 3; }
pgrep -a -x tcpdump && { echo "PRECHECK_FAIL leftover tcpdump"; exit 3; }
echo "LEFTOVER_CLEAN"
rm -f /tmp/zw_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/zw_${TAG}_*"; exit 3; }

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

echo "### K0M_BEGIN tag=$TAG nsinks=$NSINKS stagger=$STAGGER rcvbuf=$RCVBUF conns=$CONNS secs=$SECS maxbytes=$MAXBYTES ring=${RING_C}MBx${RING_W} sink_extra='$SINK_EXTRA' sink_bin=$SINK_BIN $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINK_PATH $SINK_BIN"
echo "### SINK_MD5 $(md5sum $SINK_BIN | awk '{print $1}')"
echo "### SINK_SIZE $(stat -c %s $SINK_BIN)"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID KW='$KW' KW2='$KW2' RUN_TIMEOUT=$RUN_TIMEOUT"
echo "### SS_SAMPLER cmd=\"ss -tinH state established (dport = :8080)\" every 1s -> /tmp/zw_${TAG}_ss.log"

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (single, 'ctl'): full 'tcp port 8080', snaplen 128, ${RING_C}MBx${RING_W} ring ---"
nohup tcpdump -i $IF -s 128 -B 262144 -C $RING_C -W $RING_W -w /tmp/zw_${TAG}_ctl.pcap \
   "tcp port 8080" </dev/null > /tmp/zw_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/zw_${TAG}_ctl.err || exit 4
echo "CTL_PID=$CTLPID"

echo "--- board snapshot ring (background; one point per ~0.15 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/zw_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- ss sampler (background; per-second per-socket kernel byte counters) ---"
( while :; do
    echo "SS_T $(date +%s.%N)"
    ss -tinH state established "( dport = :8080 )" 2>&1
    sleep 1
  done ) > /tmp/zw_${TAG}_ss.log 2>&1 &
SSPID=$!
echo "SS_PID=$SSPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/zw_${TAG}_nstat_pre.txt
cat /tmp/zw_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/zw_${TAG}_pre.txt

echo "--- main run: $NSINKS sinks in parallel (staggered ${STAGGER}s), timeout ${RUN_TIMEOUT}s ---"
T0=$(date +%s.%N)
SPIDS=()
for i in $(seq 1 $NSINKS); do
  timeout -k 5 $RUN_TIMEOUT $SINK_BIN --host $BOARD --port 8080 \
    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
    > /tmp/zw_${TAG}_sink${i}.txt 2>&1 &
  SPIDS+=($!)
  echo "SINK${i}_START pid=${SPIDS[-1]} t=$(date +%s.%N)"
  [ "$i" -lt "$NSINKS" ] && sleep $STAGGER
done
RC_SUM=0
for i in $(seq 0 $((NSINKS-1))); do
  wait ${SPIDS[$i]}; R=${?}; RC_SUM=$((RC_SUM+R)); echo "SINK$((i+1))_RC=$R"
  [ "$R" = "124" ] && echo "SINK$((i+1))_TIMEOUT_KILLED (RUN_TIMEOUT=${RUN_TIMEOUT}s)"
done
T1=$(date +%s.%N)
echo "### SINK_RC_SUM=$RC_SUM T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
for i in $(seq 1 $NSINKS); do
  [ -s /tmp/zw_${TAG}_sink${i}.txt ] || echo "SINK${i}_LOG_EMPTY"
  grep -q '^SINK_SUM' /tmp/zw_${TAG}_sink${i}.txt || echo "SINK${i}_SUM_MISSING"
done

echo "--- SNAP_POST (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/zw_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/zw_${TAG}_nstat_post.txt
cat /tmp/zw_${TAG}_nstat_post.txt

echo "--- teardown: stop ss sampler + snapshot ring + pcap (+ any sink survivor) ---"
kill $SSPID $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $CTLPID ctl
pkill -9 -x p7b_tcp_sink 2>/dev/null && echo "PKILL_SINK_SURVIVOR" || true

echo "--- pcap stats (tcpdump self-report) ---"
tail -3 /tmp/zw_${TAG}_ctl.err
ls -la /tmp/zw_${TAG}_*.pcap* 2>&1
sha256sum /tmp/zw_${TAG}_*.pcap* 2>&1

echo "--- ss log tail witness ---"
wc -l /tmp/zw_${TAG}_ss.log; tail -4 /tmp/zw_${TAG}_ss.log

echo "--- SINK_OPTS witness ---"
for i in $(seq 1 $NSINKS); do
  o=$(grep -m1 '^SINK_OPTS' /tmp/zw_${TAG}_sink${i}.txt || true)
  [ -n "$o" ] && echo "### SINK_OPTS_WITNESS sink$i $o" || echo "### SINK_OPTS_WITNESS sink$i MISSING"
done

echo "--- sink summary (verbatim) ---"
for i in $(seq 1 $NSINKS); do
  echo "== SINK $i =="
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/zw_${TAG}_sink${i}.txt
done

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a -x p7b_tcp_sink; pgrep -a -x tcpdump; echo "(empty = no leftover processes)"
echo "### K0M_END tag=$TAG $(date +%s.%N)"
