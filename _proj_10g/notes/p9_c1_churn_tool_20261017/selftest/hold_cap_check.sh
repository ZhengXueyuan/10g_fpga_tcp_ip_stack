#!/bin/bash
# hold_cap_check.sh -- 补两条主门未覆盖的路径（⛔ 不碰板, 127.0.0.1）
#   E1 `--hold-s`：连接窗口结束后**进程仍活着、fd 仍开着、仍在读干**（退 FIN 洪泛的缓解手段，
#      README §4-c 推荐真臂用它 ⇒ 不能不测）
#   E2 `--max-conns` 上限：撞顶后打 `CHURN_CAP` 行、停止新建、跑完 RC=0
set -u
T=/tmp/c1_churn_selftest
BIN=/tmp/p7b_biz/p7b_tcp_churn
PY=python3
PORT=18986
PASS=0; FAIL=0
chk_eq()  { local n=$1 a=$2 w=$3; if [ "$a" = "$w" ]; then echo "CHK PASS $n got=$a want=$w"; PASS=$((PASS+1)); else echo "CHK FAIL $n got=$a want=$w"; FAIL=$((FAIL+1)); fi; }
chk_rng() { local n=$1 a=$2 lo=$3 hi=$4
  if awk -v a="$a" -v lo="$lo" -v hi="$hi" 'BEGIN{exit !((a+0) >= (lo+0) && (a+0) <= (hi+0))}'; then
    echo "CHK PASS $n got=$a range=$lo..$hi"; PASS=$((PASS+1))
  else echo "CHK FAIL $n got=$a range=$lo..$hi"; FAIL=$((FAIL+1)); fi; }
sumline() { grep -E '^CHURN_SUM ' "$1" 2>/dev/null | tail -1; }
sfield()  { sumline "$1" | grep -oE "(^| )$2=[^ ]+" | head -1 | sed 's/^ *//; s/^[^=]*=//'; }
pkill -f "fake_stream_server.py --port $PORT" >/dev/null 2>&1; sleep 0.2
nohup $PY "$T/fake_stream_server.py" --port "$PORT" --seconds 12 --mode mid > "$T/srv_E.log" 2>&1 &
for i in $(seq 1 80); do grep -q SRV_READY "$T/srv_E.log" 2>/dev/null && break; sleep 0.1; done

echo "--- E1: --seconds 3 --hold-s 3（窗口后必须仍活着/仍读干/不新建连接） ---"
S=$(date +%s.%N)
"$BIN" --host 127.0.0.1 --port $PORT --connect-interval-ms 10 --seconds 3 --hold-s 3 --max-conns 350 \
       > "$T/E1.out" 2> "$T/E1.err" &
PID=$!
sleep 2.5; FD_PRE=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
sleep 2.0; FD_HOLD=$(ls /proc/$PID/fd 2>/dev/null | wc -l)          # t≈4.5s > seconds=3（窗口已结束）
T_HOLD=$(grep -oE '^CHURN_T t=[0-9.]+' "$T/E1.out" | tail -1 | cut -d= -f2)
wait $PID; RC=$?
E=$(date +%s.%N)
WALL=$(awk -v a="$S" -v b="$E" 'BEGIN{printf "%.2f", b-a}')
chk_eq  E1_rc "$RC" 0
chk_rng E1_wall_s "$WALL" 5.8 8.0                                  # ≈ 3 + 3 + 收尾
chk_rng E1_fd_pre "$FD_PRE" 100 400
chk_rng E1_fd_in_hold "$FD_HOLD" 100 400                           # 窗口结束后 fd 仍开着
chk_rng E1_churn_t_during_hold "$T_HOLD" 3.5 6.5                   # 周期行打到 hold 里了
chk_eq  E1_conns "$(sfield "$T/E1.out" conns)" 300                 # 3s × 100/s ⇒ **没有**多建
chk_eq  E1_cap_hit "$(sfield "$T/E1.out" cap_hit)" 0
# ⭐ v2 修正的定点牙：速率分母 = **连接窗口**（不含 hold）。修正前这里 = 49.9/s（3s+hold3s）
chk_rng E1_rate_per_s "$(sfield "$T/E1.out" rate_per_s)" 93 107
chk_rng E1_conn_window_s "$(sfield "$T/E1.out" conn_window_s)" 2.8 3.2
chk_rng E1_window_s "$(sfield "$T/E1.out" window_s)" 5.8 8.0
echo "  [E1 SUM] $(sumline "$T/E1.out")"

echo; echo "--- E2: --max-conns 50（撞顶 => CHURN_CAP 行 + 停止新建 + RC=0） ---"
"$BIN" --host 127.0.0.1 --port $PORT --connect-interval-ms 10 --seconds 3 --max-conns 50 \
       > "$T/E2.out" 2> "$T/E2.err"
chk_eq E2_rc "$?" 0
chk_eq E2_cap_line "$(grep -c '^CHURN_CAP max_conns=50' "$T/E2.out")" 1
chk_eq E2_conns "$(sfield "$T/E2.out" conns)" 50
chk_eq E2_cap_hit "$(sfield "$T/E2.out" cap_hit)" 1
chk_eq E2_conn_lines "$(grep -c '^CHURN conn=' "$T/E2.out")" 50
echo "  [E2 CAP] $(grep -m1 '^CHURN_CAP' "$T/E2.out")"
pkill -f "fake_stream_server.py --port $PORT" >/dev/null 2>&1
echo
echo "=== HOLD_CAP_CHECK $([ $FAIL = 0 ] && echo PASS || echo FAIL) PASS=$PASS FAIL=$FAIL $(date -u +%FT%TZ) ==="
exit $([ $FAIL = 0 ] && echo 0 || echo 1)
