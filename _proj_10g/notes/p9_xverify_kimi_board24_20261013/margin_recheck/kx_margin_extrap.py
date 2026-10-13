#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_margin_extrap.py — 复核面①：外推三段框算术独立复算（自写解析器；不 import 对方 _tools）
# 洞定义（按报告 §1.1 口径独立重实现）：Δ[0]=首采样 w70 − pre 快照；Δ[k]=w70_k−w70_{k-1}（t 序）
# Def-A = Δ>0 极大连续段合并；Def-B = 每个 Δ>0 区间各自计；降幅 = Σ min(深度, ΔC)
import re, os, glob, statistics, csv

HERE = os.path.dirname(os.path.abspath(__file__))
N = os.path.join(HERE, "..", "..", "p9_uram_ab_20261014", "runs")
O24 = os.path.join(HERE, "..", "..", "p9_board_0x24_20261013", "runs")
O23 = os.path.join(HERE, "..", "..", "p9_hostread_20261013", "runs")
CHUNK = 4194304
DC2, DC4 = 32800, 98400

def parse_file(path):
    """返回 {tag: dict}（支持一文件多窗）"""
    t = open(path, encoding="utf-8", errors="replace").read()
    heads = list(re.finditer(r"(?m)^=== WIN (\S+)( [^\n]*)?\n", t))
    out = {}
    for i, h in enumerate(heads):
        tag = h.group(1)
        body = t[h.end(): heads[i+1].start() if i+1 < len(heads) else len(t)]
        rows = [(float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)))
                for m in re.finditer(r"^READLOG i=\d+ t=([\d.]+) \S+ \S+ \S+ got=(\d+) pc=(\d+) w70=(\d+) dw70=\d+ dma=\d+ ddma=\d+", body, re.M)]
        pre = int(re.search(r"SNAP_BEGIN \S+?_pre.*?^W70\s+0x138\s+\S+\s+0x([0-9a-fA-F]+)", body, re.M | re.S).group(1), 16)
        post = int(re.search(r"SNAP_BEGIN \S+?_post.*?^W70\s+0x138\s+\S+\s+0x([0-9a-fA-F]+)", body, re.M | re.S).group(1), 16)
        acct = int(re.search(r"MIR_STREAM_ACCT pc=\d+ taken_bytes=\d+ dW70=(\d+)", body).group(1))
        out[tag] = dict(rows=rows, pre=pre, post=post, acct=acct)
    return out

def holes(d):
    rows = sorted(d["rows"])
    deltas = [rows[0][3] - d["pre"]] + [b[3] - a[3] for a, b in zip(rows, rows[1:])]
    tot = sum(deltas)
    # Def-A: 极大连续 Δ>0 段
    depthsA, anchors, cur, anchor = [], [], 0.0, None
    for k, dl in enumerate(deltas):
        if dl > 0:
            if cur == 0:
                anchor = rows[k-1][2] if k > 0 else 0   # 段前最后一个 Δ=0 采样的 pc（k=0 → 流起点 pc=0）
            cur += dl
        else:
            if cur > 0:
                depthsA.append(cur); anchors.append(anchor)
            cur = 0.0
    if cur > 0:
        depthsA.append(cur); anchors.append(anchor)
    depthsB = [dl for dl in deltas if dl > 0]
    return deltas, depthsA, depthsB, anchors, tot

def extrap(depths, dc):
    return sum(min(x, dc) for x in depths)

# ---------- 载入 36 窗 ----------
W = {}   # tag -> (group, arm, data)
for f in glob.glob(os.path.join(N, "WIN_*.txt")):
    for tag, d in parse_file(f).items():
        arm = "0x23" if "_A" in tag else "0x24"
        W[tag] = (f"new:{arm[2:]}S" if tag.startswith("S_") else f"new:{arm[2:]}F", arm, d)
for f in glob.glob(os.path.join(O24, "WIN_*.txt")):
    for tag, d in parse_file(f).items():
        W[tag] = (f"old24:{'S' if tag.startswith('S') else 'F'}", "0x24", d)
