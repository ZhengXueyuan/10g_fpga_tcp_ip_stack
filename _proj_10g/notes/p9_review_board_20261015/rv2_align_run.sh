#!/bin/bash
# RV2: 逐 case 跑两工具 (固定/原版), 每例限时 900 s; 输出逐条落盘 (不依赖上层缓冲)。
cd "$(dirname "$0")"
PY=/c/Users/zhxue/anaconda3/python.exe
T=../p9_board_0x27_k0_20261015/_tools
O=$T/align_check2_orig.py
F=$T/align_check2_fixed.py
S=rv2_align_synth
OUT=rv2_ALIGN_CASES.txt
: > $OUT
for c in A B C; do
  case $c in
    A) P=$S/caseA_hole1seg.pcap;   D="wire 层洞(中段缺 1 整段, 内容连续)" ;;
    B) P=$S/caseB_lost8B.pcap;     D="内容丢字 8B (真断点)" ;;
    C) P=$S/caseC_phasejump.pcap;  D="真相位跳 @100000 (+23456)" ;;
  esac
  for t in fixed orig; do
    if [ $t = fixed ]; then TOOL=$F; else TOOL=$O; fi
    echo "== case $c ($D) | $t ==" >> $OUT
    PYTHONIOENCODING=utf-8 timeout 900 $PY -u "$TOOL" "$P" 8080 2>&1 | grep -v "^  \.\.\. verified" >> $OUT
    echo "   [RC=$?]" >> $OUT
  done
done
# case D: 相位跳 5MB (abs 面外) —— 只跑 fixed, 限时 600 s 观察是否响亮快失败还是磨
echo "== case D (相位跳 +5MB, abs 面外) | fixed, timeout 600 ==" >> $OUT
PYTHONIOENCODING=utf-8 timeout 600 $PY -u "$F" $S/caseD_jump5MB.pcap 8080 2>&1 | grep -v "^  \.\.\. verified" >> $OUT
echo "   [RC=$? (124=timeout 被杀)]" >> $OUT
# case E/F
PYTHONIOENCODING=utf-8 timeout 900 $PY -u "$F" $S/caseE_misshead.pcap 8080 2>&1 | grep -v "^  \.\.\. verified" | sed 's/^/E_fixed /' >> $OUT
echo "E_FIXED_RC=$?" >> $OUT
PYTHONIOENCODING=utf-8 timeout 900 $PY -u "$F" $S/caseF_shorttail.pcap 8080 2>&1 | grep -v "^  \.\.\. verified" | sed 's/^/F_fixed /' >> $OUT
echo "F_FIXED_RC=$?" >> $OUT
echo "ALL_DONE" >> $OUT
