#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_ab_row.py — ④ 行级抽算：0x23 臂窗 S_A2（253 行 READLOG）
#   检查：行 dw70 无回绕形态（全值 < 2^32、按 t 序链闭合 w70_i = w70_{i-1}+dw70_i、零误差）、
#         t 序链闭合率、pc 链（pc_i = pc_{i-1}+got_i）、Σdw70 == ACCT == 快照差、err 计数 = 0
import re, os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "p9_uram_ab_20261014")
F = os.path.join(BASE, "runs", "WIN_S_A2_20261014_003211.txt")
t = open(F, encoding="utf-8", errors="replace").read()

rows = []
for m in re.finditer(r"^READLOG i=(\d+) t=([\d.]+) gap_us=([\d.]+) mmio_us=([\d.]+) read_us=([\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)", t, re.M):
    rows.append(dict(i=int(m.group(1)), tt=float(m.group(2)), gap=float(m.group(3)), mmio=float(m.group(4)),
                     read=float(m.group(5)), got=int(m.group(6)), pc=int(m.group(7)), w70=int(m.group(8)),
                     dw70=int(m.group(9)), dma=int(m.group(10)), ddma=int(m.group(11))))
print(f"窗 S_A2（0x23 臂）: {len(rows)} 行 READLOG")

# 1) 打印序 vs t 序
drops_print = sum(1 for a, b in zip(rows, rows[1:]) if b["tt"] < a["tt"])
srt = sorted(rows, key=lambda r: r["tt"])
ts_sorted_ok = all(b["tt"] > a["tt"] for a, b in zip(srt, srt[1:]))
print(f"打印序内 t 回退点数 = {drops_print}（dual 两线程块拼接预期 1）; t 全排序后严格递增: {ts_sorted_ok}")

# 2) 行 dw70 无回绕形态：全值 < 2^32；且按 t 序 w70 链闭合
wrap_vals = [r["dw70"] for r in rows if r["dw70"] >= 2**32]
nonneg = all(r["dw70"] >= 0 for r in rows)
W32 = 2**32
err = 0
first_bad = None
prev_w70 = 0  # pre 快照 W70 = 0
for k, r in enumerate(srt):
    expect = (prev_w70 + r["dw70"]) % W32
    if r["w70"] != expect:
        err += 1
        if first_bad is None: first_bad = (k, r["i"], prev_w70, r["dw70"], expect, r["w70"])
    prev_w70 = r["w70"]
print(f"行 dw70 >= 2^32 的个数: {len(wrap_vals)}; dw70 全部 >= 0: {nonneg}")
print(f"t 序 w70 链闭合（w70_i == w70_{{i-1}} + dw70_i, 起点 = pre 快照 0）: 失配 {err}/{len(srt)}", end="")
if first_bad: print(f"  首失配 {first_bad}")
else: print()

# 3) pc 链：pc_i = pc_{i-1} + got_i（t 序）
pc_err = 0
prev_pc = 0
for r in srt:
    if r["pc"] != prev_pc + r["got"]:
        pc_err += 1
    prev_pc = r["pc"]
print(f"t 序 pc 链（pc_i == pc_{{i-1}}+got_i）失配: {pc_err}/{len(srt)}")

# 4) Σdw70 对账
sum_dw70 = sum(r["dw70"] for r in rows)
acct = int(re.search(r"MIR_STREAM_ACCT pc=\d+ taken_bytes=\d+ dW70=(\d+)", t).group(1))
post = int(re.search(r"SNAP_BEGIN S_A2_post.*?^W70\s+0x138\s+mir_drop_bytes\s+0x([0-9a-fA-F]+)", t, re.M | re.S).group(1), 16)
sumline = int(re.search(r"READLOG_SUM n=(\d+).*?dw70_total=(\d+)", t).groups()[1])
print(f"Σdw70 = {sum_dw70}; READLOG_SUM dw70_total = {sumline}; ACCT dW70 = {acct}; post 快照 W70 = {post} ⇒ 四值全等: {sum_dw70 == sumline == acct == post}")

# 5) 抽样打印 3 行
for k in (0, 1, len(srt) - 1):
    r = srt[k]
    print(f"  样例[t序#{k}] i={r['i']} t={r['tt']} got={r['got']} pc={r['pc']} w70={r['w70']} dw70={r['dw70']}")
print(f"\n行级 err 计数（链闭合失配）= {err}；窗 read_error 字段（DONE 行）= {re.search(r'read_error=([01])', t).group(1)}（早停形态，报告 §3-⑤ 已登记）")
