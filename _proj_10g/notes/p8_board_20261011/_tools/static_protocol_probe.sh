#!/bin/bash
# static_protocol_probe.sh -- P8 静态寄存器协议探针 (负对照 b/d/e; 只读 + 一次空读 DATA)
#   判据: (e) 逐字读 0x20..0x138 全 71 字 ⇒ MIR_STATUS.level 不变 (快照不偷数据)
#         (d) 读 0x14C (未实现) ⇒ level/unf 不变
#         (b) level==0 时读一次 MIR_DATA ⇒ 哨兵 0x5A5A5A5A + unf_sticky=1 + level 仍 0
#   用法(root): bash static_protocol_probe.sh
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
rd(){ $T/reg_rw $D "$1" w 2>/dev/null | tail -1 | sed 's/.*: //'; }
st(){ echo "MIR_STATUS=$1 level=$(( ($1) & 0xFFFF )) unf=$(( (($1) >> 16) & 1 )) any_drop=$(( (($1) >> 17) & 1 )) cap=$(( (($1) >> 18) & 1 )) ver=$(( (($1) >> 19) & 0xF )) src_sel=$(( (($1) >> 23) & 1 ))"; }

echo "=== BEFORE ==="
S0=$(rd 0x13C); st "$S0"
echo "--- (e) 逐字读快照 0x20..0x138 (71 字) ---"
nff=0
for i in $(seq 0 70); do
  A=$((0x20 + 4*i)); V=$(rd "$(printf 0x%X $A)")
  [ "$(echo "$V" | tr A-F a-f)" = "0xffffffff" ] && { nff=$((nff+1)); echo "  W$i @$(printf 0x%X $A) = $V (!!)"; }
done
echo "  快照 71 字读完; 其中 0xffffffff 个数 = $nff (期望 0)"
S1=$(rd 0x13C); st "$S1"
echo "--- (d) 读未实现地址 0x14C ---"
U=$(rd 0x14C); echo "  0x14C = $U (期望 0xffffffff)"
S2=$(rd 0x13C); st "$S2"
echo "--- (b) level==0 时读一次 MIR_DATA (0x140) → 期望哨兵 + unf_sticky=1 ---"
D1=$(rd 0x140); echo "  MIR_DATA = $D1 (期望 0x5a5a5a5a)"
S3=$(rd 0x13C); st "$S3"
echo "--- MIR_CTRL (0x144) 现值 ---"
C=$(rd 0x144); echo "  MIR_CTRL = $C"
echo "=== 判定行 (逐条打印, 不做 PASS/FAIL 裁定) ==="
echo "  (e) level: $((S0 & 0xFFFF)) -> $((S1 & 0xFFFF))  [快照 71 字读完]"
echo "  (d) level: $((S1 & 0xFFFF)) -> $((S2 & 0xFFFF))  [读 0x14C 后]"
echo "  (b) unf : $(( (S2 >> 16) & 1 )) -> $(( (S3 >> 16) & 1 ))  [空读 DATA 后]; level: $((S2 & 0xFFFF)) -> $((S3 & 0xFFFF))"
