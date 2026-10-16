#!/bin/bash
# =============================================================================
# arm_fast_ab.sh -- p9_t2fast_ab_20261017 arm runner (runs on the PEER box)
#
#   Purpose: separate the THREE unseparated degrees of freedom of the observation
#   "T2 did not reproduce the B4P_S2 fast stream (887 Mbps)" (trickle round REPORT sec.8-1):
#     (i) sink binary (OLD 6d9b14f2 / NEW f6229929) · (ii) burn freshness / cross-arm
#     state · (iii) config (maxbytes + poll/stall extras).
#
#   Parent skeleton = arm_trickleA_peer_patched.sh (p9_p3win_trickle round; itself from
#   k0_arm_b4_multi.sh of the 0x28 K0 round).  Kept VERBATIM from it: the pcap hard gates
#   (arming / graceful stop / loss report), the identity gate, the snapshot ring,
#   SNAP_PRE/SNAP_POST, nstat pre/post, the sink log layout.
#
#   Deltas vs arm_trickleA_peer_patched.sh:
#     * ONE tcpdump only, named "ctl": full `tcp port 8080` with -s 128 (small AND
#       carries the handshake + first data + first ACK, so the first-segment timing
#       can be measured).  NO full pcap this round (prev round proved the 2.4 GB full
#       ring structurally drops ~30M pkts at ~5 Gbps => only pollution).
#     * SINK_BIN / SINK_SIZE / SINK_PATH witnesses (F1 needs the OLD binary).
#     * nstat list extended with the delayed-ACK family:
#       TcpExtDelayedACKs / TcpExtQuickAcks / TcpExtDelayedACKLocked / TcpExtDelayedACKLost.
#     * KW default = the round's minimum set '5 20 43 51 52 55 66 67 68 69';
#       KW2 (PRE/POST) = KW + '63 64 65 71 72 73 74'.
#     * leftover-process precheck before arming.
#     * SINK_OPTS witness extraction (new binary prints it; old binary does NOT =>
#       a MISSING line is itself a binary-generation witness).
#
#   Usage: bash arm_fast_ab.sh <TAG> <NSINKS> <STAGGER> <RCVBUF> <CONNS> <SECS> <MAXBYTES>
#   Env overrides: SINK_BIN SINK_EXTRA KW KW2 RING_C RING_W RUN_TIMEOUT NW EXPECT_BID
#
#   Pre-registered arms (see round README_FOR_TL.md):
#     F0 burn 0x28 -> immediately  bash arm_fast_ab.sh F0 1 0 2920 6 120 200000000
#     F1 (no burn)     SINK_BIN=/tmp/p7b_biz_prev/p7b_tcp_sink__6d9b14f2_pre_sinkdelta \
#                      bash arm_fast_ab.sh F1 1 0 2920 6 120 200000000
#     F2 (no burn)     bash arm_fast_ab.sh F2 1 0 2920 6 120 200000000
#     F3 burn 0x28 -> immediately SINK_EXTRA='--poll-ms 1000 --stall-n 3' \
#                      bash arm_fast_ab.sh F3 1 0 2920 6 120 50000000
#     F4 (no burn)     bash arm_fast_ab.sh F4 2 0.4 2920 2 40 20000000
#     F5 (no burn)     bash arm_fast_ab.sh F5 1 0 2920 6 120 200000000
#     F6 burn 0x28 -> immediately  bash arm_fast_ab.sh F6 1 0 2920 6 120 200000000
#   Run as: python tools/peer_ssh.py --sudo "cd /tmp/p7b_biz && bash arm_fast_ab.sh ..."
# =============================================================================
set -u
TAG=${1:?usage: arm_fast_ab.sh TAG NSINKS STAGGER RCVBUF CONNS SECS MAXBYTES}
NSINKS=${2:?}; STAGGER=${3:?}; RCVBUF=${4:?}; CONNS=${5:?}; SECS=${6:?}; MAXBYTES=${7:?}
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
SINK_BIN=${SINK_BIN:-/tmp/p7b_biz/p7b_tcp_sink}
SINK_EXTRA=${SINK_EXTRA-}
RING_C=${RING_C:-256}; RING_W=${RING_W:-4}
RUN_TIMEOUT=${RUN_TIMEOUT:-165}
NW=${NW:-75}; EXPECT_BID=${EXPECT_BID:-0x00000028}
KW=${KW:-'5 20 43 51 52 55 66 67 68 69'}
KW2=${KW2:-"$KW 63 64 65 71 72 73 74"}

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root => tcpdump/reg_rw blocked (run via peer_ssh.py --sudo)"; exit 3; }
[ -x "$SINK_BIN" ] || { echo "PRECHECK_FAIL SINK_BIN not executable: $SINK_BIN"; exit 3; }

