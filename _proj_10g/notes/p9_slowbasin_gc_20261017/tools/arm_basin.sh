#!/bin/bash
# =============================================================================
# arm_basin.sh -- p9_slowbasin_gc_20261017 arm runner (runs on the PEER box)
#
#   Purpose: separate the ENTRY event and the CLEAR event of the "slow basin"
#   (session-level latent slow state; see p9_t2fast_ab_20261017/README_FOR_TL.md sec.7/8).
#
#   Parent skeleton = arm_fast_ab.sh (p9_t2fast_ab_20261017; itself from
#   arm_trickleA_peer_patched.sh).  Kept VERBATIM from it: the pcap hard gates
#   (arming / graceful stop / loss report), the identity gate, the snapshot ring,
#   SNAP_PRE/SNAP_POST, nstat pre/post, the sink log layout, RUN_TIMEOUT hard bound.
#
#   Deltas vs arm_fast_ab.sh:
#     * peer-side file prefix = basin_<TAG>_*  (round rule: basin_*/gc_* only)
#     * NEW instrument: `ss -tin` per-second sampler (kernel-side per-socket
#       bytes_received timeline; independent of the pcap; catches connections even
#       if tcpdump drops).  Log = /tmp/basin_<TAG>_ss.log
#     * nstat list = the round's mandated six (TcpExtDelayedACKs / DelayedACKLocked /
#       TcpExtTCPOFOQueue / TcpRetransSegs / TcpInSegs / TcpOutSegs) + DelayedACKLost
#       + TCPPureAcks/TCPHPAcks + TCPFastRetrans (cheap; QuickAcks does not exist on 7.0).
#     * RUN_TIMEOUT default = 240 (round派单: 200-260 hard bound).
#
#   Usage: bash arm_basin.sh <TAG> <NSINKS> <STAGGER> <RCVBUF> <CONNS> <SECS> <MAXBYTES>
#   Env overrides: SINK_BIN SINK_EXTRA KW KW2 RING_C RING_W RUN_TIMEOUT NW EXPECT_BID
#
#   Pre-registered arms (round README_FOR_TL.md):
#     G0  (no burn)  bash arm_basin.sh G0 1 0 2920 3 60 60000000         # A' baseline
#     G1  (no burn)  SINK_EXTRA='--poll-ms 1000 --stall-n 3' \
#                    bash arm_basin.sh G1 2 0.4 2920 6 120 50000000      # entry arm (T1 cfg)
#     G2  (no burn)  bash arm_basin.sh G2 1 0 2920 3 60 60000000         # residue test
#     G3  (burn 0x28 first)  bash arm_basin.sh G3 1 0 2920 3 60 60000000 # clear-by-burn test
#     G4  (no burn)  flood: bash arm_basin.sh G4F 1 0 1048576 20000 20 2097152 \
#                               --env SINK_EXTRA='--poll-ms 300 --stall-n 2'
#                    then   bash arm_basin.sh G4 1 0 2920 3 60 60000000
#     B-plan (only if G1 all fast):
#       G1b stagger 0:  SINK_EXTRA='--poll-ms 1000 --stall-n 3' \
#                       bash arm_basin.sh G1b 2 0 2920 6 120 50000000
#       G1c longer:     SINK_EXTRA='--poll-ms 1000 --stall-n 3' RUN_TIMEOUT=280 \
#                       bash arm_basin.sh G1c 2 0.4 2920 6 240 200000000
#   Run as: python tools/peer_ssh.py --timeout 400 --sudo "cd /tmp/p7b_biz && bash arm_basin.sh ..."
# =============================================================================
set -u
TAG=${1:?usage: arm_basin.sh TAG NSINKS STAGGER RCVBUF CONNS SECS MAXBYTES}
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
KW=${KW:-'5 20 43 51 52 55 66 67 68 69'}
KW2=${KW2:-"$KW 63 64 65 71 72 73 74"}

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root => tcpdump/reg_rw blocked (run via peer_ssh.py --sudo)"; exit 3; }
[ -x "$SINK_BIN" ] || { echo "PRECHECK_FAIL SINK_BIN not executable: $SINK_BIN"; exit 3; }

