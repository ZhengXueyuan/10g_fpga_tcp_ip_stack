#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_ab_stats.py — ① 12 窗 ΔW70 三口径闭合复算 + 臂汇总（自写解析器；不 import 对方 _tools）
import re, os, statistics
from math import comb

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "p9_uram_ab_20261014")
RUNS = os.path.join(BASE, "runs")

WINS = ["S_A1", "F_A1", "S_B1", "F_B1", "S_A2", "F_A2", "S_B2", "F_B2", "S_A3", "F_A3", "S_B3", "F_B3"]
ARM_OF = {w: ("0x23" if "_A" in w else "0x24") for w in WINS}
SRC_OF = {w: ("S" if w.startswith("S_") else "F") for w in WINS}
EXPECT_ARGS = "--bid {bid} --bytes 1073741824 --stream --src udp --pat-off 0 --buf-mb 1024 --sample-ms 1000 --settle 0.3 --seconds 6 --readlog 1 --chunk 4194304 --dual 2 --no-verify"

def parse_win(path):
    t = open(path, encoding="utf-8", errors="replace").read()
    d = {}
    d["tool_md5"] = re.search(r"^TOOL_MD5=(\w+)", t, re.M).group(1)
    d["args"] = re.search(r"^TOOL_ARGS: (.*)$", t, re.M).group(1)
    d["bid"] = re.search(r"MIR_ID magic=\S+ \(exp \S+\) bid=(\w+)", t).group(1)
    m = re.search(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) short=(\d+) ended_early=(\d+) read_error=(\d+)", t)
    d["done"] = [int(m.group(i)) for i in range(1, 8)]
    m = re.search(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+) w70a=(\d+) w70b=(\d+)", t)
    d["acct"] = [int(m.group(i)) for i in range(1, 6)]
    d["K"] = int(re.search(r"K=(\d+)$", t, re.M).group(1))
    m = re.search(r"式A\(成形器\).*?-> (\d+)\s+band=\[0,32\] closed_a=(\d+)", t); d["ida"] = [int(m.group(1)), int(m.group(2))]
    m = re.search(r"式B\(镜像/K\).*?-> (\d+)\s+band=\[0,24\] closed_b=(\d+)", t); d["idb"] = [int(m.group(1)), int(m.group(2))]
    m = re.search(r"host_miss_pct=([\d.]+)", t); d["miss"] = float(m.group(1))
    pres = re.findall(r"SNAP_BEGIN (\S+?)_pre.*?^W70\s+0x138\s+mir_drop_bytes\s+0x([0-9a-fA-F]+)", t, re.M | re.S)
    posts = re.findall(r"SNAP_BEGIN (\S+?)_post.*?^W70\s+0x138\s+mir_drop_bytes\s+0x([0-9a-fA-F]+)", t, re.M | re.S)
    d["w70_pre"] = int(pres[0][1], 16); d["w70_post"] = int(posts[0][1], 16)
    rows = re.findall(r"^READLOG i=(\d+) t=([\d.]+) gap_us=([\d.]+) mmio_us=([\d.]+) read_us=([\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)", t, re.M)
    d["rows"] = [[int(a), float(b), float(c), float(d_), float(e), int(f), int(g), int(h), int(i), int(j), int(k)] for a, b, c, d_, e, f, g, h, i, j, k in rows]
    m = re.search(r"READLOG_SUM n=(\d+).*?dw70_total=(\d+)", t); d["sum_n"] = int(m.group(1)); d["sum_dw70"] = int(m.group(2))
    d["ts"] = re.search(r"TOOL_RC=(\d+) TZ=([\d.]+)", t)
    d["tool_rc"] = int(d["ts"].group(1))
    return d

print("=" * 100)
print("① 12 窗三口径闭合（pre/post 快照差 == ACCT dW70 == Σ READLOG dw70）+ 逐窗字段")
print("=" * 100)
data = {}
hdr = f"{'窗':<7}{'臂':<6}{'snap_diff':>12}{'ACCT':>12}{'Σdw70':>12}{'闭合':>6}{'n_rl':>6}{'w70a=pre':>10}{'w70b=post':>11}{'cl_a':>6}{'cl_b':>6}{'miss%':>8}{'MD5':>6}"
print(hdr)
allok = True
for w in WINS:
    import glob
    f = glob.glob(os.path.join(RUNS, f"WIN_{w}_*.txt"))[0]
    d = parse_win(f)
    data[w] = d
    snap_diff = d["w70_post"] - d["w70_pre"]
    sum_dw70 = sum(r[8] for r in d["rows"])
    ok3 = (snap_diff == d["acct"][2] == sum_dw70)
    okw = (d["acct"][3] == d["w70_pre"]) and (d["acct"][4] == d["w70_post"])
    okn = (len(d["rows"]) == d["sum_n"])
    oksum = (d["sum_dw70"] == sum_dw70)
    okargs = (d["args"] == EXPECT_ARGS.format(bid="0x" + ARM_OF[w][2:].zfill(8)))
    okmd5 = (d["tool_md5"] == "48dcbcb26a4db45f576fc9664638a089")
    okbid = (d["bid"] == ARM_OF[w][2:].zfill(8))
    ok = ok3 and okw and okn and oksum and okargs and okmd5 and okbid and d["idb"] == [0, 1] and d["ida"][1] == 0
    allok &= ok
    print(f"{w:<7}{ARM_OF[w]:<6}{snap_diff:>12}{d['acct'][2]:>12}{sum_dw70:>12}{str(ok3):>6}{len(d['rows']):>6}{str(okw):>10}{str(d['acct'][4]==d['w70_post']):>11}{d['ida'][1]:>6}{d['idb'][1]:>6}{d['miss']:>8}{str(okmd5):>6}")
    if not ok:
        print(f"   [DEBUG {w}] ok3={ok3} okw={okw} okn={okn} oksum={oksum} okargs={okargs} okmd5={okmd5} okbid={okbid} idb={d['idb']} ida={d['ida']}")
