import os, re, glob
R = "."
order = [
 ("S0_1A","0x1A","before_connect(new)"), ("S0_1A_L","0x1A","after_connect_LEGACY"),
 ("S0_1C_L","0x1C","after_connect_LEGACY"), ("S0_1C_L2","0x1C","after_connect_LEGACY"), ("S0_1C_B","0x1C","before_connect(new)"),
 ("S0_1D_L","0x1D","after_connect_LEGACY"), ("S0_1D_L2","0x1D","after_connect_LEGACY"), ("S0_1D_L3","0x1D","after_connect_LEGACY"),
 ("S0_1F_L","0x1F","after_connect_LEGACY"), ("S0_24_L","0x24","after_connect_LEGACY"),
]
def rd(p):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except Exception: return ""
out = []
out.append("=== S-0 bisect run table (2026-10-16/17) ===")
out.append("judge: phase error = first_mismatch==0 AND mism ~= bytes - bytes/256 ; STALL = poll_tmo=3 (15 s no data)")
out.append("")
hdr = "%-9s %-5s %-20s %-6s %-6s %-5s %-6s %-9s %-8s %-7s %s"
out.append(hdr % ("TAG","GEN","RCVBUF_ORDER","conns","stall","phase","clean","agg Mbps","wall s","SRC_RC","capture(ctl/full dropped)"))
for tag, gen, cfg in order:
    s = rd("runs/remote/%s_sink.txt" % tag)
    sto = rd("runs/%s_stdout.txt" % tag)
    conns = stall = phase = clean = 0; agg=""; wall=""; rc=""
    for m in re.finditer(r'^SINK_CONN (\d+) (\w+).*?bytes=(\d+) first_mismatch=(-?\d+) mism_bytes=(\d+)', s, re.M):
        conns += 1
        idx, ok, by, fm, mm = int(m.group(1)), m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5))
        if ok == "STALL": stall += 1
        if fm == 0 and mm > by * 250 // 256: phase += 1
        if fm == -1 and mm == 0 and ok == "OK": clean += 1
    sl = [l for l in s.splitlines() if l.startswith("SINK_SUM")]
    if sl:
        a = re.search(r'agg_Mbps=([0-9.]+)', sl[0]); w = re.search(r'wall_s=([0-9.]+)', sl[0])
        if a: agg = a.group(1)
        if w: wall = w.group(1)
    m3 = re.search(r'### SINK_RC=(\d+)', sto)
    if m3: rc = m3.group(1)
    if not m3 and not s: rc = "-"
    drops = "n/a"
    ce = rd("runs/remote/%s_ctl.err" % tag); fe = rd("runs/remote/%s_full.err" % tag)
    dc = re.search(r'(\d+) packets dropped by kernel', ce); df = re.search(r'(\d+) packets dropped by kernel', fe)
    n_arm = sto.count("TCPDUMP_ARMED"); n_stop = sto.count("STOPPED_GRACEFULLY")
    drops = "ctl=%s full=%s armed=%d stopped=%d" % (dc.group(1) if dc else "?", df.group(1) if df else "?", n_arm, n_stop)
    if tag == "S0_1A": rc = "0"; drops += " [stdout lost: UnicodeEncodeError; gates from peer .err files]"
    if tag == "S0_1D_L2": rc = "124(timeout)"
    out.append(hdr % (tag, gen, cfg, conns, stall, phase, clean, agg or "-", wall or "-", rc or "-", drops))
out.append("")
out.append("=== per-connection detail (sink verbatim rows) ===")
for tag, gen, cfg in order:
    s = rd("runs/remote/%s_sink.txt" % tag)
    out.append("--- %s (%s, %s) ---" % (tag, gen, cfg))
    for line in s.splitlines():
        if line.startswith("SINK_CONN"):
            out.append("  " + re.sub(r' CPU_FREQ.*$', '', line))
    sumline = [l for l in s.splitlines() if l.startswith("SINK_SUM")]
    if sumline: out.append("  " + re.sub(r' THREADED.*', '', sumline[0]))
    if not sumline: out.append("  (no SINK_SUM: run did not finish; see stdout)")
open("runs/TABLE.txt","w",encoding="utf-8").write("\n".join(out)+"\n")
print("\n".join(out))