for nm in ("A1", "A1N2", "A4"):
    for tag, d in parse_file(os.path.join(O23, nm + ".txt")).items():
        W[tag] = (f"old23:{'S' if tag in ('A1','A1N2') else 'F'}", "0x23", d)
print(f"载入 {len(W)} 窗（12 新 + 21 旧24 + 3 旧23，四口径自检含全部；臂汇总剔除内容臂 CAPD24）")

# ---------- 四口径自检 ----------
print("\n--- 四口径自检（ΣΔ == ACCT == post−pre） ---")
bad4 = []
res = {}
for tag, (grp, arm, d) in sorted(W.items()):
    deltas, dA, dB, anch, tot = holes(d)
    ok = (tot == d["acct"] == d["post"] - d["pre"])
    if not ok: bad4.append((tag, tot, d["acct"], d["post"] - d["pre"]))
    obs = d["acct"]
    rA2, rA4 = extrap(dA, DC2), extrap(dA, DC4)
    rB2 = extrap(dB, DC2)
    res[tag] = dict(grp=grp, arm=arm, obs=obs, nA=len(dA), nB=len(dB), rA2=rA2, rA4=rA4, rB2=rB2,
                    floor=min(DC2, obs),
                    pctA2=100*rA2/obs, pctB2=100*rB2/obs, pctA4=100*rA4/obs, pctfloor=100*min(DC2, obs)/obs)
print(f"四口径自检 {len(W)}/{len(W)} 全中: {not bad4}", bad4 or "")

# ---------- 与对方的 extrap.windows.csv 逐窗对账 ----------
print("\n--- 与对方 extrap.windows.csv 对账（36 窗 × A/B 两口径 × red_2x / red_4x / floor） ---")
their = {}
with open(os.path.join(HERE, "..", "..", "p9_uram_margin_20261014", "extrap.windows.csv"), encoding="utf-8") as f:
    for row in csv.DictReader(f):
        their[(row["window"], row["hole_def"])] = row
diff = []
for tag, r in res.items():
    for df, mine2, mine4 in (("A", r["rA2"], r["rA4"]), ("B", r["rB2"], None)):
        key = None
        for cand in (f"new:{tag}", f"old24:{tag}", f"old23:{tag}", tag):
            if (cand, df) in their:
                key = (cand, df); break
        if key is None:
            if tag != "CAPD24":
                diff.append((tag, df, "no-csv-row"))
            continue
        t = their[key]
        if int(t["red_2xURAM"]) != mine2 or (mine4 is not None and int(t["red_4xURAM"]) != mine4) or int(t["floor_reduction"]) != r["floor"]:
            diff.append((tag, df, t["red_2xURAM"], mine2, t["red_4xURAM"], mine4, t["floor_reduction"], r["floor"]))
print("36 窗 × 2 口径 × 3 列全部逐字节相同:" , not diff, diff[:6] or "")

# ---------- 新 12 窗三段框（§4.3 表） ----------
print("\n--- 新 12 窗三段框（复算 vs 报告 §4.3） ---")
order = ["S_A1","S_A2","S_A3","S_B1","S_B2","S_B3","F_A1","F_A2","F_A3","F_B1","F_B2","F_B3"]
rep43 = {  # 报告 (Def-A 降幅 B, 降幅%, 单程下界%)
 "S_A1": (65600, 0.7, 0.35), "S_A2": (98400, 1.0, 0.34), "S_A3": (65600, 0.7, 0.34),
 "S_B1": (555720, 15.0, 0.89), "S_B2": (429360, 4.7, 0.36), "S_B3": (407088, 34.9, 2.81),
 "F_A1": (131200, 1.1, 0.27), "F_A2": (98400, 0.9, 0.29), "F_A3": (65600, 0.7, 0.34),
 "F_B1": (877480, 12.0, 0.45), "F_B2": (1402000, 39.6, 0.93), "F_B3": (1129136, 20.6, 0.60)}