print(f"\n12 窗三口径全闭合 + 字段全中: {allok}")

# 与 STATS_AB.txt 对账
print("\n--- 与对方 STATS_AB.txt 对账 ---")
st = open(os.path.join(RUNS, "STATS_AB.txt"), encoding="utf-8").read()
for w in WINS:
    m = re.search(rf"^{w}\s+\w+\s+(\d+)\s+(\d+)\s+(\d+)", st, re.M)
    sv = [int(m.group(i)) for i in (1, 2, 3)]
    mine = [data[w]["acct"][2], data[w]["w70_post"] - data[w]["w70_pre"], sum(r[8] for r in data[w]["rows"])]
    assert sv == mine, (w, sv, mine)
print("STATS_AB.txt 12 行 dW70_acct/snap_diff/sum_dw70 与本复算逐字相同 ✓")

# 臂汇总
print("\n" + "=" * 100)
print("① 臂汇总复算（观测级；不下裁定）")
print("=" * 100)
for src in ("S", "F"):
    for arm in ("0x23", "0x24"):
        ws = [w for w in WINS if SRC_OF[w] == src and ARM_OF[w] == arm]
        vals = sorted(data[w]["acct"][2] for w in ws)
        med = statistics.median(vals); mean = sum(vals) / 3
        print(f"{src}_{arm}: n=3 each={[f'{v/1e6:.2f} MB ({v})' for v in vals]} 中位={med/1e6:.3f} MB ({med}) 均值={mean/1e6:.3f} MB ({mean:.0f}) min={min(vals)} max={max(vals)}")
    a = sorted(data[w]["acct"][2] for w in WINS if SRC_OF[w] == src and ARM_OF[w] == "0x23")
    b = sorted(data[w]["acct"][2] for w in WINS if SRC_OF[w] == src and ARM_OF[w] == "0x24")
    ma, mb = statistics.median(a), statistics.median(b)
    ea, eb = sum(a) / 3, sum(b) / 3
    sep = min(a) > max(b)
    U = sum(1 for x in a for y in b if y > x)  # Mann-Whitney U (B>A 计数)
    p_two = 2 * comb(6, 3) ** -1 if sep else None  # 完全分离时 U∈{0,9}, 双侧精确 p
    print(f"  {src} 臂: 中位比 B/A = {mb/ma:.3f} (−{100*(1-mb/ma):.0f}%) | 均值比 = {eb/ea:.3f} (−{100*(1-eb/ea):.1f}%) | min A > max B 完全分离: {sep} (minA={min(a)}, maxB={max(b)}) | U={U}, 双侧精确 p={p_two}")

print("\n--- 报告 §3 表逐格对账 ---")
rep = {  # 报告值
    "S_A1": 9437496, "F_A1": 12251792, "S_B1": 3702344, "F_B1": 7333800,
    "S_A2": 9748424, "F_A2": 11500296, "S_B2": 9178616, "F_B2": 3540072,
    "S_A3": 9785144, "F_A3": 9596872, "S_B3": 1167272, "F_B3": 5484456,
}
bad = [w for w in WINS if data[w]["acct"][2] != rep[w]]
print("12/12 窗 ΔW70 与报告逐格相同:" , not bad, bad or "")
# pc/taken/host_miss 对账
reppc = {"S_A1": (1061158912, 1064304328, 0.2955), "F_A1": (1061158912, 1061490032, 0.0312), "S_B1": (1069547520, 1070039480, 0.0460),
         "F_B1": (1065353216, 1066408024, 0.0989), "S_A2": (1061158912, 1063993400, 0.2664), "F_A2": (1061158912, 1062241528, 0.1019),
         "S_B2": (1061158912, 1064563208, 0.3198), "F_B2": (1069547520, 1070201752, 0.0611), "S_A3": (1061158912, 1063956680, 0.2630),
         "F_A3": (1061158912, 1064144952, 0.2806), "S_B3": (1069547520, 1072574552, 0.2822), "F_B3": (1065353216, 1068257368, 0.2719)}
bad2 = [w for w in WINS if (data[w]["acct"][0], data[w]["acct"][1], data[w]["miss"]) != reppc[w]]
print("12/12 窗 pc/taken/host_miss_pct 与报告逐格相同:", not bad2, bad2 or "")
print("TOOL_MD5 12/12 =", sorted({data[w]['tool_md5'] for w in WINS}))
print("read_error 分布:", {w: data[w]['done'][6] for w in WINS})
