#!/bin/bash
# r1_aging_test.sh -- R1 half-open aging board criteria (0x40).
#   ARM B first (1 free slot needed): live TCP connection with ACK history,
#     idle > WAIT, must still receive data (not aged; aging requires !ack_seen).
#   ARM A then: 8 raw SYNs fill half-open -> wait WAIT -> 8 new raw SYNs
#     => W7 +8 / W52 low +8 on 0x40 (baseline 0x3F: W7 +0).
#   Design aging latency = HO_LIM(8) x ORPHAN_TICK(429.4967 ms) ~ 3.44 s
#   => WAIT default 6.0 s (>=1.5 tick margin; a 4.5 s default leaves only 0.2 tick).
#   usage: bash /tmp/r1_aging_test.sh [wait_s]
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
WAIT=${1:-6.0}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
echo "BID=$(reg 0x04)"
echo "=== ARM B: live TCP, ACK history, idle ${WAIT}s ==="
ip netns exec nsa python3 - "$WAIT" <<'PY'
import socket, sys, time
wait = float(sys.argv[1])
s = socket.socket(); s.settimeout(5)
try:
    s.connect(("192.168.100.2", 8080))
except Exception as e:
    print("ARM_B connect_fail=%s" % e); raise SystemExit(0)
n = 0; t0 = time.time()
while n < 4096 and time.time()-t0 < 3:
    try:
        b = s.recv(4096)
        if not b: break
        n += len(b)
    except socket.timeout:
        break
print("ARM_B first_bytes=%d" % n)
time.sleep(wait)
got = 0; t0 = time.time()
while got < 4096 and time.time()-t0 < 3:
    try:
        b = s.recv(4096)
        if not b: break
        got += len(b)
    except socket.timeout:
        break
print("ARM_B after_idle_bytes=%d" % got)
s.close()
PY
sleep 0.5
echo "=== ARM A: fill 8 half-open raw SYNs ==="
bash /tmp/raw_probe_table.sh 8 44000
echo "=== ARM A: wait ${WAIT}s (aging) ==="
sleep "$WAIT"
echo "=== ARM A: probe 8 new raw SYNs ==="
bash /tmp/raw_probe_table.sh 8 45000
