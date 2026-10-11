#!/bin/bash
# run_paylen_matrix.sh -- P8: 数据报长度矩阵诊断 (哪些长度能被板上 app 收下)
#   每次: 快照(W0/W1/W10/W11/W13/W70) -> 发 K 字节 (定速) -> 快照 -> 打印差分
#   用法(root): K=65536 MBPS=20 bash run_paylen_matrix.sh "8 9 16 32 64 1472"
set -u
K=${K:-65536}
MBPS=${MBPS:-20}
cd /tmp/p8_board
W="0 1 10 11 13 70"
for PL in ${1:-"8 9 16 32 64 1472"}; do
  echo "=== PAYLEN=$PL K=$K MBPS=$MBPS ==="
  bash p7b_snap.sh snap plA_$PL $W > /tmp/p8_board/snapa_$PL.txt 2>&1 || echo SNAP_A_FAIL
  grep -E '^W(0|1|10|11|13|70) ' /tmp/p8_board/snapa_$PL.txt
  timeout -k 5 60 ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes $K --mbps $MBPS \
        --batch 1 --paylen $PL --seconds 30 > /tmp/p8_board/srcpl_$PL.log 2>&1
  echo "SRC_RC=$?  $(grep -E 'UDP_SUM' /tmp/p8_board/srcpl_$PL.log | head -1)"
  sleep 1
  bash p7b_snap.sh snap plB_$PL $W > /tmp/p8_board/snapb_$PL.txt 2>&1 || echo SNAP_B_FAIL
  grep -E '^W(0|1|10|11|13|70) ' /tmp/p8_board/snapb_$PL.txt
  echo "--- 差分 (用 python 算, 十进制) ---"
  python3 - "$PL" <<'EOF'
import re, sys
pl = sys.argv[1]
def load(p):
    d = {}
    for ln in open(p):
        m = re.match(r'^W(\d+)\s+\S+\s+\S+\s+(\S+)', ln)
        if m: d[int(m.group(1))] = int(m.group(2), 16) & 0xFFFFFFFF
    return d
a = load(f"/tmp/p8_board/snapa_{pl}.txt"); b = load(f"/tmp/p8_board/snapb_{pl}.txt")
for w in (0, 1, 10, 11, 13, 70):
    print(f"dW{w} = {(b.get(w,0)-a.get(w,0)) & 0xFFFFFFFF}")
EOF
done
echo "MATRIX_DONE"
