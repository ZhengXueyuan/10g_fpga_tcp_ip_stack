#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_stats.py — 独立复算 p9_board_0x24 URAM 收益主臂读数（自写解析器；不复用对方 _tools）
# 数据源：runs/STATS_{SINGLE,FOURSRC}.txt + runs/WIN_*.txt
import re, statistics, os, sys

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_0x24_20261013")
RUNS = os.path.join(BASE, "runs")

EXPECTED_ARGS = "--bid 0x00000024 --bytes 1073741824 --stream --src udp --pat-off 0 --buf-mb 1024 --sample-ms 1000 --settle 0.3 --seconds 6 --readlog 1 --chunk 4194304 --dual 2 --no-verify"

SINGLE_FILES = ["WIN_S0_20261013_220859.txt", "WIN_S1_S5_20261013_220956.txt", "WIN_S6_S10_20261013_221125.txt"]
FOUR_FILES   = ["WIN_F0_20261013_220930.txt", "WIN_F1_F5_20261013_221254.txt", "WIN_F6_F9_20261013_221427.txt"]

def parse_stats(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.rstrip("\n")
            m = re.match(r"^(S\d+|F\d+)\s+(\d+)\s+", ln)
            if m:
                tag = m.group(1); dW70 = int(m.group(2))
                # 式B(res/closed) 式A(res) reads w_read w_src
                m2 = re.match(r"^\S+\s+\d+\s+[\d.]+\s+[\d.]+\s+[\d.]+\s+(\d+)/(\d+)\s+(\d+)/\d+\s+(\d+)\s+([\d.]+)\s+([\d.]+)", ln)
                b_res, b_closed, a_res, reads = (int(m2.group(i)) for i in (1,2,3,4))
                w_read, w_src = float(m2.group(5)), float(m2.group(6))
                rows.append(dict(tag=tag, dW70=dW70, b_res=b_res, b_closed=b_closed, a_res=a_res, reads=reads, w_read=w_read, w_src=w_src))
    return rows

def parse_win_file(path):
    """返回 {tag: {...}} — 按窗口段解析（按头部行位置切分）"""
    text = open(path, encoding="utf-8", errors="replace").read()
    heads = list(re.finditer(r"(?m)^=== WIN (\S+)( [^\n]*)?\n", text))
    out = {}
    for i, h in enumerate(heads):
        tag = h.group(1)
        body = text[h.end(): heads[i+1].start() if i+1 < len(heads) else len(text)]
        d = {}
        m = re.search(r"^TOOL_ARGS: (.*)$", body, re.M); d["args"] = m.group(1) if m else None
        m = re.search(r"^MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)", body, re.M)
        d["acct"] = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None
        m = re.search(r"式A\(成形器\).*?-> (\d+)\s+band=\[0,32\] closed_a=(\d+)", body, re.M); d["ida"] = (int(m.group(1)), int(m.group(2))) if m else None
        m = re.search(r"式B\(镜像/K\).*?-> (\d+)\s+band=\[0,24\] closed_b=(\d+)", body, re.M); d["idb"] = (int(m.group(1)), int(m.group(2))) if m else None
        # pre/post 快照 W70
        pres = re.findall(r"SNAP_BEGIN (\S+?)_pre.*?^W70\s+0x138\s+mir_drop_bytes\s+0x([0-9a-fA-F]+)", body, re.M | re.S)
        posts = re.findall(r"SNAP_BEGIN (\S+?)_post.*?^W70\s+0x138\s+mir_drop_bytes\s+0x([0-9a-fA-F]+)", body, re.M | re.S)
        d["w70_pre"] = int(pres[0][1], 16) if pres else None
        d["w70_post"] = int(posts[0][1], 16) if posts else None
        # READLOG 末行 t（READLOG_SUM 前最后一行 READLOG）
        rls = re.findall(r"^READLOG i=\d+ t=([\d.]+) ", body, re.M)
        d["w_read"] = float(rls[-1]) if rls else None
        d["n_readlog"] = len(rls)
        m = re.search(r"^SRC_RC=\d+ TE=([\d.]+)", body, re.M)
        m2 = re.search(r"TS=([\d.]+) ", body)
        d["w_src"] = (float(m.group(1)) - float(m2.group(1))) if (m and m2) else None
        m = re.search(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+)", body, re.M)
        d["done"] = (int(m.group(1)), int(m.group(2))) if m else None
        m = re.search(r"PIN_CPU=(\d+)", body); d["pin_cpu"] = int(m.group(1)) if m else None
        m = re.search(r"TOOL_MD5=(\w+)", body); d["tool_md5"] = m.group(1) if m else None
        out[tag] = d
    return out

def report(name, stat_rows, win_rows, order):
    print("="*78); print(name); print("="*78)
    dw = []
    for r in stat_rows:
        dw.append(r["dW70"])
    n = len(dw)
    tot = sum(dw)
    med = statistics.median(dw)
    mean = tot / n
    print(f"n={n}  ΣdW70={tot} B = {tot/1e6:.2f} MB(十进制) = {tot/2**20:.2f} MiB")
    print(f"中位 = {med} B = {med/1e6:.4f} MB = {med/2**20:.4f} MiB")
    print(f"均值 = {mean:.1f} B = {mean/1e6:.4f} MB = {mean/2**20:.4f} MiB")
    print(f"min={min(dw)} ({min(dw)/1e6:.2f} MB)  max={max(dw)} ({max(dw)/1e6:.2f} MB)")
    print()
    # 逐窗与 WIN 文件交叉核
    print(f"{'tag':<5}{'STATS_dW70':>12}{'WIN_ACCT':>12}{'快照差分':>12}{'一致':>6}{'式B':>10}{'式A':>12}{'reads':>7}{'w_read':>9}{'w_src':>9}{'args':>5}")
    ok = True
    sum_wread = sum_wsrc = 0.0
    b_ok = 0
    for tag in order:
        s = next(r for r in stat_rows if r["tag"] == tag)
        w = win_rows[tag]
        acct = w["acct"][2] if w["acct"] else None
        snapdiff = (w["w70_post"] - w["w70_pre"]) if (w["w70_post"] is not None and w["w70_pre"] is not None) else None
        match = (s["dW70"] == acct == snapdiff)
        if not match:
            ok = False
            print(f"  [DEBUG {tag}] acct={w['acct']} pre={w['w70_pre']} post={w['w70_post']}")
        bmatch = (w["idb"] == (s["b_res"], s["b_closed"]))
        amatch = (w["ida"] and w["ida"][0] == s["a_res"])
        argsok = (w["args"] == EXPECTED_ARGS)
        wr = round(w["w_read"], 3) if w["w_read"] is not None else -1
        ws = round(w["w_src"], 3) if w["w_src"] is not None else -1
        wrok = (w["w_read"] is not None) and abs(w["w_read"] - s["w_read"]) < 0.01
        wsok = (w["w_src"] is not None) and abs(w["w_src"] - s["w_src"]) < 0.01
        if wrok: sum_wread += w["w_read"]
        if wsok: sum_wsrc += w["w_src"]
        if w["idb"] == (0, 1): b_ok += 1
        print(f"{tag:<5}{s['dW70']:>12}{acct!s:>12}{snapdiff!s:>12}{str(match):>6}{str(w['idb']):>10}{str(w['ida'][0] if w['ida'] else None):>12}{s['reads']:>7}{wr:>9}{ws:>9}{str(argsok):>5}")
    print()
    print(f"STATS↔WIN↔快照差分 三口径全一致: {ok}")
    print(f"式B(res=0,closed_b=1) 命中: {b_ok}/{n}")
    print(f"Σw_read = {sum_wread:.2f} s (≥30: {sum_wread>=30})   Σw_src = {sum_wsrc:.2f} s (≥30: {sum_wsrc>=30})")
    print(f"TOOL_MD5 集合: {sorted(set(w.get('tool_md5') for w in win_rows.values()))}")
    print(f"PIN_CPU 集合: {sorted(set(w.get('pin_cpu') for w in win_rows.values()))}")
    return dict(n=n, tot=tot, med=med, mean=mean, mn=min(dw), mx=max(dw), sum_wread=sum_wread, sum_wsrc=sum_wsrc, b_ok=b_ok, ok=ok)

st_s = parse_stats(os.path.join(RUNS, "STATS_SINGLE.txt"))
st_f = parse_stats(os.path.join(RUNS, "STATS_FOURSRC.txt"))
print("STATS_SINGLE 解析窗口:", [r["tag"] for r in st_s])
print("STATS_FOURSRC 解析窗口:", [r["tag"] for r in st_f])

win = {}
for fn in SINGLE_FILES + FOUR_FILES:
    win.update(parse_win_file(os.path.join(RUNS, fn)))
print("WIN 文件解析窗口:", sorted(win.keys(), key=lambda x: (x[0], int(x[1:]))))
print()

order_s = ["S%d" % i for i in range(11)]
order_f = ["F%d" % i for i in range(10)]
rs = report("单源臂 S0–S10", st_s, win, order_s)
rf = report("4 源臂 F0–F9", st_f, win, order_f)

print()
print("="*78); print("对照基线 5.46 / 8.93 MB（p9_hostread_20261013/REPORT.md §4）"); print("="*78)
for label, r, base in (("单源", rs, 5.46), ("4源", rf, 8.93)):
    med_mb = r["med"]/1e6; mean_mb = r["mean"]/1e6
    print(f"{label}: 基线 {base} MB → 本件中位 {med_mb:.4f} MB (Δ {100*(med_mb-base)/base:+.1f}%) / 均值 {mean_mb:.4f} MB (Δ {100*(mean_mb-base)/base:+.1f}%)")
    print(f"      精确: 基线 {base} MB  vs 中位 {r['med']} B ; 若基线精确 5,459,912 B → {100*(r['med']-5459912)/5459912:+.2f}% ; 若 4,源基线 8,930,000 B → {100*(r['med']-8930000)/8930000:+.2f}%")
