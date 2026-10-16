#!/bin/bash
# =============================================================================
# arm_trickleA.sh -- trickle forensics EXPERIMENT A arm (runs on the PEER box)
#
#   Purpose: re-run the B4H3 configuration with the two changes demanded by
#            _proj_10g/notes/p9_trickle_forensics_20261016/FINDINGS.md sec.7 (experiment A):
#              (1) capture BOTH directions: tcpdump filter WITHOUT 'src host'
#                  =>  tcpdump -i enp1s0f1np1 -s 0 -B 262144 -C 300 -W 8 -w .../full.pcap "tcp port 8080"
#              (2) snapshot KW = '66 67 68 69 20 43 51 52 55 57 58 5'  (stall + window + retx witnesses)
#            Rationale: the missing witness is the PEER->BOARD ACK stream (delayed-ACK + 1-2 MSS
#            window half of the "RTO lock-step self-lock" hypothesis, candidate 1 in sec.6).
#
#   Parent = k0_arm_b4_multi.sh (B4 round; NSINKS sinks in parallel, staggered STAGGER seconds).
#   Kept VERBATIM from it: the three pcap-correctness hard gates (arming / graceful stop /
#   loss report), identity gate, snapshot ring, SNAP_PRE/SNAP_POST, nstat pre/post, freshness gate.
#   Delta vs k0_arm_b4_multi.sh:
#     * full pcap is BIDIRECTIONAL (src host removed)  <- experiment A item (1)
#     * KW default   = '66 67 68 69 20 43 51 52 55 57 58 5'  <- experiment A item (2)
#     * KW2 (PRE/POST) = KW + '71 72 73 74' on 0x28 (E12; the H1/H2/H3 discriminators),
#       AUTO-DROPPED on 0x24 (0x13C..0x148 are MIR words in the 0x24 geometry).
#     * trickle-A defaults baked in: NSINKS=2 STAGGER=0.4 RCVBUF=2920 CONNS=6 SECS=300
#       MAXBYTES=50000000 SINK_EXTRA='--poll-ms 1000 --stall-n 3'   (B4H3 verbatim)
#     * GEN parameter (0x28 | 0x24) -> EXPECT_BID / NW  (identity gate)
#
#   Usage: bash arm_trickleA.sh <TAG> <GEN> [NSINKS] [STAGGER] [RCVBUF] [CONNS] [SECS] [MAXBYTES]
#   Env overrides: KW KW2 EXPECT_BID NW SINK_EXTRA RING_C RING_W RUN_TIMEOUT
#
#   Control arms (design doc sec.7, run as SEPARATE invocations -- dial them with parameters):
#     * single-sink same config:        bash arm_trickleA.sh <TAG> 0x28 1 0 2920 6 300 50000000
#       (reproduces the FAST stream = F-A yardstick of the forensics report)
#     * RST arm (new sink switch):      SINK_EXTRA='--poll-ms 1000 --stall-n 3 --abort-rst' \
#                                       bash arm_trickleA.sh <TAG> 0x28 2 0.4 2920 6 120 50000000
#     * same-4-tuple arm (new switch):  add '--local-port 40000' to SINK_EXTRA (pair with --abort-rst)
#   Run as:  python tools/peer_ssh.py --sudo "cd /tmp/p7b_biz && bash arm_trickleA.sh ..."
# =============================================================================
set -u
TAG=${1:?usage: arm_trickleA.sh TAG GEN [NSINKS STAGGER RCVBUF CONNS SECS MAXBYTES]}; GEN=${2:?GEN = 0x28 | 0x24}
NSINKS=${3:-2}; STAGGER=${4:-0.4}; RCVBUF=${5:-2920}; CONNS=${6:-6}; SECS=${7:-300}; MAXBYTES=${8:-50000000}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
RING_C=${RING_C:-300}; RING_W=${RING_W:-8}
RUN_TIMEOUT=${RUN_TIMEOUT:-900}
# trickle-A default (B4H3 verbatim); override via env for the control arms
SINK_EXTRA=${SINK_EXTRA-'--poll-ms 1000 --stall-n 3'}

case "$GEN" in
  0x28|0x00000028) DEF_BID=0x00000028; DEF_NW=75; E12=1 ;;
  0x24|0x00000024) DEF_BID=0x00000024; DEF_NW=71; E12=0 ;;
  *) echo "GEN must be 0x28 or 0x24 (got '$GEN')"; exit 3 ;;
