#!/bin/bash
# k0_analyze.sh -- K0 判据分析件（对端机就地跑）：拆连接 + 每连接绝对相位核查
#   用法: bash k0_analyze.sh <TAG> [SPORT]
#   依据 = DESIGN_v2.md §5.2-S4「就地分析（对端）：每连接 K0（绝对搜索）+ breaks + prefix_len」
#   ⚠️ 测量逻辑 100% 在 align_check2_fixed.py（设计件 §5.3 修订件）；split_conn_pcap.py 只做按 dport 拆分
set -u
TAG=${1:?usage: k0_analyze.sh TAG [SPORT]}
SPORT=${2:-8080}
[ "$(id -u)" = "0" ] || { echo "PRECHECK_FAIL 非 root (命名空间 /tmp/k0_* 归 root ⇒ 用 --sudo)"; exit 3; }
SPLIT=/tmp/k0_split_${TAG}
rm -rf "$SPLIT"; mkdir -p "$SPLIT"
echo "### K0AN_BEGIN tag=$TAG sport=$SPORT $(date +%s.%N)"
echo "--- 0) 工具身份 ---"
md5sum /tmp/p7b_biz/align_check2_fixed.py /tmp/p7b_biz/split_conn_pcap.py
sha256sum /tmp/p7b_biz/align_check2_fixed.py /tmp/p7b_biz/split_conn_pcap.py
echo "--- 1) 拆连接 (按 dport; 只搬数据, 不测量) ---"
SPORT=$SPORT python3 /tmp/p7b_biz/split_conn_pcap.py "$SPLIT" "$TAG" /tmp/k0_${TAG}_full.pcap*
echo "--- 2) 每连接: K0 (绝对) + breaks + verified_prefix (+ 重对齐行) ---"
for f in $(ls "$SPLIT"/*.pcap 2>/dev/null | sort); do
  b=$(basename "$f")
  echo "== CONN $b =="
  python3 /tmp/p7b_biz/align_check2_fixed.py "$f" $SPORT 2>&1 | tee "$SPLIT/$b.align2.log"
done
echo "### K0AN_END tag=$TAG $(date +%s.%N)"
