#!/bin/bash
# r1_board_accept.sh -- R1 (half-open slot aging) board acceptance for BID 0x40.
#
#   Runs ON THE PEER (192.168.0.38). The board must already be burned to 0x40
#   (see burn_0x40_board.sh) -- this script NEVER programs / never touches QSPI.
#
#   Sections
#     ID    : BID / window geometry / UNIMPL address / both carriers
#     B     : live connection with ACK history + idle WAIT => still receives (not aged)
#     A     : 8 raw SYNs fill half-open; wait WAIT; 8 fresh raw SYNs
#             => expect W7 +8  (0x3F baseline = W7 +0, archived)
#     T     : aging latency + race window: fill 8 half-open, then probe a real
#             connection every 100 ms until it succeeds => measured latency,
#             and every probe that succeeds must transfer the full payload.
#             Design value = HO_LIM x ORPHAN_TICK = 8 x 429.4967 ms ~ 3.44 s.
#     C     : cross-port same-cid => NOT RUN (only one 10G link is connected)
#
#   usage: bash /tmp/r1_board_accept.sh [wait_s] [mb]
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
P=/home/a/p11_bench
WAIT=${1:-6.0}
MB=${2:-16777216}
STAMP=$(date +%Y%m%d_%H%M%S)
OUT=$P/r1_accept_$STAMP
mkdir -p "$OUT"

reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
u32(){ printf '%u' "$(( $1 & 0xffffffff ))"; }

echo "=== ID_BEGIN $STAMP ==="
BID=$(reg 0x04); echo "ID_BID=$BID"
echo "ID_02=$($T/reg_rw /dev/xdma0_user 0x02 w 2>/dev/null | tail -1 | sed 's/.*: *//')"
# geometry (authoritative, wrapper_p4.v localparam SNAP_NW_P6E): 98 words W0..W97,
# unimplemented boundary = 0x1B8 (checked by burn_0x40_board.sh; printed here too)
echo "ID_W97=$(reg 0x1A4)"
echo "ID_UNIMPL_1B8=$(reg 0x1B8)"
echo "ID_CARRIER=$(reg 0x08)"
[ "$BID" = "0x00000040" ] && echo "ID_BID_OK" || echo "ID_BID_FAIL (want 0x00000040)"
echo "=== ID_END ==="

#--------------------------------------------------------------- ARM B --------
echo "=== ARM_B_BEGIN live connection, ACK history, idle ${WAIT}s ==="
ip netns exec nsa python3 - "$WAIT" <<'PY' 2>&1 | tee "$OUT/arm_b.txt"
import socket, sys, time
wait = float(sys.argv[1])
s = socket.socket(); s.settimeout(5)
try:
    s.connect(("192.168.100.2", 8080))
except Exception as e:
    print("ARM_B connect_fail=%s" % e); raise SystemExit(0)
n = 0; t0 = time.time()
while n < 65536 and time.time()-t0 < 3:
    try:
        b = s.recv(65536)
        if not b: break
        n += len(b)
    except socket.timeout:
        break
print("ARM_B first_bytes=%d" % n)
time.sleep(wait)
got = 0; t0 = time.time()
while got < 65536 and time.time()-t0 < 5:
    try:
        b = s.recv(65536)
        if not b: break
        got += len(b)
    except socket.timeout:
        break
print("ARM_B after_idle_bytes=%d" % got)
print("ARM_B %s" % ("PASS" if (n > 0 and got > 0) else "FAIL"))
s.close()
PY
echo "=== ARM_B_END ==="

#--------------------------------------------------------------- ARM A --------
echo "=== ARM_A_BEGIN fill 8 half-open raw SYNs ==="
snap; W7A0=$(u32 $(reg 0x3C)); W6A0=$(u32 $(reg 0x38)); W52A0=$(u32 $(reg 0xF0))
echo "ARM_A PRE W6=$W6A0 W7=$W7A0 W52=$W52A0"
bash /tmp/raw_probe_table.sh 8 44000 2>&1 | tee "$OUT/arm_a_fill.txt" | grep -E 'W6_|W7_|W52_'
snap; W7A1=$(u32 $(reg 0x3C)); W6A1=$(u32 $(reg 0x38))
echo "ARM_A fill dW6=$((W6A1-W6A0)) dW7=$((W7A1-W7A0))"
echo "=== ARM_A wait ${WAIT}s (aging) ==="
sleep "$WAIT"
echo "=== ARM_A probe 8 fresh raw SYNs ==="
bash /tmp/raw_probe_table.sh 8 45000 2>&1 | tee "$OUT/arm_a_probe.txt" | grep -E 'W6_|W7_|W52_'
snap; W7A2=$(u32 $(reg 0x3C)); W6A2=$(u32 $(reg 0x38)); W52A2=$(u32 $(reg 0xF0))
DW7=$((W7A2-W7A1)); DW6=$((W6A2-W6A1)); DW52=$((W52A2-W52A0))
echo "ARM_A probe dW6=$DW6 dW7=$DW7 dW52=$DW52"
# criterion: the 8 fresh SYNs elicit 8 SYN-ACKs => dW7 == 8 (0x3F baseline: 0)
[ "$DW7" -eq 8 ] && echo "ARM_A_AGING PASS (dW7=8)" || echo "ARM_A_AGING FAIL (dW7=$DW7 want 8)"
echo "=== ARM_A_END ==="

#--------------------------------------------------------------- ARM T --------
echo "=== ARM_T_BEGIN aging latency / race window ==="
# Fill 8 half-open (if the table is not already full this re-fills it).
bash /tmp/raw_probe_table.sh 8 46000 > "$OUT/arm_t_fill.txt" 2>&1
T0=$(date +%s.%N)
OK=0; LAT=""
for i in $(seq 1 80); do
  if ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 \
       --conns 1 --maxbytes "$MB" --seconds 10 --poll-ms 1000 --stall-n 2 \
       --abort-rst --check lane8 --no-pin > "$OUT/arm_t_probe_$i.txt" 2>&1; then
    if grep -q 'SINK_CONN 0 OK' "$OUT/arm_t_probe_$i.txt"; then
      OK=1; LAT=$(echo "$(date +%s.%N) - $T0" | bc); break
    fi
  fi
  sleep 0.1
done
echo "ARM_T first_success=$OK latency_s=${LAT:-none} (design ~3.44 s = 8 x 429.4967 ms)"
if [ "$OK" = "1" ]; then
  grep -h 'SINK_CONN 0' "$OUT/arm_t_probe_"*.txt | tail -3
  echo "ARM_T_PROBE_PASS"
else
  echo "ARM_T_PROBE_FAIL (no real connection succeeded within 8 s)"
fi
echo "=== ARM_T_END ==="

#--------------------------------------------------------------- ARM C --------
echo "=== ARM_C cross-port same-cid: NOT_RUN (only one 10G link connected) ==="

echo "=== R1_ACCEPT_DONE $STAMP dir=$OUT ==="