echo "--- leftover precheck (must be empty) ---"
pgrep -a p7b_tcp_sink && { echo "PRECHECK_FAIL leftover p7b_tcp_sink"; exit 3; }
pgrep -a tcpdump && { echo "PRECHECK_FAIL leftover tcpdump"; exit 3; }
echo "LEFTOVER_CLEAN"
rm -f /tmp/basin_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/basin_${TAG}_*"; exit 3; }

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
echo "### SS_SAMPLER cmd=\"ss -tinH state established (dport = :8080)\" every 1s -> /tmp/basin_${TAG}_ss.log"

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (single, 'ctl'): full 'tcp port 8080', snaplen 128, ${RING_C}MBx${RING_W} ring ---"
nohup tcpdump -i $IF -s 128 -B 262144 -C $RING_C -W $RING_W -w /tmp/basin_${TAG}_ctl.pcap \
   "tcp port 8080" </dev/null > /tmp/basin_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/basin_${TAG}_ctl.err || exit 4
echo "CTL_PID=$CTLPID"

echo "--- board snapshot ring (background; one point per ~0.15 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/basin_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- ss sampler (background; per-second per-socket kernel byte counters) ---"
( while :; do
    echo "SS_T $(date +%s.%N)"
    ss -tinH state established "( dport = :8080 )" 2>&1
    sleep 1
  done ) > /tmp/basin_${TAG}_ss.log 2>&1 &
SSPID=$!
echo "SS_PID=$SSPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/basin_${TAG}_nstat_pre.txt
cat /tmp/basin_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/basin_${TAG}_pre.txt

echo "--- main run: $NSINKS sinks in parallel (staggered ${STAGGER}s), timeout ${RUN_TIMEOUT}s ---"
T0=$(date +%s.%N)
SPIDS=()
for i in $(seq 1 $NSINKS); do
  timeout -k 5 $RUN_TIMEOUT $SINK_BIN --host $BOARD --port 8080 \
    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
    > /tmp/basin_${TAG}_sink${i}.txt 2>&1 &
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
  [ -s /tmp/basin_${TAG}_sink${i}.txt ] || echo "SINK${i}_LOG_EMPTY"
  grep -q '^SINK_SUM' /tmp/basin_${TAG}_sink${i}.txt || echo "SINK${i}_SUM_MISSING"
done

echo "--- SNAP_POST (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/basin_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/basin_${TAG}_nstat_post.txt
cat /tmp/basin_${TAG}_nstat_post.txt

echo "--- teardown: stop ss sampler + snapshot ring + pcap ---"
kill $SSPID $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $CTLPID ctl

echo "--- pcap stats (tcpdump self-report) ---"
tail -3 /tmp/basin_${TAG}_ctl.err
ls -la /tmp/basin_${TAG}_*.pcap* 2>&1
sha256sum /tmp/basin_${TAG}_*.pcap* 2>&1

echo "--- ss log tail witness ---"
wc -l /tmp/basin_${TAG}_ss.log; tail -4 /tmp/basin_${TAG}_ss.log

echo "--- SINK_OPTS witness (new binary prints it; old binary => MISSING) ---"
for i in $(seq 1 $NSINKS); do
  o=$(grep -m1 '^SINK_OPTS' /tmp/basin_${TAG}_sink${i}.txt || true)
  [ -n "$o" ] && echo "### SINK_OPTS_WITNESS sink$i $o" || echo "### SINK_OPTS_WITNESS sink$i MISSING"
done

echo "--- sink summary (verbatim) ---"
for i in $(seq 1 $NSINKS); do
  echo "== SINK $i =="
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/basin_${TAG}_sink${i}.txt
done

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(empty = no leftover processes)"
echo "### K0M_END tag=$TAG $(date +%s.%N)"
