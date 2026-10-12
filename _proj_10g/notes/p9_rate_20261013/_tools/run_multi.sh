#!/bin/bash
# run_multi.sh -- P9 线速档补测: **N 源 (有界) + 单窗 --stream 抓取**, 可循环 WINDOWS 次 (逐窗 = 独立窗口).
#   结构继承 run_win.sh; 差异: ① NPROC 个发端 (各 --bytes PER, 总交付 = NPROC*PER)
#                          ② --chunk 可配 (探"宿主 read 轮换空档"面)
#                          ③ 每窗独立 tag (TAG_rNN) + 前后快照 + 外部墙钟
#   用法(对端 root): TAG=A1 NPROC=1 K=134217728 CHUNK=8388608 WINDOWS=30 SECS=2 nohup bash run_multi.sh > A1.out 2>&1 &
set -u
D=${D:-/tmp/p9_rate}; cd "$D" || { echo "FATAL: no $D"; exit 3; }
TOOLS=${P7B_TOOLS:-/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools}
export NW=${NW:-71} EXPECT_BID=${EXPECT_BID:-0x00000023}
TAG=${TAG:-M00}
K=${K:-134217728}                 # 单窗抓取字节 (== Σ源交付; K%8==0)
NPROC=${NPROC:-1}
PER=${PER:-$((K / NPROC))}        # 每源字节 (PER%4==0; NPROC>1 时 K 必须能被整除)
MBPS=${MBPS:-0}                   # 每源线上 Mbps (0=满速)
PAYLEN=${PAYLEN:-1472}
BATCH=${BATCH:-32}
CHUNK=${CHUNK:-8388608}
SECS=${SECS:-2}                   # mir_dump 看门狗 (截"源已尽但最后一 read 块不满"的 stall)
SRC_SECS=${SRC_SECS:-90}
SAMPLE_MS=${SAMPLE_MS:-1000}
SETTLE=${SETTLE:-0.3}
DECL=${DECL:-}
OUT=${OUT:-/dev/null}
BUFMB=${BUFMB:-128}               # ⭐ cap 探针用 1024 (1 GiB); 常设档保持 128
CORES=${CORES:-}                  # ⭐ 空格分隔的核号表 (轮转给 NPROC 个源; 缺省 = 各源自选 ⇒ 4 源会全挤同一核!)
ARM_GAP=${ARM_GAP:-1}
WINDOWS=${WINDOWS:-1}
MOFF=${MOFF:-0}                   # NPROC>1 时各源 --off (图案交错, 与 verify 不兼容 ⇒ 用 0)
WORDS=${WORDS:-"5 11 13 70"}
snap(){ NW=$NW EXPECT_BID=$EXPECT_BID bash ./p7b_snap.sh snap "$1" $WORDS 2>&1; }

