#!/usr/bin/env python3
# ab_consistency.py -- 本卷 12 窗三口径对账: (a) pre/post 快照 W70 原值差 (b) MIR_STREAM_ACCT dW70 (c) Σ READLOG dw70
#   仅辅助; 主读数 = ACCT。输出 STATS_AB 供归档。
import glob, os, re, sys
def parse(fp):
    txt = open(fp, "r", encoding="utf-8", errors="replace").read()
    d = {}
    m = re.search(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+) w70a=(\d+) w70b=(\d+) words0=(\d+) words1=(\d+) dwords=(\d+) K=(\d+)", txt)
    if m:
        d.update(pc=int(m.group(1)), taken=int(m.group(2)), dW70_acct=int(m.group(3)),
                 w70a=int(m.group(4)), w70b=int(m.group(5)), words1=int(m.group(7)), K=int(m.group(9)))
    pre = re.search(r"W70\s+0x138\s+\S+\s+(0x[0-9a-fA-F]+)", txt.split("--- mir_dump 日志")[0])
    # pre snapshot appears before tool start; post snapshot after log
    allw70 = re.findall(r"^W70\s+0x138\s+\S+\s+(0x[0-9a-fA-F]+)", txt, re.M)
    if len(allw70) >= 2:
        d["snap_w70_a"] = int(allw70[0], 16); d["snap_w70_b"] = int(allw70[-1], 16)
        d["snap_diff"] = (d["snap_w70_b"] - d["snap_w70_a"]) % (2**32)
    s = re.findall(r"^READLOG i=\d+ .* dw70=(\d+) ", txt, re.M)
    if s: d["sum_dw70"] = sum(int(x) for x in s)
    d["n_readlog"] = len(s)
    m2 = re.search(r"MIR_STREAM_IDA.*closed_a=(\d)", txt); d["closed_a"] = int(m2.group(1)) if m2 else -1
    m3 = re.search(r"MIR_STREAM_IDB.*closed_b=(\d)", txt); d["closed_b"] = int(m3.group(1)) if m3 else -1
    m4 = re.search(r"MIR_STREAM_GAP.*host_miss_pct=([\d.]+)", txt); d["host_miss_pct"] = float(m4.group(1)) if m4 else -1
    m5 = re.search(r"MIR_ID magic=(\S+) \(exp (\S+)\) bid=(\S+) \(exp (\S+)\)", txt)
    if m5: d["bid"] = m5.group(3)
    m6 = re.search(r"^SRC_RC=(\d+)", txt, re.M); d["src_rc"] = int(m6.group(1)) if m6 else -1
    m7 = re.search(r"^TOOL_RC=(\d+)", txt, re.M); d["tool_rc"] = int(m7.group(1)) if m7 else -1
    return d

order = ["S_A1","F_A1","S_B1","F_B1","S_A2","F_A2","S_B2","F_B2","S_A3","F_A3","S_B3","F_B3"]
print("window  bid      dW70_acct    snap_diff    sum_dw70    3way_err  n_readlog closed_a closed_b host_miss%  src_rc tool_rc")
bad = 0
for tag in order:
    g = glob.glob(f"runs/WIN_{tag}_*.txt")
    if not g: print(f"{tag}: MISSING"); bad += 1; continue
    d = parse(sorted(g)[-1])
    act = d.get("dW70_acct"); sdf = d.get("snap_diff"); s = d.get("sum_dw70")
    err = (act - sdf) if (act is not None and sdf is not None) else None
    err2 = (act - s) if (act is not None and s is not None) else None
    print(f"{tag:7s} {d.get('bid','?'):8s} {act:12d} {sdf:12d} {s if s is not None else -1:12d} "
          f"snap:{err} sum:{err2} {d.get('n_readlog',0):9d} {d.get('closed_a'):8d} {d.get('closed_b'):8d} "
          f"{d.get('host_miss_pct'):10.4f} {d.get('src_rc'):6d} {d.get('tool_rc'):7d}")
    if err not in (0, None) or err2 not in (0, None): bad += 1
print(f"THREE_WAY_MISMATCH_WINDOWS={bad}")
# 汇总
def med(xs):
    ys = sorted(xs); n = len(ys)
    return (ys[n//2] if n % 2 else (ys[n//2-1]+ys[n//2])/2)
data = {}
for tag in order:
    g = glob.glob(f"runs/WIN_{tag}_*.txt")
    if g:
        d = parse(sorted(g)[-1]); data[tag] = d.get("dW70_acct")
A = [data[t] for t in order if t.endswith(("A1","A2","A3")) and t.startswith("S")]
B = [data[t] for t in order if t.endswith(("B1","B2","B3")) and t.startswith("S")]
AF = [data[t] for t in order if t.endswith(("A1","A2","A3")) and t.startswith("F")]
BF = [data[t] for t in order if t.endswith(("B1","B2","B3")) and t.startswith("F")]
for name, xs in (("S_0x23", A), ("S_0x24", B), ("F_0x23", AF), ("F_0x24", BF)):
    print(f"SUMMARY {name}: n={len(xs)} each={xs} median={med(xs):.0f} mean={sum(xs)/len(xs):.0f} min={min(xs)} max={max(xs)}")
