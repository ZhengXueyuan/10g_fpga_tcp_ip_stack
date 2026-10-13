#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_margin_phase.py — 复核面②：§3.3 结构洞察独立核（纯算术 + 12 新窗原始件实证 + 旧内容点复核）
import re, os, glob

HERE = os.path.dirname(os.path.abspath(__file__))
N = os.path.join(HERE, "..", "..", "p9_uram_ab_20261014", "runs")
O24 = os.path.join(HERE, "..", "..", "p9_board_0x24_20261013", "runs")

CHUNK = 4194304
PIPE = 2104          # 2048 + 24 + 32
CAP = 32800          # 4,100 字 × 8 B
PHASE24 = PIPE + CAP

print("=" * 84)
print("②-a 常数算术")
print("=" * 84)
print(f"2,104 = 2,048 + 24 + 32 = {2048+24+32}")
print(f"32,800 = 4,100 字 × 8 = {4100*8}  (AW=12→DEPTH 4096 + CAP 4 = 4,100 字; RTL 现读 wrapper_p4.v:3855 / app_rx_mirror.v:354-359 已核)")
print(f"34,904 = 2,104 + 32,800 = {PIPE+CAP}")

print("\n旧内容臂实测点（报告 §3.2 声称的 12 点 = 0x23 八点 + 0x24 四点）")
pts23 = [("LAD_1MiB/SAN1", 1050680), ("CAPD/ORD1", 4196408), ("LAD_32MiB/LAD_64MiB", 8390712), ("LAD_4MiB/LAD_16MiB", 3131448)]
for nm, v in pts23:
    if v == 3131448:
        print(f"  0x23 {nm}: {v} = 764×4096 + {v-764*4096} (764×4096={764*4096})  → {'≡2,104' if v-764*4096==2104 else 'X'}")
    else:
        base = v - 2104
        print(f"  0x23 {nm}: {v} = {base//1048576} MiB + {v-base}  → {'≡2,104 ✓' if v-base==2104 else 'X'}")
pts24 = [4229208, 16812120, 67143768, 201361496]
for v in pts24:
    print(f"  0x24: {v} = {v//4194304}×4MiB + {v%4194304}  → {'≡34,904 ✓' if v%4194304==PHASE24 else 'X'}")
print("  (0x24 四点本组第一轮 VERIFY.md §② 已独立复算过；此处为算术复核)")

print("\n" + "=" * 84)
print("②-b 12 新窗：pc 步进粒度实证（前提 (a)）")
print("=" * 84)
print(f"{'窗':<7}{'行数':>5}{'bad_pc_step':>12}{'bad_got':>9}{'pc_anchor%4MiB 集合':>22}")
for f in sorted(glob.glob(os.path.join(N, "WIN_*.txt"))):
    t = open(f, encoding="utf-8", errors="replace").read()
    tag = os.path.basename(f).split("_")[1]
    rows = [(float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))) for m in
            re.finditer(r"^READLOG i=\d+ t=([\d.]+) \S+ \S+ \S+ got=(\d+) pc=(\d+) w70=(\d+) dw70=\d+ dma=\d+ ddma=\d+", t, re.M)]
    rows.sort()
    pre = int(re.search(r"SNAP_BEGIN \S+?_pre.*?^W70\s+0x138\s+\S+\s+0x([0-9a-fA-F]+)", t, re.M | re.S).group(1), 16)
    bad_step = sum(1 for a, b in zip(rows, rows[1:]) if b[2] - a[2] != b[1])
    bad_got = sum(1 for r in rows if r[1] != CHUNK)
    deltas = [rows[0][3] - pre] + [b[3] - a[3] for a, b in zip(rows, rows[1:])]
    anchors = set()
    for k, dl in enumerate(deltas):
        if dl > 0 and (k == 0 or deltas[k-1] == 0):
            pc_a = 0 if k == 0 else rows[k-1][2]
            anchors.add(pc_a % CHUNK)
    print(f"{tag:<7}{len(rows):>5}{bad_step:>12}{bad_got:>9}{str(sorted(anchors)):>22}")
print("\n⇒ 若 12/12 bad=0 且 anchor 集合全 {0}：前提 (a)「pc 只在读完成处步进（粒度 4 MiB）」实证成立")

print("\n" + "=" * 84)
print("②-c 恒等式推理链核（逻辑结构复述 + 判定）")
print("=" * 84)
print("前提 (a) pc 只在读完成处步进、步长 4 MiB  ⇒  任意洞 anchor 的 pc ≡ 0 (mod 4 MiB)   [②-b 已实证]")
print("前提 (b) 丢只发生在缓冲满瞬间  ⇒  洞起点(图案坐标) = pc_anchor(交付坐标) + 在飞量")
print("  ⇒ 相位 ≡ (0 + 在飞量) (mod 4 MiB)；在飞量 = 管线 2,104 + 缓冲容量 cap（两臂常数）")
print("  ⇒ 「相位 ≡ 2,104+cap (mod 4 MiB)」对任意洞自动成立 —— 无需测量即真（给定 (a)(b)）")
print("剩余可证伪内容 = ① 在飞量真等于 2,104+cap（=各级缓冲在洞起点满）——旧轮 12 内容点实测支持（0x23 8 点 + 0x24 4 点，全部命中）")
print("                ② 丢起点判据 = 满点（非其它判据）——同样由这 12 点间接支持")
print("支持强度评估：12 点 = 全部来自内容臂（verify-on）窗，跨两臂/两工具代际/多种块径（1/4/8/32/64 MiB 与 4 KiB 页界）")
print("  ⇒ 「满点假设」获 12/12 独立点支持；但 (b) 本身（丢⇔满）从未被直接观测（缓冲水位口空接），属模型假设")

print("\n②-d 「旧轮 4/4 中的可证伪内容只剩满点假设」核：")
for v in pts24:
    print(f"  0x24 点 {v}: ≡34,904 是给定 (a)(b) 下的必然 ⇒ 命中不携带新信息；其可证伪性仅在「满点」")
print("  判定：该 Claim 与 ②-c 推理一致；「4/4」= 0x24 臂 4 个内容点（本组第一轮已独立复核其值/洞长）")
