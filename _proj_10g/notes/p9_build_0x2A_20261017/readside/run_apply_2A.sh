#!/bin/bash
# 0x2A 读侧链式同步 —— 一键执行 (照 0x28 轮顺序)。
# 前置: 矩阵已跑完 (本脚本会改 `sim/p6e_pcie/*` 与读侧工具, 会污染 gate 输入绑定)。
set -u
PY=C:/Users/zhxue/anaconda3/python.exe
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
TOOL=../../p7b_readside_bid1c_20261011/apply_readside_bid1c.py

echo "== 1) snapshot before =="
$PY snapshot_targets.py > TARGET_SHA_BEFORE_BID2A.txt 2>&1 || exit 1
tail -1 TARGET_SHA_BEFORE_BID2A.txt

echo "== 2) splice tool --apply =="
$PY splice_2A.py --apply > SPLICE_APPLY_OUTPUT.txt 2>&1 || exit 1
tail -3 SPLICE_APPLY_OUTPUT.txt

echo "== 3) apply readside --bid 0x2A =="
$PY "$TOOL" --bid 0x2A --apply > APPLY_BID2A_OUTPUT.txt 2>&1
RC=$?
echo "apply RC=$RC"
tail -3 APPLY_BID2A_OUTPUT.txt
[ $RC -eq 0 ] || exit 1

echo "== 4) snapshot after + diff =="
$PY snapshot_targets.py > TARGET_SHA_AFTER_BID2A.txt 2>&1 || exit 1
diff TARGET_SHA_BEFORE_BID2A.txt TARGET_SHA_AFTER_BID2A.txt > READ_SIDE_DIFF_NUMSTAT.txt
echo "diff_rc=$? (1 = 有差异, 期望)"
grep -c '^<' READ_SIDE_DIFF_NUMSTAT.txt

echo "== 5) assert =="
$PY "$TOOL" --bid 0x2A --assert > ASSERT_BID2A_FINAL.txt 2>&1
echo "assert RC=$?"
tail -2 ASSERT_BID2A_FINAL.txt

echo "== 6) negctl x4 (post) =="
for n in table bid tier face; do
  $PY "$TOOL" --bid 0x2A --negctl=$n > NEGCTL_${n}_2A_POST.txt 2>&1
  echo "$n RC=$? $(grep -o 'NEGCTL_VERDICT[^⇒]*' NEGCTL_${n}_2A_POST.txt | head -1)"
done

echo "== 7) neg_rehearse (post) =="
$PY neg_rehearse_2A.py > NEG_REHEARSE_2A_POST.txt 2>&1
echo "neg_rehearse RC=$?"
tail -1 NEG_REHEARSE_2A_POST.txt

echo "== 8) window doc --apply =="
$PY patch_window_doc.py --apply > WINDOW_DOC_APPLY.txt 2>&1
echo "window doc RC=$?"
tail -1 WINDOW_DOC_APPLY.txt

echo "== 9) final face =="
$PY "$TOOL" --bid 0x2A --face > FACE_2A_FINAL.txt 2>&1
echo "face RC=$?"
tail -1 FACE_2A_FINAL.txt
echo "== DONE =="
