#!/bin/bash
# run_win_hw.sh -- 2026-10-13 宿主读循环诊断轮 **单窗协议** (结构继承 p9_rate/_tools/run_win.sh)
#   三处不同:
#     ① TOOL 可换: 老二进制 = /tmp/p9_rate/p7b_mir_dump (P9 轮原件) / 新仪器件 = /tmp/p9_hostread/p7b_mir_dump
#     ② 新参数 READLOG(0|1) · AIO(0=同步平铺) · CHUNK · PIN(读侧绑核; 空=不绑, 见证行照打)
#     ③ C4 相关量: 逐窗记 (a) 读侧 /proc/<pid>/stat 的 utime/stime 采样 (b) /proc/softirqs NET_RX 前后差
#        (c) NIC port_rx_bytes/packets 前后差 (泛洪速率见证, P9 同口径)
#   ⚠️ 密码只作 env 前缀; 本脚本不落任何口令。
#   用法(对端 root): TAG=W0 K=1073741824 MBPS=0 TOOL=/tmp/p9_hostread/p7b_mir_dump READLOG=1 bash run_win_hw.sh
set -u
D=${D:-/tmp/p9_hostread}; cd "$D" || { echo "FATAL: no $D"; exit 3; }
T=${P7B_TOOLS:-/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools}
export NW=${NW:-71} EXPECT_BID=${EXPECT_BID:-0x00000023}
TOOL=${TOOL:-/tmp/p9_hostread/p7b_mir_dump}
TAG=${TAG:-W0}
K=${K:-134217728}
MBPS=${MBPS:-0}
PAYLEN=${PAYLEN:-1472}
BATCH=${BATCH:-32}
SECS=${SECS:-30}
SRC_SECS=${SRC_SECS:-90}
SAMPLE_MS=${SAMPLE_MS:-1000}
CHUNK=${CHUNK:-}
READLOG=${READLOG:-0}
AIO=${AIO:-0}
PIN=${PIN:-}
SETTLE=${SETTLE:-0.3}
BUFMB=${BUFMB:-1024}
ARM_GAP=${ARM_GAP:-1}
SRC_PIN=${SRC_PIN:-}
OUT=${OUT:-/dev/null}
DECL=${DECL:-}
WORDS=${WORDS:-"0 1 5 10 11 13 70 46 47 48 49"}
NPROC=${NPROC:-1}    # source process count (each --bytes PER; FIXOFF=0 -> same off)
CORES=${CORES:-}     # space separated core list, rotated across sources
DUAL=${DUAL:-0}      # 2 ⇒ --dual 2 (两线程交错同步读)
STAG=${STAG:-}       # 非空 ⇒ --dual-stagger-ms 覆盖
HUGE=${HUGE:-0}      # 1 ⇒ --buf-huge (1 GiB 大页缓冲; 需 BUFMB=1024 的倍数)
FIXOFF=${FIXOFF:-}   # 非空 ⇒ 用固定 OFF (绕开源侧 O(off) LFSR 快进 = P9 纪律: 主跑一律 OFF=0)
snap(){ NW=$NW EXPECT_BID=$EXPECT_BID bash /tmp/p9_rate/p7b_snap.sh snap "$1" $WORDS 2>&1; }
T0=$(date +%s.%N)
echo "=== WIN ${TAG} K=$K MBPS=$MBPS PAYLEN=$PAYLEN BATCH=$BATCH SECS=$SECS SAMPLE_MS=$SAMPLE_MS CHUNK=${CHUNK:-def} READLOG=$READLOG AIO=$AIO PIN=${PIN:-none} TOOL=$TOOL T0=$T0"
echo "--- 环境见证 ---"
echo "TOOL_MD5=$(md5sum "$TOOL" | awk '{print $1}')"
grep -E "Adaptive RX|rx-usecs" <(ethtool -c enp1s0f1np1 2>/dev/null) | tr -d '\t' | tr '\n' ' '; echo
echo -n "CARRIER_PRE="; cat /sys/class/net/enp1s0f1np1/carrier
NIC_PRE=$(ethtool -S enp1s0f1np1 2>/dev/null | grep -E 'port_rx_bytes|port_rx_packets|port_tx_bytes|port_tx_packets' | tr -d '\t' | tr '\n' ' ')
SOFT_PRE=$(grep -E 'NET_RX|NET_TX' /proc/softirqs | tr -d '\t' | tr '\n' ' ')
echo "NIC_PRE: $NIC_PRE"
echo "SOFTIRQ_PRE: $SOFT_PRE"
echo "--- pre 快照 ---"
PRE=$(snap "${TAG}_pre"); echo "$PRE"
echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败"; exit 3; }
W11HEX=$(echo "$PRE" | awk '/^W11 /{print $NF}' | head -1)
case "$W11HEX" in 0x*|0X*) ;; *) echo "FATAL: 取不到 W11 ('$W11HEX')"; exit 3;; esac
OFF=$(( W11HEX ))
echo "OFF_AUTO: W11=$W11HEX => OFF=$OFF"
if [ -n "$FIXOFF" ]; then OFF=$FIXOFF; echo "OFF_FIX: W11=$W11HEX 但 FIXOFF 生效 => OFF=$OFF"; fi
TARGS="--bid $EXPECT_BID --bytes $K --stream --src udp --pat-off $OFF --buf-mb $BUFMB --sample-ms $SAMPLE_MS --settle $SETTLE --seconds $SECS"
[ "$READLOG" != "0" ] && TARGS="$TARGS --readlog $READLOG"
[ -n "$CHUNK" ] && TARGS="$TARGS --chunk $CHUNK"
[ "$AIO" != "0" ] && TARGS="$TARGS --aio $AIO --k-bytes $K"
[ "$HUGE" != "0" ] && TARGS="$TARGS --buf-huge"
[ "$DUAL" != "0" ] && TARGS="$TARGS --dual $DUAL"
[ -n "$STAG" ] && TARGS="$TARGS --dual-stagger-ms $STAG"
[ -n "$DECL" ] && TARGS="$TARGS $DECL"
echo "--- 起 mir_dump: $TOOL $TARGS ---"
echo "TOOL_ARGS: $TARGS"
TSTART=$(date +%s.%N)
if [ -n "$PIN" ]; then
  timeout -k 5 $((SECS+120)) taskset -c "$PIN" $TOOL $TARGS --out "$OUT" > "mir_${TAG}.log" 2>&1 &
