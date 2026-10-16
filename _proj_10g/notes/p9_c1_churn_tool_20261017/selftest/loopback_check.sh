#!/bin/bash
# loopback_check.sh -- p7b_tcp_churn 回环自测（⛔ 不碰板；只跑 127.0.0.1；连接数 <=500；每跑 <=20 s）
#
# 覆盖（派单自测表）: 洪流+读干回环（建连率 / fd 计数 / bytes 增长 / 退出干净）
#   · --safe-close（旧 fd 数被控住） · 重启扫描三形态（off=0 / -1+落盘 / na）
#   · 边界响亮（非法值 RC=2） · ulimit 警告行 · 离线独立复核落盘内容
set -u
T=/tmp/c1_churn_selftest
BIN=/tmp/p7b_biz/p7b_tcp_churn
SRV=$T/fake_stream_server.py
PY=python3
PORT=18985
PASS=0; FAIL=0
mkdir -p "$T"
echo "=== loopback_check $(date -u +%FT%TZ) ==="
echo "host=$(hostname) ulimit_n=$(ulimit -n) bin_md5=$(md5sum "$BIN" | awk '{print $1}')"

chk_eq()  { local n=$1 a=$2 w=$3; if [ "$a" = "$w" ]; then echo "CHK PASS $n got=$a want=$w"; PASS=$((PASS+1)); else echo "CHK FAIL $n got=$a want=$w"; FAIL=$((FAIL+1)); fi; }
# ⚠️ 数值比较一律走 awk：**浮点读数**（rate_per_s / gap_max_ms）用 bash 的整数 `[ -ge ]`
#    会报 "integer expression expected" 而被 2>/dev/null 静默吞成 FAIL（run1 实测踩到, 4 条假 FAIL）
chk_rng() { local n=$1 a=$2 lo=$3 hi=$4
  if awk -v a="$a" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !((a+0) >= (lo+0) && (a+0) <= (hi+0))}'; then
    echo "CHK PASS $n got=$a range=$lo..$hi"; PASS=$((PASS+1))
  else
    echo "CHK FAIL $n got=$a range=$lo..$hi"; FAIL=$((FAIL+1))
  fi; }
