#!/bin/bash
# =============================================================================
# arm_p3win.sh -- P-3 window "hit" configuration arm (runs on the PEER box)
#
#   Purpose: drive one board-level arm of the P-3 window experiment
#            (design doc = _proj_10g/notes/p9_p3win_design_20261016/DESIGN.md sec.2,
#             configurations A / B / C -- cfg A = "full-speed stream -> abort -> reconnect").
#
#   Parent = B4 round k0_arm_b4.sh.  Kept VERBATIM from it:
#     * the three pcap-correctness hard gates: arming (wait 'listening on', 15 s = hard fail)
#       / graceful stop (SIGINT + wait exit; -9 fallback is REPORTED) / loss report tail
#     * identity gate, snapshot ring, explicit SNAP_PRE / SNAP_POST, nstat pre/post,
#       FRESHNESS gate (empty or missing '^SINK_SUM' => reported, never silent)
#   Delta vs k0_arm_b4.sh (this round's tool delta):
#     * GEN is an explicit parameter (0x28 | 0x24) -> EXPECT_BID / NW / KW sets
#     * the sink command line is a FULL parameter (SINK_CMD), not a fixed arg list
#     * KW (ring)   = '66 67 68 69 63 64 55 52 43 51 20 5'
#       (66/67/68/69 = wininstall / cap-side / ack_adv / win-at-winstall; 63/64 = app stall
#        counters; 55 = retx; 52 = app tx frames; 43 = tx words; 51 = app tx bytes; 20 fps; 5 clk)
#     * KW2 (PRE/POST) = KW + '71 72 73 74' on 0x28 (E12 four counters, needed by the
#       precondition gates); AUTO-DROPPED on 0x24 -- 0x13C..0x148 are the MIR four words in
#       the 0x24 geometry, reading them as E12 would be a misread (design doc sec.1.4).
#     * the design doc's new ctl-pcap reading item is echoed at the end (board-side FIN/RST)
#
#   Usage:  bash arm_p3win.sh <TAG> <GEN> <SINK_CMD...>
#     TAG      = arm tag (all files = /tmp/k0_${TAG}_*)
#     GEN      = 0x28 | 0x24   (board generation; drives EXPECT_BID / NW / KW defaults)
#     SINK_CMD = FULL sink command line AFTER the binary, e.g. (cfg A, from the design doc)
#                --host 192.168.100.2 --port 8080 --rcvbuf 1048576 --conns 100000 \
#                --seconds 120 --maxbytes 2097152 --poll-ms 300 --stall-n 2 --check lane8 --abort-rst
#   Env overrides: KW KW2 EXPECT_BID NW SINK_EXTRA RUN_TIMEOUT RING_C RING_W
#
#   Examples:
#     # cfg A on 0x28 (clean expectation) / cfg A on 0x24 (defect arm) -- SAME SINK_CMD:
#     bash arm_p3win.sh A0 0x28 --host 192.168.100.2 --port 8080 --rcvbuf 1048576 \
#       --conns 100000 --seconds 120 --maxbytes 2097152 --poll-ms 300 --stall-n 2 --check lane8 --abort-rst
#     bash arm_p3win.sh A1 0x24 --host 192.168.100.2 --port 8080 --rcvbuf 1048576 \
#       --conns 100000 --seconds 120 --maxbytes 2097152 --poll-ms 300 --stall-n 2 --check lane8 --abort-rst
#     # cfg A' (FIN arm): same line WITHOUT --abort-rst
#     # cfg C (same 4-tuple): add  --local-port 40000
#   Run as:  python tools/peer_ssh.py --sudo "cd /tmp/p7b_biz && bash arm_p3win.sh ..."
# =============================================================================
set -u
TAG=${1:?usage: arm_p3win.sh TAG GEN SINK_CMD...}; GEN=${2:?GEN = 0x28 | 0x24}; shift 2
[ $# -ge 1 ] || { echo "SINK_CMD missing (full sink args after the binary)"; exit 3; }
SINK_CMD="$*"
IF=enp1s0f1np1
BOARD=192.168.100.2
D=/dev/xdma0_user
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_biz/p7b_snap.sh
RING_C=${RING_C:-300}; RING_W=${RING_W:-8}
RUN_TIMEOUT=${RUN_TIMEOUT:-420}
SINK_EXTRA=${SINK_EXTRA:-}

# ---- GEN -> board identity + KW sets -----------------------------------------
case "$GEN" in
  0x28|0x00000028) DEF_BID=0x00000028; DEF_NW=75; E12=1 ;;
  0x24|0x00000024) DEF_BID=0x00000024; DEF_NW=71; E12=0 ;;
  *) echo "GEN must be 0x28 or 0x24 (got '$GEN')"; exit 3 ;;
