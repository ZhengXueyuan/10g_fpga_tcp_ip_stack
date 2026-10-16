#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mk_table29.py -- 0x29 拆刀轮: 逐臂判读表 (口径逐字同 bisect 轮 _tools/mk_table.py)

判据 (逐字同 bisect round TABLE 头):
  相位错 (phase) = first_mismatch==0 AND mism > bytes*250//256 (≈ bytes - bytes/256)
  STALL          = poll_tmo==3  (SINK_CONN 状态字 STALL)
  clean          = first_mismatch==-1 AND mism_bytes==0 AND OK
附加 (本轮双面记录): 慢盆判别列 —— 慢盆 = 低速率 + mism==0 + 无 STALL (内容洁净);
  幽灵 = STALL 和/或 相位错 与其算术 (bytes - bytes/256) 吻合。
用法: python mk_table29.py <TAG> [<TAG> ...]     (读 runs/remote/<TAG>_{sink,ctl.err,full.err}.txt)
"""
import os, re, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
R = os.path.dirname(os.path.abspath(__file__))          # .../p9_dissect_0x29_20261017/board
ROOT = os.path.dirname(R)
RUNS = os.path.join(ROOT, "runs")
REMOTE = os.path.join(RUNS, "remote")


def rd(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except Exception:
        return ""


tags = sys.argv[1:]
if not tags:
    tags = sorted(set(re.match(r"d29_(.+)_sink\.txt$", f).group(1)
                      for f in os.listdir(REMOTE) if f.endswith("_sink.txt") and f.startswith("d29_")))
    tags = [t for t in tags if t]
out = []
out.append("=== D29 (0x29 拆刀) run table -- %s ===" % " ".join(tags))
out.append("judge: phase = first_mismatch==0 AND mism ~= bytes - bytes/256 ; STALL = poll_tmo=3 (15 s no data)")
out.append("slow-basin rule (double-sided record): rate<<anchor AND mism==0 AND stall==0 => 慢盆 (内容洁净);")
out.append("ghost rule: stall>=1 or phase>=1 (with arithmetic check) => 幽灵签名")
out.append("")
hdr = "%-10s %-24s %-6s %-6s %-6s %-6s %-10s %-8s %-6s %-24s %s"
out.append(hdr % ("TAG", "RCVBUF_ORDER", "conns", "stall", "phase", "clean", "agg Mbps", "wall s", "SRC_RC", "capture(ctl/full dropped)", "verdict"))
for tag in tags:
    s = rd(os.path.join(REMOTE, "d29_%s_sink.txt" % tag))
    sto = rd(os.path.join(RUNS, "D29_%s_stdout.txt" % tag))
    conns = stall = phase = clean = 0
    agg = wall = ""
    order = "?"
    for m in re.finditer(r"^SINK_CONN (\d+) (\w+).*?bytes=(\d+) first_mismatch=(-?\d+) mism_bytes=(\d+)", s, re.M):
        conns += 1
        ok, by, fm, mm = m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5))
        if ok == "STALL":
            stall += 1
        if fm == 0 and mm > by * 250 // 256:
            phase += 1
        if fm == -1 and mm == 0 and ok == "OK":
            clean += 1
    mo = re.search(r"^SINK_RCVBUF_ORDER (\S+)", s, re.M)
    if mo:
        order = mo.group(1)
    sl = [l for l in s.splitlines() if l.startswith("SINK_SUM")]
    if sl:
        a = re.search(r"agg_Mbps=([0-9.]+)", sl[0]); w = re.search(r"wall_s=([0-9.]+)", sl[0])
        agg = a.group(1) if a else ""
        wall = w.group(1) if w else ""
    m3 = re.search(r"### SINK_RC=(\d+)", sto)
    rc = m3.group(1) if m3 else "-"
    ce = rd(os.path.join(REMOTE, "d29_%s_ctl.err" % tag)); fe = rd(os.path.join(REMOTE, "d29_%s_full.err" % tag))
    dc = re.search(r"(\d+) packets dropped by kernel", ce); df = re.search(r"(\d+) packets dropped by kernel", fe)
    n_arm = sto.count("TCPDUMP_ARMED"); n_stop = sto.count("STOPPED_GRACEFULLY")
    drops = "ctl=%s full=%s armed=%d stopped=%d" % (dc.group(1) if dc else "?", df.group(1) if df else "?", n_arm, n_stop)
    verdict = []
    if stall or phase:
        verdict.append("幽灵签名 (stall=%d phase=%d)" % (stall, phase))
    if conns and not stall and not phase and clean == conns:
        verdict.append("洁净")
    if conns == 0 and (not s.strip()):
        verdict.append("无读数 (hang/timeout?)")
    if not sto:
        rc = "n/a(stdout lost)" if rc == "-" else rc
    out.append(hdr % (tag, order, conns, stall, phase, clean, agg or "-", wall or "-", rc, drops, "; ".join(verdict)))
out.append("")
out.append("=== per-connection detail (sink verbatim rows; THREADED.. 尾已截) ===")
for tag in tags:
    s = rd(os.path.join(REMOTE, "d29_%s_sink.txt" % tag))
    out.append("--- %s ---" % tag)
    for line in s.splitlines():
        if line.startswith("SINK_CONN"):
            line = re.sub(r" CPU_FREQ.*$", "", line)
            # 相位错算术核对: mism vs bytes - bytes/256 (差 <= 48 视为吻合, 与 bisect 口径同族)
            m = re.search(r"bytes=(\d+) first_mismatch=(-?\d+) mism_bytes=(\d+)", line)
            if m and int(m.group(2)) == 0:
                by, mm = int(m.group(1)), int(m.group(3))
                pred = by - by // 256
                line += "  [arith bytes-bytes/256=%d delta=%d]" % (pred, pred - mm)
            out.append("  " + line)
    sumline = [l for l in s.splitlines() if l.startswith("SINK_SUM")]
    if sumline:
        out.append("  " + re.sub(r" THREADED.*", "", sumline[0]))
    else:
        out.append("  (no SINK_SUM: run did not finish; see stdout)")
print("\n".join(out))
open(os.path.join(RUNS, "TABLE.txt"), "w", encoding="utf-8").write("\n".join(out) + "\n")