sumline() { grep -E '^CHURN_SUM ' "$1" 2>/dev/null | tail -1; }
sfield()  { sumline "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/^ *//; s/^[^=]*=//'; }
connfield() { grep -E '^CHURN conn=' "$1" 2>/dev/null | grep -oE "(^| )$2=[^ ]+" | sed 's/^ *//; s/^[^=]*=//' | sort -u | tr '\n' ',' ; }

start_server() { # $1=mode $2=seconds $3=tag
  pkill -f "fake_stream_server.py --port $PORT" >/dev/null 2>&1
  sleep 0.2
  nohup $PY "$SRV" --port "$PORT" --seconds "$2" --mode "$1" > "$T/srv_$3.log" 2>&1 &
  for i in $(seq 1 80); do grep -q SRV_READY "$T/srv_$3.log" 2>/dev/null && return 0; sleep 0.1; done
  return 1
}
stop_server() { pkill -f "fake_stream_server.py --port $PORT" >/dev/null 2>&1; sleep 0.2; }

run_client() { # $1=tag $2=total_secs $3=fd_sample_at_s ; 其余 = 客户端参数
  local tag=$1 dur=$2 sat=$3; shift 3
  "$BIN" "$@" > "$T/$tag.out" 2> "$T/$tag.err" &
  local pid=$!
  sleep "$sat"
  local fd1=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
  local rem=$(awk -v d="$dur" -v s="$sat" 'BEGIN{r=d-s-0.25; if(r<0)r=0; printf "%.2f", r}')
  sleep "$rem"
  local fd2=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
  wait $pid
  RC=$?
  echo "$fd1 $fd2" > "$T/$tag.fds"
}

expect_rc2() { # $1=名字 ; 其余 = 必须被拒的参数
  local n=$1; shift
  "$BIN" "$@" >/dev/null 2> "$T/bad_$n.err"
  local rc=$?
  local e=$(wc -c < "$T/bad_$n.err" | tr -d ' ')
  if [ "$rc" = "2" ] && [ "$e" -gt 0 ]; then
    echo "CHK PASS bad_$n rc=2 stderr_bytes=$e :: $(head -c 120 "$T/bad_$n.err" | tr '\n' ' ')"
    PASS=$((PASS+1))
  else
    echo "CHK FAIL bad_$n rc=$rc stderr_bytes=$e"; FAIL=$((FAIL+1))
  fi
}

# ---------------------------------------------------------------------------
echo; echo "--- T1: mode=mid interval=10ms seconds=4 (建连率/fd/bytes/候选/落盘) ---"
mkdir -p "$T/dump_mid"; rm -f "$T/dump_mid"/*.bin
start_server mid 8 T1 || { echo "CHK FAIL T1_server_start"; FAIL=$((FAIL+1)); }
run_client T1 4 1.5 --host 127.0.0.1 --port $PORT --connect-interval-ms 10 --seconds 4 \
           --max-conns 450 --rcvbuf 1048576 --dump-prefix-dir "$T/dump_mid"
stop_server
chk_eq  T1_rc "$RC" 0
C=$(sfield "$T/T1.out" conns); R=$(sfield "$T/T1.out" rate_per_s); ND=$(sfield "$T/T1.out" nodata)
CD=$(sfield "$T/T1.out" candidates); DU=$(sfield "$T/T1.out" dumps); SK=$(sfield "$T/T1.out" dumps_skipped)
FY=$(sfield "$T/T1.out" dump_fail); BL=$(sfield "$T/T1.out" bytes)
chk_rng T1_conns "$C" 380 430
chk_rng T1_rate_per_s "$R" 93 107
chk_rng T1_nodata "$ND" 0 3
chk_rng T1_candidates "$CD" "$((C-6))" "$C"
chk_eq  T1_dumps "$DU" "$CD"
chk_eq  T1_dumps_skipped "$SK" 0
chk_eq  T1_dump_fail "$FY" 0
chk_eq  T1_bytes_8192x "$BL" "$((8192*(C-ND)))"
chk_eq  T1_conn_lines "$(grep -c '^CHURN conn=' "$T/T1.out")" "$C"
# ⚠️ 必须锚**前导空格**：行里还有 `scan_bytes=` / `prefix_bytes=`，裸 `bytes=[0-9]+` 会一起命中
#    （run1 实测踩到 ⇒ 400 条假 FAIL）
BADBYTES=$(grep -E '^CHURN conn=' "$T/T1.out" | grep -oE '(^| )bytes=[0-9]+' | cut -d= -f2 | grep -vxE '0|8192' | wc -l)
chk_eq  T1_bytes_values_in_0_or_8192 "$BADBYTES" 0
chk_eq  T1_opts_line "$(grep -c '^CHURN_OPTS connect_interval_ms=10 rcvbuf=1048576 seconds=4 safe_close=0 restart_scan=1$' "$T/T1.out")" 1
chk_eq  T1_ulimit_warn_ok0 "$(grep -c '^CHURN_ULIMIT .*ok=0$' "$T/T1.out")" 1
chk_eq  T1_ulimit_warn_stderr "$(grep -c 'CHURN_WARN RLIMIT_NOFILE' "$T/T1.err")" 1
chk_eq  T1_pin_bound "$(grep -cE 'PIN_CPU=[0-9]+' "$T/T1.out")" 1
FD1=$(cut -d' ' -f1 "$T/T1.fds"); FD2=$(cut -d' ' -f2 "$T/T1.fds")
chk_rng T1_fd_at_1p5s "$FD1" 100 200
chk_rng T1_fd_final "$FD2" "$((C-30))" "$((C+8))"
chk_rng T1_estab "$(sfield "$T/T1.out" estab)" "$((C-6))" "$C"
chk_rng T1_srv_accepted_last "$(grep -oE 'SRV_ACCEPTED n=[0-9]+' "$T/srv_T1.log" | tail -1 | cut -d= -f2)" "$((C-60))" "$C"
echo "  [T1 SUM] $(sumline "$T/T1.out")"
echo "  [T1 sample conn] $(grep -m1 '^CHURN conn=' "$T/T1.out")"
echo "  [T1 sample dump] $(grep -m1 '^CHURN_DUMP ' "$T/T1.out")"
echo "--- T1b: 离线独立复核 (落盘候选内不得含针) ---"
$PY "$T/offline_dump_check.py" "$T/dump_mid" --expect-files "$DU" --note T1mid > "$T/offline_T1.log" 2>&1
RC_OFF=$?
cat "$T/offline_T1.log"
chk_eq T1b_offline_rc "$RC_OFF" 0

echo; echo "--- T2: mode=mid interval=50ms seconds=10 (定时器刻度可判) ---"
start_server mid 15 T2 || { echo "CHK FAIL T2_server_start"; FAIL=$((FAIL+1)); }
run_client T2 10 2 --host 127.0.0.1 --port $PORT --connect-interval-ms 50 --seconds 10 --max-conns 250
stop_server
chk_eq  T2_rc "$RC" 0
C2=$(sfield "$T/T2.out" conns); R2=$(sfield "$T/T2.out" rate_per_s)
chk_rng T2_conns "$C2" 185 215
chk_rng T2_rate_per_s "$R2" 18 22
chk_rng T2_gap_max_ms "$(sfield "$T/T2.out" gap_max_ms)" 45 80

echo; echo "--- T3: mode=from0 interval=20ms seconds=4 (重启形态 off=0) ---"
mkdir -p "$T/dump_from0"; rm -f "$T/dump_from0"/*.bin
start_server from0 8 T3 || { echo "CHK FAIL T3_server_start"; FAIL=$((FAIL+1)); }
run_client T3 4 2 --host 127.0.0.1 --port $PORT --connect-interval-ms 20 --seconds 4 --max-conns 250 \
           --dump-prefix-dir "$T/dump_from0"
stop_server
chk_eq  T3_rc "$RC" 0
C3=$(sfield "$T/T3.out" conns); V0=$(sfield "$T/T3.out" verdict_off0)
chk_rng T3_conns "$C3" 185 215
chk_rng T3_verdict_off0 "$V0" "$((C3-5))" "$C3"
chk_eq  T3_candidates "$(sfield "$T/T3.out" candidates)" 0
chk_eq  T3_dumps "$(sfield "$T/T3.out" dumps)" 0
chk_eq  T3_dump_files "$(ls "$T/dump_from0" | wc -l)" 0
echo "  [T3 sample conn] $(grep -m1 '^CHURN conn=' "$T/T3.out")"

echo; echo "--- T4: mode=mid interval=10ms seconds=4 + --safe-close (fd 数被控住) ---"
start_server mid 8 T4 || { echo "CHK FAIL T4_server_start"; FAIL=$((FAIL+1)); }
run_client T4 4 2 --host 127.0.0.1 --port $PORT --connect-interval-ms 10 --seconds 4 --max-conns 450 --safe-close
stop_server
chk_eq  T4_rc "$RC" 0
C4=$(sfield "$T/T4.out" conns); CS=$(sfield "$T/T4.out" closed_safe)
chk_rng T4_conns "$C4" 380 430
FD4=$(cut -d' ' -f2 "$T/T4.fds")
chk_rng T4_live_fd_bounded "$FD4" 1 120
chk_rng T4_closed_safe "$CS" "$((C4-130))" "$C4"
chk_eq  T4_safe_close_witness "$(sfield "$T/T4.out" safe_close)" 1
echo "  [T4 fd samples (1.75s, final)] $(cat "$T/T4.fds")  conns=$C4 closed_safe=$CS"

echo; echo "--- T5: mode=sink interval=10ms seconds=3 (0 字节连接 => restart@off=na) ---"
start_server sink 7 T5 || { echo "CHK FAIL T5_server_start"; FAIL=$((FAIL+1)); }
run_client T5 3 1.5 --host 127.0.0.1 --port $PORT --connect-interval-ms 10 --seconds 3 --max-conns 350
stop_server
chk_eq  T5_rc "$RC" 0
C5=$(sfield "$T/T5.out" conns)
chk_rng T5_conns "$C5" 280 320
chk_eq  T5_nodata "$(sfield "$T/T5.out" nodata)" "$C5"
chk_eq  T5_candidates "$(sfield "$T/T5.out" candidates)" 0
chk_eq  T5_verdict_na "$(connfield "$T/T5.out" "restart@off")" "na,"
chk_eq  T5_bytes "$(sfield "$T/T5.out" bytes)" 0
echo "  [T5 sample conn] $(grep -m1 '^CHURN conn=' "$T/T5.out")"

echo; echo "--- T6: 边界响亮 (非法值 => RC=2 + stderr) ---"
expect_rc2 interval0    --connect-interval-ms 0
expect_rc2 intervalneg  --connect-interval-ms -5
expect_rc2 seconds0     --seconds 0
expect_rc2 rcvbuf_lo    --rcvbuf 100
expect_rc2 rcvbuf_hi    --rcvbuf 2000000000
expect_rc2 prefixkb0    --prefix-kb 0
expect_rc2 scan31       --scan-bytes 31
expect_rc2 scan_toobig  --scan-bytes 9999999
expect_rc2 port0        --port 0
expect_rc2 localport_hi --local-port 70000
expect_rc2 dumpmax_neg  --dump-max -1
expect_rc2 maxconns0    --max-conns 0
expect_rc2 hold_neg     --hold-s -1
expect_rc2 host_bogus   --host not-an-ip
expect_rc2 dumpdir_miss --dump-prefix-dir /nonexistent_c1_xyz
expect_rc2 unknown_arg  --nope
expect_rc2 missing_val  --seconds

echo; echo "--- T7: --help => RC=0 ---"
"$BIN" --help > "$T/help.out" 2>&1; chk_eq T7_help_rc "$?" 0
chk_rng T7_help_has_off "$(grep -c 'restart@off' "$T/help.out")" 1 9
"$BIN" --selftest > /dev/null 2>&1; chk_eq T8_selftest_rc "$?" 0
"$BIN" --selftest-scan > /dev/null 2>&1; chk_eq T8_selftest_scan_rc "$?" 0

echo
echo "=== LOOPBACK_CHECK $([ $FAIL = 0 ] && echo PASS || echo FAIL) PASS=$PASS FAIL=$FAIL $(date -u +%FT%TZ) ==="
exit $([ $FAIL = 0 ] && echo 0 || echo 1)