esac
export EXPECT_BID=${EXPECT_BID:-$DEF_BID} NW=${NW:-$DEF_NW}
KW=${KW:-'66 67 68 69 63 64 55 52 43 51 20 5'}
if [ "$E12" = "1" ]; then KW2=${KW2:-"$KW 71 72 73 74"}; else KW2=${KW2:-"$KW"}; fi

# ---- precondition hard gates (B1/B4 lineage) ---------------------------------
[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL not root => tcpdump/reg_rw blocked (run via peer_ssh.py --sudo)"; exit 3; }
rm -f /tmp/k0_${TAG}_* 2>/dev/null || { echo "PRECHECK_FAIL cannot clean /tmp/k0_${TAG}_* (owned by someone else?)"; exit 3; }

arm_tcpdump(){  # wait for 'listening on' (the arming gate); 15 s timeout = hard fail
  local f=$1 t=0
  while [ $t -lt 150 ]; do
    grep -q 'listening on' "$f" 2>/dev/null && { echo "TCPDUMP_ARMED $f (waited ~$((t/10))s)"; return 0; }
    sleep 0.1; t=$((t+1))
  done
  echo "TCPDUMP_ARM_FAIL 15s without 'listening on': $f"; return 1
}
stop_tcpdump(){  # SIGINT graceful stop + wait for exit (this is the flush gate)
  local p=$1 n=$2 i=0
  kill -INT "$p" 2>/dev/null
  while [ $i -lt 150 ]; do kill -0 "$p" 2>/dev/null || { echo "$n STOPPED_GRACEFULLY (~$((i/10))s)"; return 0; }; sleep 0.1; i=$((i+1)); done
  echo "$n did not exit in 15 s => KILL -9"; kill -9 "$p" 2>/dev/null; return 1
}

echo "### K0_BEGIN tag=$TAG gen=$GEN $(date +%s.%N)"
echo "### SINK_CMD: $SINK_CMD $SINK_EXTRA"
echo "### SNAP_MD5 $(md5sum $S | awk '{print $1}')"
echo "### SINK_MD5 $(md5sum /tmp/p7b_biz/p7b_tcp_sink | awk '{print $1}')"
echo "### SNAP_ARGS NW=$NW EXPECT_BID=$EXPECT_BID KW='$KW' KW2='$KW2'"
echo "### TCPDUMP $(tcpdump --version 2>/dev/null | head -1)"

echo "--- board identity gate (before run) ---"
bash $S id; echo "ID_RC=$?"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
echo -n "NETADDR="; ip -4 addr show $IF | grep -o 'inet [0-9./]*'
echo -n "ROUTE_GET="; ip route get $BOARD | head -1

echo "--- pcap (1): control frames census (FIN/RST, whole window; tiny volume) ---"
nohup tcpdump -i $IF -s 0 -w /tmp/k0_${TAG}_ctl.pcap \
   "tcp port 8080 and (tcp[tcpflags] & (tcp-fin|tcp-rst) != 0)" \
   </dev/null > /tmp/k0_${TAG}_ctl.err 2>&1 &
CTLPID=$!
arm_tcpdump /tmp/k0_${TAG}_ctl.err || exit 4

echo "--- pcap (2): ring full-frame (board -> peer) ---"
rm -f /tmp/k0_${TAG}_full*
nohup tcpdump -i $IF -s 0 -B 262144 -C $RING_C -W $RING_W -w /tmp/k0_${TAG}_full.pcap \
   "tcp port 8080 and src host $BOARD" </dev/null > /tmp/k0_${TAG}_full.err 2>&1 &
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

echo "--- SNAP_PRE (explicit; E12 + reconciliation words) $(date +%s.%N) ---"
bash $S snap ${TAG}_PRE $KW2 2>&1 | tee /tmp/k0_${TAG}_pre.txt
echo "PRE_RC=$?"

echo "--- main run: sink (current deployment; SINK_CMD from argv) ---"
T0=$(date +%s.%N)
timeout -k 5 $RUN_TIMEOUT /tmp/p7b_biz/p7b_tcp_sink $SINK_CMD $SINK_EXTRA \
  > /tmp/k0_${TAG}_sink.txt 2>&1
RC=$?
T1=$(date +%s.%N)
echo "### SINK_RC=$RC T0=$T0 T1=$T1 T1-T0=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", b-a}')"
# freshness gate: the log must be from THIS run and have reached the end (stale-log trap, #72 kin)
if [ ! -s /tmp/k0_${TAG}_sink.txt ]; then echo "SINK_LOG_EMPTY => stop"; exit 4; fi
grep -q '^SINK_SUM' /tmp/k0_${TAG}_sink.txt || echo "SINK_SUM_MISSING (run did not finish; RC=$RC)"

