#!/bin/bash
# =============================================================================
# c1_arm.sh -- p9_c1_board_20261017 arm runner (runs on the PEER box)
#
#   Usage: bash c1_arm.sh <TAG> <GEN:0x28|0x24> <SECS> [extra churn args...]
#   Env overrides: ULIMIT DUMP_MAX RING_C RING_W RUN_TIMEOUT NW EXPECT_BID KW
#
#   Skeleton = p9_slowbasin_gc_20261017/tools/arm_basin.sh (itself from
#   arm_fast_ab.sh / arm_trickleA_peer_patched.sh).  Kept VERBATIM from it:
#   the pcap hard gates (arming / graceful stop), the identity gate, the
#   snapshot ring, SNAP_PRE/SNAP_POST, nstat pre/post, RUN_TIMEOUT hard bound.
#
#   Deltas vs arm_basin.sh:
#     * main run = /tmp/p7b_biz/p7b_tcp_churn (C1 tool) with the round's
#       mandated command line (interval 10 ms / rcvbuf 1 MiB / max-conns 16000 /
#       --dump-prefix-dir / --hold-s 5).  ulimit -n raised FIRST (soft was 1024).
#     * NEW: SNAP_MID taken while the churn process is in its --hold-s window
#       (i.e. AFTER CHURN_SUM is printed but BEFORE the exit FIN flood).
#     * NEW: restart@off distribution + CHURN_* witness lines + dump listing.
#     * peer-side artifact prefix = c1_<TAG>_* ; dump dir = /tmp/c1_dump_<TAG>
# =============================================================================
set -u
TAG=${1:?usage: c1_arm.sh TAG GEN SECS [churn args...]}
GEN=${2:?}; SECS=${3:?}
CHURN_EXTRA="${4:-} ${5:-} ${6:-} ${7:-} ${8:-} ${9:-}"
CHURN_EXTRA=$(echo "$CHURN_EXTRA" | sed 's/  */ /g;s/^ //;s/ $//')
IF_=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
CHURN=/tmp/p7b_biz/p7b_tcp_churn
DUMPDIR=/tmp/c1_dump_${TAG}
ULIMIT=${ULIMIT:-16384}
DUMP_MAX=${DUMP_MAX:-8192}
MAXCONN=${MAXCONN:-16000}
RING_C=${RING_C:-256}; RING_W=${RING_W:-4}
RUN_TIMEOUT=${RUN_TIMEOUT:-$((SECS+90))}
case "$GEN" in
  0x28) NW=${NW:-75}; EXPECT_BID=${EXPECT_BID:-0x00000028}; UNIMPL_ADDR=${UNIMPL_ADDR:-0x15C}
        KW=${KW:-'5 20 43 51 52 55 63 64 71 72 73 74'};;
  0x24) NW=${NW:-71}; EXPECT_BID=${EXPECT_BID:-0x00000024}; UNIMPL_ADDR=${UNIMPL_ADDR:-0x14C}
        KW=${KW:-'5 20 43 51 52 55 63 64'};;
  *) echo "GEN must be 0x28 or 0x24"; exit 3;;
esac
export NW EXPECT_BID UNIMPL_ADDR

