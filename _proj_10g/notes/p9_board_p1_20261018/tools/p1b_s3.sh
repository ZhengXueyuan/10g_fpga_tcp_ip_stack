#!/bin/bash
# p1b_s3.sh -- S-3: board SFP1 TX_DIS negative control (0x08 bit0) + S-4/S-5 peer-side TX-off arm.
#   usage: p1b_s3.sh txdis      -> 0x08 bit0 1 for 4 s then 0 (expect peer p0 carrier 1->0->1, p1 unaffected)
#   usage: p1b_s3.sh linkdown   -> ip link set enp1s0f0np0 down/up (S-4 LOS / S-5 clock-stop attempt)
set -u
MODE=${1:?usage: p1b_s3.sh txdis|linkdown}
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p1b_snap.sh
IF=enp1s0f0np0
IF1=enp1s0f1np1
D=/dev/xdma0_user
rd8(){ $T/reg_rw $D 0x08 w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
wr8(){ $T/reg_rw $D 0x08 w "$1" >/dev/null 2>&1; }
car(){ cat /sys/class/net/$1/carrier 2>&1; }
cch(){ cat /sys/class/net/$1/carrier_changes 2>&1; }
statusline(){
  echo -n "p0 carrier="; car $IF; echo -n "p0 carchg="; cch $IF
  echo -n "p1 carrier="; car $IF1; echo -n "p1 carchg="; cch $IF1
}
echo "=== P1BOARD-${MODE^^} $(date +%s.%N) $(date) ==="
echo -n "SCRATCH_0x08_PRE="; rd8
statusline
echo "--- SNAP PRE ---"
bash $S snap ${MODE}_PRE 76 77 78 79 80 81 82

case "$MODE" in
txdis)
  echo "--- SET 0x08=0x1 (sfp1_tx_dis=1) t=$(date +%s.%N) ---"
  wr8 0x1
  echo -n "SCRATCH_0x08_AFTER_SET="; rd8
  sleep 4
  echo "--- during TX_DIS (t+4s) ---"
  statusline
  bash $S snap S3_DIS 76 77 78 79 80 81 82
  sleep 2
  echo "--- during TX_DIS (t+6s) ---"
  statusline
  bash $S snap S3_DIS2 76 77 78 79 80 81 82
  echo "--- RESTORE 0x08=0x0 t=$(date +%s.%N) ---"
  wr8 0x0
  echo -n "SCRATCH_0x08_AFTER_RESTORE="; rd8
  sleep 6
  echo "--- after restore (t+6s) ---"
  statusline
  bash $S snap S3_POST 76 77 78 79 80 81 82
  ;;
linkdown)
  echo "--- ip link set $IF down t=$(date +%s.%N) ---"
  ip link set $IF down
  echo "LINK_DOWN_RC=$?"
  for i in $(seq 1 12); do
    echo "--- DN sample $i t=$(date +%s.%N) ---"
    statusline
    bash $S snap S4_DN_$i 76 77 78 79 80 81 82
    sleep 1
  done
  echo "--- ip link set $IF up t=$(date +%s.%N) ---"
  ip link set $IF up
  echo "LINK_UP_RC=$?"
  for i in $(seq 1 30); do
    C=$(car $IF)
    [ "$C" = "1" ] && { echo "CARRIER_UP after ${i}s t=$(date +%s.%N)"; break; }
    sleep 1
  done
  statusline
  for i in $(seq 1 10); do
    echo "--- UP sample $i t=$(date +%s.%N) ---"
    statusline
    bash $S snap S4_UP_$i 76 77 78 79 80 81 82
    sleep 1
  done
  ;;
esac
echo "--- SNAP FINAL ---"
bash $S snap ${MODE}_FINAL 76 77 78 79 80 81 82
echo -n "SCRATCH_0x08_FINAL="; rd8
statusline
echo "=== P1BOARD-${MODE^^}-END $(date +%s.%N) ==="