echo "--- SNAP_POST (explicit; right after sink exit) $(date +%s.%N) ---"
bash $S snap ${TAG}_POST $KW2 2>&1 | tee /tmp/k0_${TAG}_post.txt
echo "POST_RC=$?"

# =============================================================================
# PRECONDITION ("front") GATES -- CHECKPOINT COMMENTS, NOT A VERDICT.
#   Verdict authority stays with the criteria owner.  An arm that fails G1/G2 must be
#   logged as "no discriminating power" (never as "defect absent"; global #92).
#
#   G1  d(W72+W74) > 0        -- 0x28 arms ONLY (E12 words 71..74; see KW2 above).
#                                0x24 has NO E12 instrument -> record "not measurable here",
#                                extrapolate from the same-config 0x28 arm (design doc sec.1.4).
#   G2  mean W51 rate >= 1 Gbps -- W51 = app_pattern TX payload bytes; rate = dW51*8/dt.
#                                READ TOGETHER WITH W63/W64 (app stall cycles): a W51 mean
#                                hides stall structure (design doc sec.1.3 note 2).
#   G3  three-state identity   -- dW71 == d(apply-on-the-fly) + dW72 + dW74,
#                                with d(apply-on-the-fly) = dW73 - dW72
#                                (round-B4 measured form; equivalently dW71 == dW73 + dW74
#                                 whenever every sw_req lands exactly one apply).
#   EXPECTATION GATE (design doc sec.4):  d(W72+W74) * P(H) >= 3
#                                with P(H) = W51_rate_Bps / (1460 * 156.25e6).
#   The quantities come from SNAP_PRE/SNAP_POST (above) and/or the ring log; the offline
#   parsers are parse_snap_timeline.py (K0 round) and k0_analyze.sh.
# =============================================================================

echo "--- peer kernel counters (after) ---"
nstat -az 2>/dev/null | grep -E '^(TcpInSegs|TcpOutSegs|TcpRetransSegs|TcpExtTCPOFOQueue|TcpExtTCPFastRetrans|TcpExtTCPACKSkippedSeq) ' > /tmp/k0_${TAG}_nstat_post.txt
cat /tmp/k0_${TAG}_nstat_post.txt

echo "--- teardown: stop snapshot ring + pcaps (SIGINT graceful) ---"
kill $SNAPPID 2>/dev/null; sleep 0.3
stop_tcpdump $FULLPID full
stop_tcpdump $CTLPID ctl

echo "--- pcap stats (tcpdump self-report; drops/gaps = readout contamination witness) ---"
echo "[ctl]";  tail -3 /tmp/k0_${TAG}_ctl.err
echo "[full]"; tail -3 /tmp/k0_${TAG}_full.err
ls -la /tmp/k0_${TAG}_*.pcap* 2>&1
sha256sum /tmp/k0_${TAG}_*.pcap* 2>&1

echo "--- sink summary (verbatim) ---"
grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_RCVBUF_ORDER|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/k0_${TAG}_sink.txt | head -80

echo "--- board state (after) ---"
echo -n "BID_0x04="; $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n "SCRATCH_0x08="; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n "CARRIER="; cat /sys/class/net/$IF/carrier
pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo "(empty = no leftover processes)"

# ---- ctl-pcap reading item (design doc sec.2.4-3): does the BOARD send any control frame? ----
#   Extract /tmp/k0_${TAG}_ctl.pcap and check src==BOARD entries (B4H3: ZERO board-side frames
#   across the whole window).  Board-side FIN/RST presence/absence is the direct H1/H2 witness.
echo "### K0_END tag=$TAG $(date +%s.%N)"
