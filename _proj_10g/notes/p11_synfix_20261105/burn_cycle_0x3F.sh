#!/bin/bash
# burn_cycle_0x3F.sh -- 0x3F 诊断：换烧周期测试（每周期 = 烧 0x3F + 4 轮 8x256MB）。
#   停顿高发窗 = 换烧后的头 1..2 轮 ⇒ 每周期都从第 1 轮开始记。
#   usage: PEER_PW=... bash burn_cycle_0x3F.sh [cycles]
set -u
OUT=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_synfix_20261105
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
C=${1:-6}
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
for i in $(seq 1 "$C"); do
  echo "===== CYCLE $i $(date +%T) ====="
  PEER_PW="${PEER_PW:-}" bash "$OUT/burn_0x3F_board.sh" > "/tmp/burn3d_$i.log" 2>&1
  rc=$?
  grep -E 'BURN_OK|BURN_FAIL|ID_BID|ID_RC|WINDOW_SCAN_NFF' "/tmp/burn3d_$i.log" | tail -4
  [ $rc -eq 0 ] || { echo "CYCLE_$i BURN_RC=$rc => STOP"; break; }
  $SSH --sudo "bash /tmp/env_setup_robust.sh >/dev/null 2>&1; \
    for r in 1 2 3 4; do \
      bash /tmp/f2_disc6.sh d 0 c${i}r\${r} >/dev/null 2>&1; \
      ok=0; st=0; \
      for k in 0 1 2 3 4 5 6 7; do \
        L=\$(grep -E 'SINK_CONN' /home/a/p11_bench/c${i}r\${r}_d_\$k.txt 2>/dev/null | tail -1); \
        case \"\$L\" in *' OK '*) ok=\$((ok+1));; *STALL*) st=\$((st+1));; esac; \
      done; \
      echo \"C${i}_R\${r} OK=\$ok STALL=\$st\"; \
      if [ \$st -gt 0 ]; then \
        echo '--- SAMPLES (tail) ---'; tail -6 /home/a/p11_bench/c${i}r\${r}_samples6.txt; \
        echo '--- CONNS ---'; \
        for k in 0 1 2 3 4 5 6 7; do echo \"P\$k \$(grep -E 'SINK_CONN' /home/a/p11_bench/c${i}r\${r}_d_\$k.txt | tail -1)\"; done; \
      fi; \
    done" 2>&1 | tee -a "$OUT/raw/burn_cycle_0x3F_cycle$i.txt"
done
echo "===== ALL CYCLES DONE $(date +%T) ====="
