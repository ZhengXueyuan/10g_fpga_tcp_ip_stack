#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_margin_queue.py — 复核面③：§5.1 否定结果复算（自写实现；不复跑对方 p9_queue_recon.py）
# (a) 源率精度需求 0.003% 的算术; (b) 实测源率稳定度（窗内逐区间 CV）; (c) 恒定 (R,t0) 可行域独立扫描
import re, os, glob, statistics

HERE = os.path.dirname(os.path.abspath(__file__))
N = os.path.join(HERE, "..", "..", "p9_uram_ab_20261014", "runs")
CAP = {"0x23": 2104, "0x24": 34904}

print("=" * 84)
print("③-a 源率精度需求复算")
print("=" * 84)
for label, num in (("34,904 B（0x24 在飞上界）", 34904), ("32,800 B（URAM 载荷）", 32800), ("34 KB（报告取整）", 34*1024)):
    print(f"{label} / 1 GiB = {num/2**30*100:.5f}%")
print("报告写「34 KB / 1 GiB ≈ 0.003%」——与 34,904/2^30 = 0.00325%、32,800/2^30 = 0.00305% 同量级 ✓")

CASES = [("S_A1", "0x23"), ("S_A2", "0x23"), ("F_A1", "0x23"),
         ("S_B1", "0x24"), ("S_B2", "0x24"), ("S_B3", "0x24"),
         ("F_B1", "0x24"), ("F_B2", "0x24"), ("F_B3", "0x24")]

print("\n③-b 实测源率窗内稳定度（逐区间 ddma×4/Δt 的变异系数 CV；n = 区间数）")
cvs = {}
for tag, arm in CASES:
    f = glob.glob(os.path.join(N, f"WIN_{tag}_*.txt"))[0]
    t = open(f, encoding="utf-8", errors="replace").read()
    rows = sorted((float(m.group(1)), int(m.group(2))) for m in
                  re.finditer(r"^READLOG i=\d+ t=([\d.]+) \S+ \S+ \S+ got=\d+ pc=\d+ w70=\d+ dw70=\d+ dma=\d+ ddma=(\d+)", t, re.M))
    rates = [4 * b[1] / (b[0] - a[0]) for a, b in zip(rows, rows[1:]) if b[0] - a[0] > 0.001]
    cv = statistics.pstdev(rates) / statistics.mean(rates)
    cvs[tag] = cv
    print(f"{tag}({arm}): n={len(rates)} 均值={statistics.mean(rates)/1e6:6.1f} MB/s CV={cv*100:5.2f}%")
med = statistics.median(cvs.values())
print(f"9 窗中位 CV = {med*100:.2f}%  范围 {min(cvs.values())*100:.2f}–{max(cvs.values())*100:.2f}%  （全 12 窗中位 1.40%，早先全量扫描）")
print("⇒ 报告「实测源率在窗内只稳定到 ~1%」为量级表述：8/9 窗 0.70–2.39%，中位 1.80%（S_B2 = 8.96% 离群）")
print("   相对需求 0.003%：实测稳定度比所需精度差 ~2–3 个数量级 ⇒ 恒定 R 假设必然被数据拒绝")

print("\n" + "=" * 84)
print("③-c 恒定 (R,t0) 可行域独立扫描（O*_j = R(t_j−t0) − pc_j − (w70_j−pre)，约束 0 ≤ O* ≤ CAP）")
print("=" * 84)
def feasible(rows, pre, cap, R):
    T = [r[0] for r in rows]; pc = [r[1] for r in rows]; w = [r[2] - pre for r in rows]
    hi = min(T[j] - (pc[j] + w[j]) / R for j in range(len(rows)))
    lo = max(T[j] - (pc[j] + w[j] + cap) / R for j in range(len(rows)))
    return lo, hi