for w in $(seq -f "%02g" 1 "$WINDOWS"); do
  T=${TAG}_r${w}
  T0=$(date +%s.%N)
  echo "=== WIN ${T} K=$K NPROC=$NPROC PER=$PER MBPS=$MBPS CHUNK=$CHUNK SECS=$SECS T0=$T0"
  PRE=$(snap "${T}_pre"); echo "$PRE"
  echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败 (窗 ${T})"; exit 3; }
  W11HEX=$(echo "$PRE" | awk '/^W11 /{print $NF}' | head -1)
  case "$W11HEX" in 0x*|0X*) ;; *) echo "FATAL: 取不到 W11 ('$W11HEX')"; exit 3;; esac
  OFF=$(( W11HEX ))
  if [ -n "${FIXOFF:-}" ]; then
    OFF=$FIXOFF
    echo "OFF_FIX: W11=$W11HEX 但 FIXOFF 生效 => OFF=$OFF (源与 verify 同值即可; app 侧 LFSR 已失步, 见报告)"
  else
    echo "OFF_AUTO: W11=$W11HEX => OFF=$OFF"
  fi
  timeout -k 5 $(( ${SECS%.*} + 120 )) ./p7b_mir_dump --bid "$EXPECT_BID" --bytes "$K" --stream --src udp --pat-off "$OFF" \
        --buf-mb "$BUFMB" --chunk "$CHUNK" --sample-ms "$SAMPLE_MS" --settle "$SETTLE" --seconds "$SECS" $DECL \
        --out "$OUT" > "mir_${T}.log" 2>&1 &
  TPID=$!
  sleep 0.3
  # 读侧亲和见证 (工具自身未接 p7b_affinity.h ⇒ 从外部抓它到底跑在哪些核上)
  echo "READER_CPUS_ALLOWED=$(grep -m1 Cpus_allowed_list /proc/$TPID/status 2>/dev/null | tr -d '\t') READER_CPU=$(awk '{print $39}' /proc/$TPID/stat 2>/dev/null)"
  sleep "$(awk -v g="$ARM_GAP" 'BEGIN{v=g-0.3; if(v<0)v=0; printf "%.2f", v}')"
  TS=$(date +%s.%N)
  SPIDS=""
  for p in $(seq 1 "$NPROC"); do
    OFF_P=$OFF
    [ "$NPROC" -gt 1 ] && OFF_P=$MOFF
    COREOPT=""
    if [ -n "$CORES" ]; then
      c=$(echo "$CORES" | tr ' ' '\n' | sed -n "$(( (p - 1) % $(echo "$CORES" | wc -w) + 1 ))p")
      [ -n "$c" ] && COREOPT="--core $c"
    fi
    timeout -k 5 $((SRC_SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes "$PER" --mbps "$MBPS" \
        --batch "$BATCH" --paylen "$PAYLEN" --off "$OFF_P" --seconds "$SRC_SECS" $COREOPT > "src_${T}_p${p}.log" 2>&1 &
    SPIDS="$SPIDS $!"
  done
  # 数据起点轮询 (W11 变化 = app 收到第一字节; 给"源慢启动/与工具窗口错开"一个可判据)
  W11PRE=$(( W11HEX ))
  ONSET=NONE
  ENDT=$(awk -v t="$(date +%s.%N)" 'BEGIN{printf "%.4f", t+40}')
  while :; do
    cur=$("$TOOLS/reg_rw" /dev/xdma0_user 0x4C w 2>/dev/null | tail -1 | sed 's/.*: *//' | grep -oE '^0x[0-9a-fA-F]+')
    if [ -n "$cur" ] && [ "$(( cur ))" != "$W11PRE" ]; then ONSET=$(date +%s.%N); break; fi
    now=$(date +%s.%N)
    awk -v a="$now" -v b="$ENDT" 'BEGIN{exit !(a>b)}' && break
    sleep 0.15
  done
  TREL="NONE"
  [ "$ONSET" != NONE ] && TREL=$(awk -v a="$ONSET" -v b="$TS" 'BEGIN{printf "%.3f", a-b}')
  echo "DATA_ONSET=$ONSET (源起后 ${TREL}s)"
  for sp in $SPIDS; do wait "$sp"; done
  TE=$(date +%s.%N)
  wait $TPID; TOOL_RC=$?
  TZ=$(date +%s.%N)
  echo "TOOL_RC=$TOOL_RC TS=$TS TE=$TE TZ=$TZ"
  echo "--- mir_dump 日志 (逐字) ---"
  cat "mir_${T}.log"
  echo "--- 发端 UDP_SUM (逐进程) ---"
  for p in $(seq 1 "$NPROC"); do echo "[p$p] $(grep -E 'UDP_SUM' "src_${T}_p${p}.log" | tail -1)"; done
  echo "--- PIN 见证 (逐进程) ---"
  for p in $(seq 1 "$NPROC"); do
    echo "[p$p] $(grep -oE 'PIN_CPU=[0-9a-z]+' "src_${T}_p${p}.log" | head -1) $(grep -oE 'PIN_ALLOWED_MASK=[0-9a-f]+' "src_${T}_p${p}.log" | head -1)"
  done
  echo "--- post 快照 ---"
  snap "${T}_post" || echo SNAP_POST_FAIL
  echo "=== END ${T} $(date +%s.%N)"
done
echo "ALL_DONE $(date +%s.%N)"
