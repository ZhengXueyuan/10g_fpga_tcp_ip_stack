#!/bin/bash
# verify_0x3C_f2.sh -- F2 (FIN 优先级) 板级 A/B 主判据。
#   每轮：.4 口 8 条连接（单会话 app 只服务 2 条，其余 6 条无板→对端数据、被关闭
#   ⇒ 旧码 FIN 泄漏）；轮末在 .2 口做一条正常 connect。
#   期望：0x3B 负臂第 2 轮后 .2 connect 失败（表满）；0x3C 正臂每轮都成功。
#   用法: bash verify_0x3C_f2.sh 0x3B|0x3C
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
EXPECT=${1:-0x3C}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; }
BID=$(reg 0x04); BIDN=$(printf '%d' "$BID" 2>/dev/null); EXPN=$(printf '%d' "$EXPECT" 2>/dev/null)
echo "BID=$BID ($BIDN) EXPECT=$EXPECT ($EXPN)"
if [ -z "${BIDN:-}" ] || [ "$BIDN" != "$EXPN" ]; then echo "BID_MISMATCH => ABORT"; exit 2; fi
bash /tmp/env_setup_robust.sh >/tmp/f2env.log 2>&1
grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/f2env.log | tail -3
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
snap; echo "T0 W52=$(reg 0xF0) W97=$(reg 0x1A4)"
for r in 1 2; do
  echo "=== ROUND $r: .4 zero-data leak round ==="
  for i in 0 1 2 3 4 5 6 7; do
    ip netns exec nsb timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.4 --port 8080 --conns 1 \
        --maxbytes 4294967296 --seconds 8 --poll-ms 5000 --stall-n 3 --check lane8 --no-pin \
        > $P/f2_${r}_$i.txt 2>&1 &
    sleep 0.5
  done
  wait
  for i in 0 1 2 3 4 5 6 7; do
    printf 'R%s P%s %s\n' "$r" "$i" "$(grep -oE 'bytes=[0-9]+|fail_conns=[0-9]+' $P/f2_${r}_$i.txt | head -2 | tr '\n' ' ')"
  done
  snap; echo "R$r END W52=$(reg 0xF0) W97=$(reg 0x1A4)"
  echo "--- ROUND $r: .2 8-conn probe ---"
  ok=0
  for j in 0 1 2 3 4 5 6 7; do
    ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
        --maxbytes 4294967296 --seconds 8 --poll-ms 5000 --stall-n 3 --check lane8 --no-pin \
        > $P/f2_probe_${r}_$j.txt 2>&1 &
    sleep 0.3
  done
  wait
  for j in 0 1 2 3 4 5 6 7; do
    if grep -q 'conns=1 fail_conns=0' $P/f2_probe_${r}_$j.txt; then ok=$((ok+1)); fi
    printf 'PROBE%s_%s %s\n' "$r" "$j" "$(grep -oE 'conns=[0-9]+|fail_conns=[0-9]+|why=[0-9]+' $P/f2_probe_${r}_$j.txt | head -3 | tr '\n' ' ')"
  done
  echo "R$r PROBE_SUCCESS=$ok/8"
done
snap; echo "TEND W52=$(reg 0xF0) W97=$(reg 0x1A4)"
