#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
p9_extrap.py -- 第 2 片 URAM 边际收益外推 (模型, 非测量)
==================================================================================
模型 (逐洞, 可加性假设):
    G_i  = d_i + C_arm          # d_i = 观测洞深; C_arm = 该臂"洞起点时在飞量"上界
    d'_i = max(0, G_i - C_new)  # C_new = 升容后的在飞上界
主量: C_arm = 2104 (0x23) / 34904 (0x24);  ΔC = 32800 (2×URAM) / 98400 (4×URAM)
      => C_new = C_arm + ΔC  (即"在 0x24 基础上再加 1/3 片 URAM")
备用口径 (调用方字面): C_new 直接取 65,600 / 131,200 (= 2×/4× URAM 载荷, 不含 2104 管线)

三种口径 (按"洞"定义与合并方式):
  Def-A  : 极大连续正区间段 = 一个洞 (合并; 对降幅保守)
  Def-B  : 每个正区间各自一个洞 (拆分; 对降幅乐观) —— 即降幅上界
  单程模型: 整窗 = 单一 excursion ⇒ 降幅 = min(ΔC, obs) —— 降幅下界
真值 ∈ [单程, Def-A or Def-B], 取决于缓冲在两洞之间是否真排空 (未观测; 见报告 §假设).
"""
import importlib.util
import random
import sys
import os
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("hp", os.path.join(HERE, "p9_holeparse.py"))
hp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hp)

NEW = "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_uram_ab_20261014/runs/WIN_*.txt"
OLD24 = ["D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S0_20261013_220859.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S1_S5_20261013_220956.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S6_S10_20261013_221125.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F0_20261013_220930.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F1_F5_20261013_221254.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F6_F9_20261013_221427.txt"]
OLD23 = ["D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A1.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A1N2.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A4.txt"]

C_ARM = {"0x23": 2104, "0x24": 34904}
C_ARM_ALT = {"0x23": 0, "0x24": 32800}      # 只数"缓冲载荷"、不含管线的口径
DC = {"2xURAM": 32800, "4xURAM": 98400}
C_TOTAL_LITERAL = {"2xURAM": 65600, "4xURAM": 131200}   # 调用方字面口径


def load_windows():
    wins = []
    import glob
    for f in sorted(glob.glob(NEW)):
        txt = open(f, encoding="utf-8", errors="replace").read()
        for r in hp.parse_windows(txt, os.path.basename(f)):
            hp.analyze(r)
            r["arm"] = "0x24" if r["tag"].split("_")[-1][0] == "B" else "0x23"
            r["src"] = r["tag"][0]              # S = 单源, F = 4 源
            r["grp"] = "new:" + r["tag"]
            wins.append(r)
    for f in OLD24:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for r in hp.parse_windows(txt, os.path.basename(f)):
            hp.analyze(r)
            r["arm"] = "0x24"
            r["src"] = "S" if r["tag"].startswith("S") else "F"
            r["grp"] = "old24:" + r["tag"]
            wins.append(r)
    for f in OLD23:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for r in hp.parse_windows(txt, os.path.basename(f)):
            hp.analyze(r)
            r["arm"] = "0x23"
            r["src"] = "F" if r["tag"].startswith("A4") else "S"   # hostread: A1/A1N2 = 单源, A4 = 4 源
            r["grp"] = "old23:" + r["tag"]
            wins.append(r)
    return wins


def predict(depths, c_arm, c_new):
    """给定逐洞深度, 预测升容后总丢 + 降幅"""
    g = [d + c_arm for d in depths]
    d2 = [max(0, x - c_new) for x in g]
    return sum(d2)


def stat(v):
    if not v:
        return "-"
    s = sorted(v)
    n = len(s)
    med = s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
    return f"min={s[0]:,} med={int(med):,} max={s[-1]:,}"


def main():
    wins = load_windows()
    w_src = {w["grp"]: w["src"] for w in wins}
    rep = []
    W = rep.append
    W("=" * 110)
    W("p9_extrap.py -- 第 2 片/第 3 片 URAM 边际收益外推 (模型; 假设见 §6)")
    W("=" * 110)
    W(f"\n窗数: 新 12 + 旧0x24 {sum(1 for w in wins if w['grp'].startswith('old24'))} + 旧0x23基线 {sum(1 for w in wins if w['grp'].startswith('old23'))}")

    # ---- §1 逐窗: 主口径 (C_arm 真实在飞, ΔC = 32800/98400) ----
    W("\n## 1. 逐窗外推表 (主口径: C_arm = 2104/34904, ΔC = 32800 与 98400; 模型 = 逐洞独立)")
    W(f"{'窗':<14} {'臂':<5} {'洞定义':<6} {'洞数':>4} {'现观测':>10} "
      f"{'2×URAM 预测':>12} {'降幅':>7} {'降幅%':>6} | {'4×URAM 预测':>12} {'降幅%':>6} | {'单程下界降幅%':>10}")
    rows_csv = []
    for w in wins:
        obs = w["sum_my_delta"]
        c_arm = C_ARM[w["arm"]]
        for df, key in (("A", "bursts"), ("B", "bursts_b")):
            depths = [b["depth"] for b in w[key]]
            p2 = predict(depths, c_arm, c_arm + DC["2xURAM"])
            p4 = predict(depths, c_arm, c_arm + DC["4xURAM"])
            red2 = obs - p2
            red4 = obs - p4
            floor2 = min(DC["2xURAM"], obs)
            W(f"{w['grp']:<14} {w['arm']:<5} {df:<6} {len(depths):>4} {obs:>10,} "
              f"{p2:>12,} {red2:>7,} {100*red2/obs:>5.1f}% | {p4:>12,} {100*red4/obs:>5.1f}% | {100*floor2/obs:>9.2f}%")
            rows_csv.append((w["grp"], w["arm"], df, len(depths), obs, p2, red2, p4, red4, floor2))

    # ---- §2 臂汇总 (按臂/构型 pooled) ----
    W("\n## 2. 臂汇总 (pooled; 每窗降幅的中位/极值; 口径 = Def-A, ΔC=32800)")
    agg = defaultdict(list)
    for (grp, arm, df, n, obs, p2, red2, p4, red4, fl) in rows_csv:
        if df != "A":
            continue
        s = w_src[grp]
        agg[(arm, s)].append((obs, p2, red2, p4, red4))
    W(f"{'臂-构型':<10} {'窗数':>4} {'观测 中位':>12} {'2×URAM 预测中位':>14} {'降幅中位':>10} {'降幅% 中位(range)':>18}")
    for k in sorted(agg):
        v = agg[k]
        med = lambda i: sorted(x[i] for x in v)[len(v) // 2]
        pcts = sorted(100 * x[2] / x[0] for x in v)
        W(f"{k[0]+'-'+k[1]:<10} {len(v):>4} {med(0):>12,} {med(1):>14,} {med(2):>10,} "
          f"{pcts[len(pcts)//2]:>8.1f}% ({pcts[0]:.1f}–{pcts[-1]:.1f}%)")

    # ---- §3 敏感性 1: 洞定义 (Def-A 合并 vs Def-B 拆分) ----
    W("\n## 3. 敏感性① 洞定义 (Def-A 合并 = 保守; Def-B 逐区间 = 乐观) [ΔC=32800]")
    W(f"{'窗':<14} {'Def-A 洞数':>9} {'Def-A 降幅%':>11} {'Def-B 洞数':>9} {'Def-B 降幅%':>11} {'差(pp)':>8}")
    for w in wins:
        obs = w["sum_my_delta"]
        c = C_ARM[w["arm"]]
        da = [b["depth"] for b in w["bursts"]]
        db = [b["depth"] for b in w["bursts_b"]]
        ra = 100 * (obs - predict(da, c, c + DC["2xURAM"])) / obs
        rb = 100 * (obs - predict(db, c, c + DC["2xURAM"])) / obs
        W(f"{w['grp']:<14} {len(da):>9} {ra:>10.1f}% {len(db):>9} {rb:>10.1f}% {rb-ra:>7.1f}")

    # ---- §4 敏感性 2: 事件深度 ±20% 重采样 (降幅% 的比值口径) ----
    #   说明: 主模型的降幅 = Σ max(0, d_i - ΔC); 由于 d_i = G_i - C_arm 由模型定义, 对 G 加噪
    #   ≡ 对 d 加噪. 这里用**比值口径** (降幅/该重采样总丢) 避免"与未加噪观测比"的伪负值.
    W("\n## 4. 敏感性② 事件深度 ±20% 重采样 (200 种子; 比值口径 = Σmin(d',ΔC)/Σd'; 报 p5/p50/p95)")
    rnd = random.Random(20261014)
    W(f"{'窗':<14} {'Def':<4} {'降幅% p5':>9} {'p50':>7} {'p95':>7}  (无噪声值)")
    for w in wins:
        obs = w["sum_my_delta"]
        c = C_ARM[w["arm"]]
        for df, key in (("A", "bursts"), ("B", "bursts_b")):
            ds = [b["depth"] for b in w[key]]
            base = 100 * sum(min(d, DC["2xURAM"]) for d in ds) / sum(ds)
            vals = []
            for _ in range(200):
                dn = [d * (1 + 0.2 * (rnd.random() * 2 - 1)) for d in ds]
                vals.append(100 * sum(min(d, DC["2xURAM"]) for d in dn) / sum(dn))
            vals.sort()
            W(f"{w['grp']:<14} {df:<4} {vals[10]:>8.1f}% {vals[100]:>6.1f}% {vals[190]:>6.1f}%   ({base:.1f}%)")

    # ---- §5 敏感性 3: 容量常数口径 ----
    W("\n## 5. 敏感性③ 容量常数口径 (Def-A; 数字 = 降幅%)")
    W("  口径① 主: C_arm = 2104/34904, C_new = +32800")
    W("  口径② 备: C_arm = 0/32800 (只数缓冲载荷), C_new = +32800")
    W("  口径③ 调用方字面: C_new = 65600 (总), 即 ΔC = 65600 - C_arm")
    W("  口径④ 若 2104 实为 2048+56 的不确定度: C_arm(+56)")
    W(f"{'窗':<14} {'①主':>8} {'②载荷只':>8} {'③字面':>8} {'④+56':>8}")
    for w in wins:
        obs = w["sum_my_delta"]
        a = w["arm"]
        ds = [b["depth"] for b in w["bursts"]]
        r1 = 100 * (obs - predict(ds, C_ARM[a], C_ARM[a] + DC["2xURAM"])) / obs
        r2 = 100 * (obs - predict(ds, C_ARM_ALT[a], C_ARM_ALT[a] + DC["2xURAM"])) / obs
        r3 = 100 * (obs - predict(ds, C_ARM[a], C_TOTAL_LITERAL["2xURAM"])) / obs
        r4 = 100 * (obs - predict(ds, C_ARM[a] + 56, C_ARM[a] + 56 + DC["2xURAM"])) / obs
        W(f"{w['grp']:<14} {r1:>7.1f}% {r2:>7.1f}% {r3:>7.1f}% {r4:>7.1f}%")

    # ---- §6 G 分布跨臂可比性 ----
    W("\n## 6. G 分布跨臂可比性 (量 = G_i = d_i + C_arm; Def-B 逐区间, pooled)")
    for grp, filt in (("新 S_A (0x23)", lambda w: w["grp"].startswith("new:S_A")),
                      ("新 S_B (0x24)", lambda w: w["grp"].startswith("new:S_B")),
                      ("新 F_A (0x23)", lambda w: w["grp"].startswith("new:F_A")),
                      ("新 F_B (0x24)", lambda w: w["grp"].startswith("new:F_B")),
                      ("旧 S(0x24) 21窗", lambda w: w["grp"].startswith("old24:S")),
                      ("旧 F(0x24) 21窗", lambda w: w["grp"].startswith("old24:F")),
                      ("旧 0x23 基线", lambda w: w["grp"].startswith("old23"))):
        g = []
        for w in wins:
            if filt(w):
                g += [b["depth"] + C_ARM[w["arm"]] for b in w["bursts_b"]]
        W(f"  {grp:<16} n={len(g):>4}  {stat(g)}")

    txt = "\n".join(rep)
    open(os.path.join(HERE, "extrap.report.txt"), "w", encoding="utf-8").write(txt)
    with open(os.path.join(HERE, "extrap.windows.csv"), "w", encoding="utf-8") as f:
        f.write("window,arm,hole_def,n_holes,obs_bytes,pred_2xURAM,red_2xURAM,pred_4xURAM,red_4xURAM,floor_reduction\n")
        for r in rows_csv:
            f.write(",".join(str(x) for x in r) + "\n")
    print("[OK] -> extrap.report.txt / extrap.windows.csv")


if __name__ == "__main__":
    main()