[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root (run via peer_ssh.py --sudo)"; exit 3; }
[ -x "$CHURN" ] || { echo "PRECHECK_FAIL CHURN not executable: $CHURN"; exit 3; }

echo "### C1M_BEGIN tag=$TAG gen=$GEN secs=$SECS run_timeout=$RUN_TIMEOUT churn_extra='$CHURN_EXTRA' $(date +%s.%N)"
echo "### CHURN_MD5 $(md5sum $CHURN | awk '{print $1}')"
echo "### CHURN_SIZE $(stat -c %s $CHURN)"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID UNIMPL=$UNIMPL_ADDR KW='$KW'"

echo "--- fd limit (must cover ~${SECS}x100 open fds) ---"
echo "ULIMIT_BEFORE soft=$(ulimit -Sn) hard=$(ulimit -Hn) want=$ULIMIT"
ulimit -n $ULIMIT 2>&1; echo "ULIMIT_SET_RC=$?"
echo "ULIMIT_AFTER soft=$(ulimit -Sn) hard=$(ulimit -Hn)"

echo "--- leftover precheck (must be empty) ---"
pgrep -a p7b_tcp_churn && { echo "PRECHECK_FAIL leftover p7b_tcp_churn"; exit 3; }
pgrep -a p7b_tcp_sink && { echo "PRECHECK_FAIL leftover p7b_tcp_sink"; exit 3; }
pgrep -a tcpdump && { echo "PRECHECK_FAIL leftover tcpdump"; exit 3; }
echo "LEFTOVER_CLEAN"
rm -f /tmp/c1_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/c1_${TAG}_*"; exit 3; }
rm -rf "$DUMPDIR" 2>/dev/null; mkdir -p "$DUMPDIR" || { echo "PRECHECK_FAIL cannot mkdir $DUMPDIR"; exit 3; }

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

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF_/carrier
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (single, 'ctl'): full 'tcp port 8080', snaplen 128, ${RING_C}MBx${RING_W} ring ---"
nohup tcpdump -i $IF_ -s 128 -B 262144 -C $RING_C -W $RING_W -w /tmp/c1_${TAG}_ctl.pcap \
   "tcp port 8080" </dev/null > /tmp/c1_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/c1_${TAG}_ctl.err || exit 4
echo "CTL_PID=$CTLPID"

echo "--- board snapshot ring (background; one point per ~0.15 s) ---"
( while :; do
    echo "SNAP_T $(date +%s.%N)"
    bash $S snap ${TAG} $KW 2>&1
    sleep 0.15
  done ) > /tmp/c1_${TAG}_snap.log 2>&1 &
SNAPPID=$!
echo "SNAP_PID=$SNAPPID"

echo "--- peer kernel counters (before) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/c1_${TAG}_nstat_pre.txt
cat /tmp/c1_${TAG}_nstat_pre.txt

echo "--- SNAP_PRE (explicit) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW 2>&1 | tee /tmp/c1_${TAG}_pre.txt

echo "--- main run: p7b_tcp_churn (timeout ${RUN_TIMEOUT}s; churn window ${SECS}s + hold 5s) ---"
T0=$(date +%s.%N)
timeout -k 5 $RUN_TIMEOUT $CHURN --host $BOARD --port 8080 \
    --connect-interval-ms 10 --rcvbuf 1048576 --seconds $SECS \
    --max-conns $MAXCONN --dump-prefix-dir "$DUMPDIR" --dump-max $DUMP_MAX --hold-s 5 \
    $CHURN_EXTRA > /tmp/c1_${TAG}_churn.txt 2> /tmp/c1_${TAG}_churn.err &
CPID=$!
echo "CHURN_PID=$CPID"

# wait for CHURN_SUM (printed after the connection window, before hold-s) then SNAP_MID
MID=0
for i in $(seq 1 $((RUN_TIMEOUT*4))); do
  if ! kill -0 $CPID 2>/dev/null; then break; fi
  grep -q '^CHURN_SUM' /tmp/c1_${TAG}_churn.txt 2>/dev/null && { MID=1; break; }
  sleep 0.25
done
if [ $MID -eq 1 ]; then
  echo "--- SNAP_MID (in hold window, before exit FIN flood) $(date +%s.%N) ---"
  bash $S snap ${TAG}_MID $KW 2>&1 | tee /tmp/c1_${TAG}_mid.txt
else
  echo "--- SNAP_MID SKIPPED (CHURN_SUM not seen before exit; kill -0 check) $(date +%s.%N) ---"
fi
wait $CPID; RC_CHURN=$?
T1=$(date +%s.%N)
echo "### CHURN_RC=$RC_CHURN T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
[ "$RC_CHURN" = "124" ] && echo "CHURN_TIMEOUT_KILLED (RUN_TIMEOUT=${RUN_TIMEOUT}s)"

echo "--- SNAP_POST (explicit; after exit FIN flood) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW 2>&1 | tee /tmp/c1_${TAG}_post.txt

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq|TcpExtDelayedACKs|TcpExtDelayedACKLocked|TcpExtDelayedACKLost|TcpExtTCPPureAcks|TcpExtTCPHPAcks) ' > /tmp/c1_${TAG}_nstat_post.txt
cat /tmp/c1_${TAG}_nstat_post.txt

echo "--- teardown: stop snapshot ring + pcap ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $CTLPID ctl

echo "--- pcap stats (tcpdump self-report) ---"
tail -3 /tmp/c1_${TAG}_ctl.err
ls -la /tmp/c1_${TAG}_*.pcap* 2>&1
sha256sum /tmp/c1_${TAG}_*.pcap* 2>&1

echo "--- churn witness lines (verbatim) ---"
grep -E '^CHURN_(OPTS|ULIMIT|RCVBUF|NEEDLE|TARGET|LIMITS|CAP|WARN|DUMP_LIMIT)' /tmp/c1_${TAG}_churn.txt
echo "--- churn stderr (verbatim; empty=clean) ---"
cat /tmp/c1_${TAG}_churn.err
echo "--- CHURN_SUM (verbatim) ---"
grep -E '^CHURN_SUM|^CHURN_DONE' /tmp/c1_${TAG}_churn.txt

echo "--- restart@off distribution ---"
echo "conns_reported=$(grep -c '^CHURN conn=' /tmp/c1_${TAG}_churn.txt)"
grep -oE 'restart@off=[^ ]+' /tmp/c1_${TAG}_churn.txt | sort | uniq -c | sort -rn | head -20
echo "--- restart@off=-1 candidate lines (first 10) ---"
grep -E '^CHURN conn=.*restart@off=-1' /tmp/c1_${TAG}_churn.txt | head -10
echo "--- sample conn lines (first 3 / last 3) ---"
grep '^CHURN conn=' /tmp/c1_${TAG}_churn.txt | head -3
grep '^CHURN conn=' /tmp/c1_${TAG}_churn.txt | tail -3
echo "--- CHURN_T trajectory (first 3 / last 3) ---"
grep '^CHURN_T' /tmp/c1_${TAG}_churn.txt | head -3
grep '^CHURN_T' /tmp/c1_${TAG}_churn.txt | tail -3
echo "--- CHURN_DUMP lines count / dump dir listing ---"
grep -c '^CHURN_DUMP' /tmp/c1_${TAG}_churn.txt
ls "$DUMPDIR" | wc -l
ls -la "$DUMPDIR" | head -5
du -sh "$DUMPDIR"

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF_/carrier
echo -n "SS_ESTAB_8080="; ss -tan state established '( dport = :8080 )' 2>/dev/null | wc -l
echo -n "SS_ALL_8080="; ss -tan '( dport = :8080 or sport = :8080 )' 2>/dev/null | wc -l
pgrep -a p7b_tcp_churn; pgrep -a tcpdump; echo "(empty = no leftover processes)"
echo "### C1M_END tag=$TAG $(date +%s.%N)"
