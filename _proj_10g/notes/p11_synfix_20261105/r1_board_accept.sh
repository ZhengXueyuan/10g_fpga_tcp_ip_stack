#!/bin/bash
# r1_board_accept.sh -- R1 (half-open slot aging) board acceptance for BID 0x40.
#
#   Runs ON THE PEER (192.168.0.38). The board must already be burned to 0x40
#   (see burn_0x40_board.sh) -- this script NEVER programs / never touches QSPI.
#
#   Sections
#     ID    : BID / window geometry / UNIMPL address / both carriers
#     B     : live connection with ACK history + idle WAIT => still receives (not aged)
#     B2    : 8 concurrent live connections, synchronous idle WAIT => all resume
#     A     : 8 raw SYNs fill half-open; wait WAIT; 8 fresh raw SYNs
#             => expect W7 +8  (0x3F baseline = W7 +0, archived)
#     T     : aging latency + race window: fill 8 half-open, then probe a real
#             connection every 100 ms until it succeeds => measured latency,
#             and every probe that succeeds must transfer the full payload.
#             Design value = HO_LIM x ORPHAN_TICK = 8 x 429.4967 ms ~ 3.44 s.
#     C     : cross-port race (BOTH 10G links are cabled: .2 via nsa, .4 via nsb);
#             probabilistic because the board has no cid readout.
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

#------------------------------------------------------------- ARM B2 --------
# 8 concurrent live connections, all idle for WAIT seconds at the same time.
# This is the design-study criterion "8 live connections + ACK history + idle >
# aging latency => still transfers, no false aging".  Python threads are enough
# here: this is a functional criterion (the C++ bench has no pause/resume).
echo "=== ARM_B2_BEGIN 8 concurrent live conns, synchronous idle ${WAIT}s ==="
ip netns exec nsa python3 - "$WAIT" <<'PY' 2>&1 | tee "$OUT/arm_b2.txt"
import socket, sys, time, threading
wait = float(sys.argv[1])
N = 8
bar = threading.Barrier(N)
res = [None]*N
def worker(i):
    try:
        s = socket.socket(); s.settimeout(5)
        s.connect(("192.168.100.2", 8080))
        n = 0
        while n < 65536:
            b = s.recv(65536)
            if not b: break
            n += len(b)
        bar.wait(timeout=20)      # all 8 are now live + have ACK history
        time.sleep(wait)          # synchronous idle > aging latency
        got = 0; t0 = time.time()
        while got < 65536 and time.time()-t0 < 5:
            try:
                b = s.recv(65536)
            except socket.timeout:
                break
            if not b: break
            got += len(b)
        s.close()
        res[i] = (n, got)
    except Exception as e:
        res[i] = ("exc:%s" % e, 0)
        try: bar.abort()
        except Exception: pass
ts = [threading.Thread(target=worker, args=(i,)) for i in range(N)]
for t in ts: t.start()
for t in ts: t.join()
ok = sum(1 for r in res if r and isinstance(r[0], int) and r[0] > 0 and r[1] > 0)
for i, r in enumerate(res):
    print("ARM_B2 conn%d first=%s after_idle=%s" % (i, r[0], r[1]))
print("ARM_B2 ok=%d/%d %s" % (ok, N, "PASS" if ok == N else "FAIL"))
PY
echo "=== ARM_B2_END ==="

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
# W52 = {estab_events[31:16], estab_count[15:0]}  (board 0x3F 2026-11-08 20:0x:
# W52=0x0ad10008 with 8 half-open slots left over => estab = low 16, NOT >>16)
echo "ARM_A W52_pre=$W52A0 W52_post=$W52A2 estab_pre=$((W52A0 & 0xFFFF)) estab_post=$((W52A2 & 0xFFFF))"
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
      OK=1; LAT=$(awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.2f", b-a}'); break
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
# Cross-port race.  BOTH 10G links are cabled (probed 2026-11-08 20:0x:
# nsb -> 192.168.100.4 answers ping, carrier 1/1), so this arm IS runnable.
# The cid space is GLOBAL (MAX_TCP_CONN=8 shared by both ports) and slot_dead is a
# global bitmap, so the H-2/L-3 risk is "port0 ages cid k while port1's ADD takes
# cid k".  There is no cid readout on the board => this is a PROBABILISTIC race:
# fill one port with 8 half-open, then hammer the other port with short transfers
# across the whole aging window; every transfer must pass.
echo "=== ARM_C_BEGIN cross-port race (probabilistic; no cid readout) ==="
C_OK=0; C_TOT=0
bash /tmp/raw_probe_table.sh 8 47000 > "$OUT/arm_c_fill.txt" 2>&1   # port0 half-open
for i in $(seq 1 12); do
  C_TOT=$((C_TOT+1))
  if ip netns exec nsb timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.4 --port 8080 \
       --conns 1 --maxbytes 1048576 --seconds 8 --poll-ms 1000 --stall-n 2 \
       --abort-rst --check lane8 --no-pin > "$OUT/arm_c_p1_$i.txt" 2>&1 \
     && grep -q 'SINK_CONN 0 OK' "$OUT/arm_c_p1_$i.txt"; then C_OK=$((C_OK+1)); fi
  sleep 0.4
done
echo "ARM_C port1_only ok=$C_OK/$C_TOT (port0 had 8 half-open aging concurrently)"
[ "$C_OK" -eq "$C_TOT" ] && echo "ARM_C PASS" || echo "ARM_C FAIL"
# symmetric direction: port1 half-open, port0 transfers
#   (port1 raw-SYN tooling = /tmp/raw_probe_table_p1.sh + raw_syn_{burst,table_probe}_p1.py,
#    iface enp1s0f0np0 / SIP 192.168.100.101 / DIP 192.168.100.4; validated on 0x3F:
#    1 raw SYN => W6 +1, W7 +0 under a full table)
C2_OK=0; C2_TOT=0
bash /tmp/raw_probe_table_p1.sh 8 48000 > "$OUT/arm_c_fill_p1.txt" 2>&1 || true
for i in $(seq 1 6); do
  C2_TOT=$((C2_TOT+1))
  if ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 \
       --conns 1 --maxbytes 1048576 --seconds 8 --poll-ms 1000 --stall-n 2 \
       --abort-rst --check lane8 --no-pin > "$OUT/arm_c_p0_$i.txt" 2>&1 \
     && grep -q 'SINK_CONN 0 OK' "$OUT/arm_c_p0_$i.txt"; then C2_OK=$((C2_OK+1)); fi
  sleep 0.4
done
echo "ARM_C port0_only ok=$C2_OK/$C2_TOT"
[ "$C2_OK" -eq "$C2_TOT" ] && echo "ARM_C_REV PASS" || echo "ARM_C_REV FAIL (or port1 fill unavailable)"
echo "=== ARM_C_END ==="

echo "=== R1_ACCEPT_DONE $STAMP dir=$OUT ==="
