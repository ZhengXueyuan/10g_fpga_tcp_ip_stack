#!/bin/bash
# burn_cycle_0x3C_disc6.sh -- 0x3C 换烧周期停顿猎手：每周期 = 烧 0x3C + 2 轮 (disc6 全采样)。
#   停顿高发窗 = 换烧后头 1..2 轮 ⇒ 每周期只跑 2 轮。
#   usage: PEER_PW=... bash burn_cycle_0x3C_disc6.sh [cycles]
set -u
OUT=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_synfix_20261105
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
C=${1:-6}
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
for i in $(seq 1 "$C"); do
  echo "===== CYCLE $i $(date +%T) ====="
  PEER_PW="${PEER_PW:-}" bash "$OUT/burn_0x3C_board.sh" > "/tmp/burn3c_$i.log" 2>&1
  rc=$?
  grep -E 'BURN_OK|BURN_FAIL|ID_BID' "/tmp/burn3c_$i.log" | tail -2
  [ $rc -eq 0 ] || { echo "CYCLE_$i BURN_RC=$rc => STOP"; break; }
  $SSH --sudo "bash /tmp/env_setup_robust.sh >/dev/null 2>&1; \
    for r in 1 2; do \
      bash /tmp/f2_disc6.sh d 0 w${i}r\${r} >/dev/null 2>&1; \
      ok=0; st=0; \
      for k in 0 1 2 3 4 5 6 7; do \
        L=\$(grep -E 'SINK_CONN' /home/a/p11_bench/w${i}r\${r}_d_\$k.txt 2>/dev/null | tail -1); \
        case \"\$L\" in *' OK '*) ok=\$((ok+1));; *STALL*) st=\$((st+1));; esac; \
      done; \
      echo \"W${i}_R\${r} OK=\$ok STALL=\$st\"; \
      if [ \$st -gt 0 ]; then \
        echo '--- SAMPLES (tail) ---'; tail -8 /home/a/p11_bench/w${i}r\${r}_samples6.txt; \
        echo '--- CONNS ---'; \
        for k in 0 1 2 3 4 5 6 7; do echo \"P\$k \$(grep -E 'SINK_CONN' /home/a/p11_bench/w${i}r\${r}_d_\$k.txt | tail -1)\"; done; \
      fi; \
    done" 2>&1 | tee -a "$OUT/raw/burn_cycle_0x3C_disc6_cycle$i.txt"
done
echo "===== ALL CYCLES DONE $(date +%T) ====="