else
  timeout -k 5 $((SECS+120)) $TOOL $TARGS --out "$OUT" > "mir_${TAG}.log" 2>&1 &
fi
TPID=$!
sleep 0.4
echo "READER_CPUS_ALLOWED=$(grep -m1 Cpus_allowed_list /proc/$TPID/status 2>/dev/null | tr -d '\t') READER_CPU_START=$(awk '{print $39}' /proc/$TPID/stat 2>/dev/null)"
# 读侧 CPU 采样 (1 Hz; 最多 120 行)
( for i in $(seq 1 120); do
    [ -r /proc/$TPID/stat ] || break
    awk -v i="$i" -v t="$(date +%s.%N)" '{print "READER_STAT i="i" t="t" utime="$14" stime="$15" threads="$20}' /proc/$TPID/stat 2>/dev/null
    sleep 1
  done ) > "rstat_${TAG}.log" 2>/dev/null &
RPID=$!
sleep "$(awk -v g="$ARM_GAP" 'BEGIN{v=g-0.4; if(v<0)v=0; printf "%.2f", v}')"
TS=$(date +%s.%N)
echo "--- 起发端 (有界: --bytes $K, --mbps $MBPS) TS=$TS ---"
PER=$((K / NPROC))
SPIDS=""
for p in $(seq 1 "$NPROC"); do
  COREOPT=""
  if [ -n "$CORES" ]; then
    c=$(echo "$CORES" | tr " " "\n" | sed -n "$(( (p - 1) % $(echo "$CORES" | wc -w) + 1 ))p")
    [ -n "$c" ] && COREOPT="--core $c"
  fi
  [ -n "$SRC_PIN" ] && COREOPT="--core $SRC_PIN"
  timeout -k 5 $((SRC_SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes "$PER" --mbps "$MBPS" --batch "$BATCH" --paylen "$PAYLEN" --off "$OFF" --seconds "$SRC_SECS" $COREOPT > "src_${TAG}_p${p}.log" 2>&1 &
  SPIDS="$SPIDS $!"
done
SRC_RC=0
for sp in $SPIDS; do wait "$sp" || SRC_RC=1; done
SRC_RC=$?
TE=$(date +%s.%N)
echo "SRC_RC=$SRC_RC TE=$TE"
wait $TPID; TOOL_RC=$?
TZ=$(date +%s.%N)
kill $RPID 2>/dev/null; wait $RPID 2>/dev/null
echo "TOOL_RC=$TOOL_RC TZ=$TZ (墙钟 TZ-TSTART=$(awk -v a=$TZ -v b=$TSTART 'BEGIN{printf "%.3f", a-b}')s)"
echo "--- mir_dump 日志 (逐字) ---"
cat "mir_${TAG}.log"
echo "--- 发端关键行 ---"
for p in $(seq 1 "$NPROC"); do echo "[p$p] $(grep -aE "PIN_CPU=|UDP_SUM" src_${TAG}_p${p}.log | tail -2 | tr "\n" " ")"; done
echo "--- post 快照 ---"
snap "${TAG}_post" || echo SNAP_POST_FAIL
NIC_POST=$(ethtool -S enp1s0f1np1 2>/dev/null | grep -E 'port_rx_bytes|port_rx_packets|port_tx_bytes|port_tx_packets' | tr -d '\t' | tr '\n' ' ')
SOFT_POST=$(grep -E 'NET_RX|NET_TX' /proc/softirqs | tr -d '\t' | tr '\n' ' ')
echo "NIC_POST: $NIC_POST"
echo "SOFTIRQ_POST: $SOFT_POST"
echo "--- 读侧 CPU 采样 (末 4 行; 全文在 rstat_${TAG}.log) ---"
tail -4 "rstat_${TAG}.log" 2>/dev/null || echo NO_RSTAT
echo "--- 文件 ---"
ls -la "$OUT" 2>&1 || true
echo "=== END ${TAG} $(date +%s.%N)"