allok = True
for tag in order:
    r = res[tag]
    e = rep43[tag]
    ok = (r["rA2"] == e[0]) and (round(r["pctA2"], 1) == e[1]) and (round(r["pctfloor"], 2) == e[2])
    allok &= ok
    print(f"{tag}: red_A={r['rA2']} (报 {e[0]})  {r['pctA2']:.1f}% (报 {e[1]})  下界 {r['pctfloor']:.2f}% (报 {e[2]})  {'OK' if ok else 'X'}")
print("§4.3 新 12 窗三段全中:", allok)

# ---------- 臂汇总（§4.4） ----------
print("\n--- 臂汇总 Def-A 降幅%% 中位（§4.4） ---")
arms = {
 "0x23-S": [t for t, r in res.items() if r["grp"] in ("new:23S", "old23:S")],
 "0x23-F": [t for t, r in res.items() if r["grp"] in ("new:23F", "old23:F")],
 "0x24-S": [t for t, r in res.items() if r["grp"] in ("new:24S", "old24:S") and t != "CAPD24"],
 "0x24-F": [t for t, r in res.items() if r["grp"] in ("new:24F", "old24:F") and t != "CAPD24"],
}
rep44 = {"0x23-S": (5, 1.0, 0.7, 76.3), "0x23-F": (4, 1.1, 0.7, 3.3), "0x24-S": (14, 50.0, 0.7, 83.6), "0x24-F": (13, 14.5, 4.1, 39.6)}
for a, tags in arms.items():
    pcts = sorted(res[t]["pctA2"] for t in tags)
    med = statistics.median(pcts)              # 两中值平均
    med_up = pcts[len(pcts) // 2]              # 上中位 s[n//2]（对方臂汇总表口径）
    n, m, lo, hi = rep44[a]
    ok = (len(tags) == n) and (round(med_up, 1) == m) and (round(min(pcts), 1) == lo) and (round(max(pcts), 1) == hi)
    print(f"{a}: n={len(tags)}(报 {n}) 中位(两中均) {med:.2f}% / 上中位 {med_up:.1f}%(报 {m}) 范围 {min(pcts):.1f}–{max(pcts):.1f}%(报 {lo}–{hi}) {'OK(上中位口径)' if ok else 'X'}")
    if a == "0x24-S":
        print("   0x24-S 逐窗%:", {t: round(res[t]['pctA2'],1) for t in sorted(tags)})

# ---------- 敏感度（§4.5① 77pp） ----------
print("\n--- 洞定义敏感度 Def-B − Def-A（pp；§4.5①） ---")
for tag in order:
    r = res[tag]
    print(f"{tag}: A={r['pctA2']:.1f}%  B={r['pctB2']:.1f}%  差={r['pctB2']-r['pctA2']:.1f} pp")
mx = max(res[t]["pctB2"] - res[t]["pctA2"] for t in order)
print(f"新 12 窗最大敏感度: {mx:.1f} pp（报告：可达 77 pp / S_A1=77.3）")
print(f"Def-B 2×URAM 最大降幅: {max(res[t]['pctB2'] for t in order):.1f}%（报告：新 A 臂可到 58–78%）")
print(f"单程下界范围: {min(res[t]['pctfloor'] for t in order):.2f}–{max(res[t]['pctfloor'] for t in order):.2f}%（报告 0.27–2.81%）")

# ---------- G 分布（A6，§4.5④） ----------
print("\n--- G = d + C_arm pooled Def-B 中位（§4.5④） ---")
CARM = {"0x23": 2104, "0x24": 34904}
for gname, pred in (("new:23S", "S_A 37,112"), ("new:23F", "F_A 46,872"), ("new:24S", "S_B 54,440"), ("new:24F", "F_B 59,352"), ("old23:S", "旧0x23 45,112")):
    gs = []
    for tag, (grp, arm, d) in W.items():
        if grp != gname: continue
        _, dA, dB, _, _ = holes(d)
        gs += [x + CARM[arm] for x in dB]
    print(f"{gname}: n={len(gs)} G中位={statistics.median(gs):,.0f} (报告 {pred}) 范围 {min(gs):,}–{max(gs):,}")
