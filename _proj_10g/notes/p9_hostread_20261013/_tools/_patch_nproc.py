import sys

p = r"D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/_tools/run_win_hw.sh"
lines = open(p, encoding="utf-8").read().split("\n")
for i, L in enumerate(lines):
    if L.startswith("DUAL=${DUAL:-0}"):
        lines.insert(i, "NPROC=${NPROC:-1}    # source process count (each --bytes PER; FIXOFF=0 -> same off)")
        lines.insert(i + 1, "CORES=${CORES:-}     # space separated core list, rotated across sources")
        break
start = next(i for i, L in enumerate(lines) if L.strip() == 'SOPT=""')
end = next(i for i, L in enumerate(lines) if L.strip() == "SRC_RC=$?")
cmd = ('timeout -k 5 $((SRC_SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes "$PER" --mbps "$MBPS" '
       '--batch "$BATCH" --paylen "$PAYLEN" --off "$OFF" --seconds "$SRC_SECS" $COREOPT > "src_${TAG}_p${p}.log" 2>&1 &')
new_block = [
    "PER=$((K / NPROC))",
    'SPIDS=""',
    'for p in $(seq 1 "$NPROC"); do',
    '  COREOPT=""',
    '  if [ -n "$CORES" ]; then',
    '    c=$(echo "$CORES" | tr " " "\\n" | sed -n "$(( (p - 1) % $(echo "$CORES" | wc -w) + 1 ))p")',
    '    [ -n "$c" ] && COREOPT="--core $c"',
    "  fi",
    '  [ -n "$SRC_PIN" ] && COREOPT="--core $SRC_PIN"',
    "  " + cmd,
    '  SPIDS="$SPIDS $!"',
    "done",
    "SRC_RC=0",
    'for sp in $SPIDS; do wait "$sp" || SRC_RC=1; done',
]
lines[start:end] = new_block
txt = "\n".join(lines)
old_grep = 'grep -E "PIN_CPU=|UNPINNED|UDP_SUM|FATAL|SEND_ERR|UDP_POLL_TMO" "src_${TAG}.log" | tail -6'
new_grep = 'for p in $(seq 1 "$NPROC"); do echo "[p$p] $(grep -aE "PIN_CPU=|UDP_SUM" src_${TAG}_p${p}.log | tail -2 | tr "\\n" " ")"; done'
assert old_grep in txt, "grep block not found"
txt = txt.replace(old_grep, new_grep)
open(p, "w", encoding="utf-8", newline="\n").write(txt)
print("patched NPROC ok")