esac
export EXPECT_BID=${EXPECT_BID:-$DEF_BID} NW=${NW:-$DEF_NW}
KW=${KW:-'66 67 68 69 20 43 51 52 55 57 58 5'}
if [ "$E12" = "1" ]; then KW2=${KW2:-"$KW 71 72 73 74"}; else KW2=${KW2:-"$KW"}; fi

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root => tcpdump/reg_rw blocked (run via peer_ssh.py --sudo)"; exit 3; }
rm -f /tmp/k0_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/k0_${TAG}_*"; exit 3; }

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

echo "### K0M_BEGIN tag=$TAG gen=$GEN nsinks=$NSINKS stagger=$STAGGER rcvbuf=$RCVBUF conns=$CONNS secs=$SECS maxbytes=$MAXBYTES ring=${RING_C}MBx${RING_W} sink_extra='$SINK_EXTRA' $(date +%s.%N)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINK_MD5 $(md5sum /tmp/p7b_biz/p7b_tcp_sink | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID KW='$KW' KW2='$KW2'"

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (1): control frames census (FIN/RST, whole window) ---"
nohup tcpdump -i $IF -s 0 -w /tmp/k0_${TAG}_ctl.pcap \
   "tcp port 8080 and (tcp[tcpflags] & (tcp-fin|tcp-rst) != 0)" \
   </dev/null > /tmp/k0_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/k0_${TAG}_ctl.err || exit 4

echo "--- pcap (2): BIDIRECTIONAL full-frame ring (experiment A item 1; no 'src host') ---"
rm -f /tmp/k0_${TAG}_full*
nohup tcpdump -i $IF -s 0 -B 262144 -C $RING_C -W $RING_W -w /tmp/k0_${TAG}_full.pcap \
   "tcp port 8080" </dev/null > /tmp/k0_${TAG}_full.err 2>&1 &
FULLPID=$!
arm_tcpdump /tmp/k0_${TAG}_full.err || exit 4
echo "FULL_PID=$FULLPID CTL_PID=$CTLPID"

echo "--- board snapshot ring (background; one point per 0.15 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/k0_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_pre.txt
cat /tmp/k0_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/k0_${TAG}_pre.txt

echo "--- main run: $NSINKS sinks in parallel (staggered ${STAGGER}s) ---"
T0=$(date +%s.%N)
SPIDS=()
for i in $(seq 1 $NSINKS); do
  timeout -k 5 $RUN_TIMEOUT /tmp/p7b_biz/p7b_tcp_sink --host $BOARD --port 8080 \
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

echo "--- SNAP_POST (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/k0_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_post.txt
cat /tmp/k0_${TAG}_nstat_post.txt

echo "--- teardown: stop snapshot ring + pcaps ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $FULLPID full
stop_tcpdump $CTLPID ctl

echo "--- pcap stats (tcpdump self-report) ---"
echo "[ctl]";  tail -3 /tmp/k0_${TAG}_ctl.err
echo "[full]"; tail -3 /tmp/k0_${TAG}_full.err
ls -la /tmp/k0_${TAG}_*.pcap* 2>&1
sha256sum /tmp/k0_${TAG}_*.pcap* 2>&1

echo "--- sink summary (verbatim) ---"
for i in $(seq 1 $NSINKS); do
  echo "== SINK $i =="
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/k0_${TAG}_sink${i}.txt
done

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(empty = no leftover processes)"

# ---- expected readings (pre-registered, from the forensics report sec.7 experiment A) ----
#   Candidate 1 ("RTO lock-step self-lock"): peer ACKs appear ~1 per cluster (~49.7/s),
#     right after each replay; win in {0,1460,2920}; dW68 ~ 49.7/s; dW66 duty ~100% with the
#     bulk of (dW66 - dW67) on the PEER side; W69 = {win_inflight, win_wnd_eff} at the wait.
#   Candidate 3 (board internal stall) predicts dW68 of thousands/s instead.
#   Offline parsers: tk_dump.py / tk_scan_arm.py / tk_timeline2.py / tk_snap.py
#     (p9_trickle_forensics_20261016), plus parse_snap_timeline.py (K0 round).
echo "### K0M_END tag=$TAG $(date +%s.%N)"
