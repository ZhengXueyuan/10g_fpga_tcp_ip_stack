#!/bin/bash
# run_tb_app_ho.sh -- R1 half-open aging unit gate on a Linux host with Vivado xsim.
#   Proven on the peer (192.168.0.38) 2026-11-08; the LD_LIBRARY_PATH line is required
#   because xsim needs libncurses.so.5, shipped under .xinstall (Ubuntu/24).
#   usage: bash run_tb_app_ho.sh [repo_root]
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=${1:-$(cd "$HERE/../.." && pwd)}
V=/opt/AMD/2025.2/Vivado
NCL=/opt/AMD/.xinstall/2025.2/lib/lnx64.o/Ubuntu/24
source "$V/settings64.sh" >/dev/null 2>&1 || true
export LD_LIBRARY_PATH="$NCL:${LD_LIBRARY_PATH:-}"
cd "$REPO" || exit 2
rm -rf "$HERE/xsim.dir"
"$V/bin/xvlog" -work xil_defaultlib rtl/fifo_sync.v rtl/app_ctrl.v tb/tb_app_ho.v > "$HERE/xvlog.log" 2>&1 || { echo "[XVLOG FAIL]"; tail -5 "$HERE/xvlog.log"; exit 1; }
"$V/bin/xelab" -debug typical -L xil_defaultlib xil_defaultlib.tb_app_ho -s tb_ho > "$HERE/xelab.log" 2>&1 || { echo "[XELAB FAIL]"; tail -5 "$HERE/xelab.log"; exit 1; }
"$V/bin/xsim" tb_ho -runall > "$HERE/xsim.log" 2>&1 || { echo "[XSIM FAIL]"; tail -5 "$HERE/xsim.log"; exit 1; }
grep -E 'TB_RESULT PASS|CHECK FAIL|^A:|^B:|^C:' "$HERE/xsim.log" | tail -10
grep -q 'TB_RESULT PASS' "$HERE/xsim.log" || exit 1
exit 0