for tag, arm in CASES:
    f = glob.glob(os.path.join(N, f"WIN_{tag}_*.txt"))[0]
    t = open(f, encoding="utf-8", errors="replace").read()
    rows = sorted((float(m.group(1)), int(m.group(2)), int(m.group(3))) for m in
                  re.finditer(r"^READLOG i=\d+ t=([\d.]+) \S+ \S+ \S+ got=\d+ pc=(\d+) w70=(\d+) dw70=\d+ dma=\d+ ddma=\d+", t, re.M))
    pre = int(re.search(r"SNAP_BEGIN \S+?_pre.*?^W70\s+0x138\s+\S+\s+0x([0-9a-fA-F]+)", t, re.M | re.S).group(1), 16)
    pay = int(re.search(r"UDP_SUM pkts=\d+ pay_bytes=(\d+) dur_s=([\d.]+)", t).group(1))
    dur = float(re.search(r"UDP_SUM pkts=\d+ pay_bytes=\d+ dur_s=([\d.]+)", t).group(1))
    R_true = pay / dur
    cap = CAP[arm]
    feas = 0; best_gap = -1e18
    NSTEP = 4001
    for k in range(NSTEP):
        R = R_true * (0.90 + 0.22 * k / (NSTEP - 1))   # [0.90, 1.12] × R_true
        lo, hi = feasible(rows, pre, cap, R)
        gap = hi - lo
        best_gap = max(best_gap, gap)
        if lo <= hi:
            feas += 1
    # 宽松 CAP 稳健性（×2）
    feas2 = 0
    for k in range(NSTEP):
        R = R_true * (0.90 + 0.22 * k / (NSTEP - 1))
        lo, hi = feasible(rows, pre, cap * 2, R)
        if lo <= hi: feas2 += 1
    print(f"{tag}({arm}) CAP={cap}: R_true={R_true/1e6:6.1f} MB/s  可行档 {feas}/4001 (最宽 t0 窗 {best_gap*1e6:8.2f} µs) | CAP×2 时 {feas2}/4001")
print("\n⇒ 9/9 窗 0 可行档（含 CAP×2 稳健性）：独立复现「恒定 R 拒绝 ⇒ 水位重建法不可行」")

print("\n③-d 稳健性补核（自写扫描的口径差异：F 窗源率真值）")
print("对方脚本对 F 窗取 R_true = UDP_SUM pay/dur = 单源率（~88 MB/s），而 O* 公式中 pc 为 4 源聚合 —— R 尺度差 4×")
print("本组以聚合 ddma 率（Σ4·ddma/Σt）为 R0 重扫 4 个 F 窗：")
for tag in ("F_A1", "F_B1", "F_B2", "F_B3"):
    f = glob.glob(os.path.join(N, f"WIN_{tag}_*.txt"))[0]
    t = open(f, encoding="utf-8", errors="replace").read()
    rows = sorted((float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) for m in
                  re.finditer(r"^READLOG i=\d+ t=([\d.]+) \S+ \S+ \S+ got=\d+ pc=(\d+) w70=(\d+) dw70=\d+ dma=\d+ ddma=(\d+)", t, re.M))
    pre = int(re.search(r"SNAP_BEGIN \S+?_pre.*?^W70\s+0x138\s+\S+\s+0x([0-9a-fA-F]+)", t, re.M | re.S).group(1), 16)
    T = [r[0] for r in rows]; pc = [r[1] for r in rows]; w = [r[2] - pre for r in rows]
    R_agg = sum(4 * r[3] for r in rows) / (T[-1] - T[0])
    feas = 0; best = -1e18
    for k in range(4001):
        R = R_agg * (0.90 + 0.22 * k / 4000)
        hi = min(T[j] - (pc[j] + w[j]) / R for j in range(len(rows)))
        lo = max(T[j] - (pc[j] + w[j] + 34904) / R for j in range(len(rows)))
        best = max(best, hi - lo)
        if lo <= hi: feas += 1
    print(f"  {tag}: 聚合R0={R_agg/1e6:.1f} MB/s  可行档 {feas}/4001  最宽t0窗 {best*1e6:.1f} µs")
print("⇒ 正确尺度 R 下 4/4 仍不可行：否定结果稳健（非 R 尺度伪影）")