echo "--- leftover precheck (must be empty) ---"
pgrep -a p7b_tcp_sink && { echo "PRECHECK_FAIL leftover p7b_tcp_sink"; exit 3; }
pgrep -a tcpdump && { echo "PRECHECK_FAIL leftover tcpdump"; exit 3; }
echo "LEFTOVER_CLEAN"
rm -f /tmp/fast_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/fast_${TAG}_*"; exit 3; }

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

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (single, 'ctl'): full 'tcp port 8080', snaplen 128, ${RING_C}MBx${RING_W} ring ---"
nohup tcpdump -i $IF -s 128 -B 262144 -C $RING_C -W $RING_W -w /tmp/fast_${TAG}_ctl.pcap \
   "tcp port 8080" </dev/null > /tmp/fast_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/fast_${TAG}_ctl.err || exit 4
echo "CTL_PID=$CTLPID"

echo "--- board snapshot ring (background; one point per ~0.15 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/fast_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtQuickAcks) ' > /tmp/fast_${TAG}_nstat_pre.txt
cat /tmp/fast_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/fast_${TAG}_pre.txt

echo "--- main run: $NSINKS sinks in parallel (staggered ${STAGGER}s), timeout ${RUN_TIMEOUT}s ---"
T0=$(date +%s.%N)
SPIDS=()
for i in $(seq 1 $NSINKS); do
  timeout -k 5 $RUN_TIMEOUT $SINK_BIN --host $BOARD --port 8080 \
    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA \
    > /tmp/fast_${TAG}_sink${i}.txt 2>&1 &
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
  [ -s /tmp/fast_${TAG}_sink${i}.txt ] || echo "SINK${i}_LOG_EMPTY"
  grep -q '^SINK_SUM' /tmp/fast_${TAG}_sink${i}.txt || echo "SINK${i}_SUM_MISSING"
done

echo "--- SNAP_POST (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/fast_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtQuickAcks) ' > /tmp/fast_${TAG}_nstat_post.txt
cat /tmp/fast_${TAG}_nstat_post.txt

echo "--- teardown: stop snapshot ring + pcap ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $CTLPID ctl

echo "--- pcap stats (tcpdump self-report) ---"
tail -3 /tmp/fast_${TAG}_ctl.err
ls -la /tmp/fast_${TAG}_*.pcap* 2>&1
sha256sum /tmp/fast_${TAG}_*.pcap* 2>&1

echo "--- SINK_OPTS witness (new binary prints it; old binary => MISSING) ---"
for i in $(seq 1 $NSINKS); do
  o=$(grep -m1 '^SINK_OPTS' /tmp/fast_${TAG}_sink${i}.txt || true)
  [ -n "$o" ] && echo "### SINK_OPTS_WITNESS sink$i $o" || echo "### SINK_OPTS_WITNESS sink$i MISSING"
done

echo "--- sink summary (verbatim) ---"
for i in $(seq 1 $NSINKS); do
  echo "== SINK $i =="
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/fast_${TAG}_sink${i}.txt
done

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(empty = no leftover processes)"
echo "### K0M_END tag=$TAG $(date +%s.%N)"
