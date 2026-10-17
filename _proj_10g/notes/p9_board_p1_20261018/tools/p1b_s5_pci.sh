#!/bin/bash
# p1b_s5_pci.sh -- best-effort S-4/S-5: remove ONLY p0's PCI function (0000:01:00.0) to try to
#   stop the peer TX laser, then rescan.  p1 is a separate function (0000:01:00.1) and must stay up.
#   Root required.  Never touches QSPI.
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p1b_snap.sh
IF=enp1s0f0np0
IF1=enp1s0f1np1
DEV=0000:01:00.0
statusline(){
  echo -n "p0 carrier="; cat /sys/class/net/$IF/carrier 2>&1
  echo -n "p0 carchg="; cat /sys/class/net/$IF/carrier_changes 2>&1
  echo -n "p1 carrier="; cat /sys/class/net/$IF1/carrier 2>&1
  echo -n "p1 carchg="; cat /sys/class/net/$IF1/carrier_changes 2>&1
}
echo "=== P1BOARD-PCIREMOVE $(date +%s.%N) $(date) ==="
nmcli device set $IF managed no 2>&1 || true
ip link set $IF up 2>&1 || true
sleep 1
statusline
echo "--- SNAP PRE ---"
bash $S snap PCIRM_PRE 76 77 78 79 80 81 82
echo "--- remove $DEV t=$(date +%s.%N) ---"
echo 1 > /sys/bus/pci/devices/$DEV/remove
echo "REMOVE_RC=$?"
sleep 1
if [ -e /sys/class/net/$IF ]; then echo "P0_IFACE=PRESENT"; else echo "P0_IFACE=GONE"; fi
if [ -e /sys/class/net/$IF1 ]; then echo "P1_IFACE=PRESENT"; else echo "P1_IFACE=GONE"; fi
statusline
for i in $(seq 1 15); do
  echo "--- DN sample $i t=$(date +%s.%N) ---"
  bash $S snap S5_DN_$i 76 77 78 79 80 81 82
  sleep 1
done
echo "--- rescan t=$(date +%s.%N) ---"
echo 1 > /sys/bus/pci/rescan
echo "RESCAN_RC=$?"
for i in $(seq 1 40); do
  C=$(cat /sys/class/net/$IF/carrier 2>/dev/null)
  [ "$C" = "1" ] && { echo "P0_BACK after ${i}s t=$(date +%s.%N)"; break; }
  sleep 1
done
statusline
for i in $(seq 1 10); do
  echo "--- UP sample $i t=$(date +%s.%N) ---"
  statusline
  bash $S snap S5_UP_$i 76 77 78 79 80 81 82
  sleep 1
done
echo "--- SNAP FINAL ---"
bash $S snap PCIRM_FINAL 76 77 78 79 80 81 82
statusline
echo "=== P1BOARD-PCIREMOVE-END $(date +%s.%N) ==="
