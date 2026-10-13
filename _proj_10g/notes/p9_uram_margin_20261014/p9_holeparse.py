#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
p9_holeparse.py  --  p9_uram_margin_20261014 轮: READLOG 洞(丢字节)事件解析器 (自写; 不承重旧脚本)
================================================================================================
口径 (先写清, 对 0x23/0x24 两臂同一口径):

  * 数据源 = WIN_*.txt 里的 READLOG 行的 **w70 原始列** (板侧 32 位丢字节累加器 W70 的逐行采样)。
    ⛔ 不用打印的 dw70 列作主口径 —— 旧轮已登记该列有"两段锁窗口竞态" (kimi B-1), 实测本卷
       也存在 (w70 跳变在 dw70 列里缺/串位)。自己重算 Δw70 = (w70_j - w70_{j-1}) mod 2^32。
  * dual 窗 (--dual 2): READLOG 行按线程分两段落盘 (i 先 0..N1-1 再 N1..N)。**按 t 排序**后
    才是全局时间序 (旧轮 FIX 轮口径)。pc / w70 都是全局计数器。
  * 洞事件 Def-A (主口径): 按 t 排序的相邻采样区间中, Δw70 > 0 的 **极大连续段** = 一个洞事件;
    洞深 = 该段 ΣΔw70 (字节); 起点 = 段前最后一个 Δ=0 采样的 (t, pc) 与段首采样 (t, pc)。
  * 洞事件 Def-B (敏感性口径): **每个 Δw70>0 的采样区间各自算一个洞** (不合并)。
  * 恒等自检: ΣΔw70(自算, t 序) 必须 == MIR_STREAM_ACCT dW70 == READLOG_SUM dw70_total
              == post 快照 W70 - pre 快照 W70 (四口径; 任一不符即响亮报出)。
  * 相位: pc 只能在读完成处步进,**步长恒 = 4 MiB** (got=4194304 全行) => 交付坐标系里
    任意洞起点的相位 = (pc_onset + 在飞管线 + 缓冲容量) mod 4MiB, 其中 pc_onset 是 4MiB 的倍数。
    => 内容臂测到的"洞起点相位"恒等式 = `4 MiB*k + (2104 + cap)`; 本脚本对无内容窗只能
    给"模型预测相位", 不能给"实测相位" (无 --verify / 无 .bin 捕获)。

用法:  python p9_holeparse.py <WIN_*.txt> [<WIN_*.txt> ...]  --out-prefix OUT
输出:  OUT.bursts.csv  每洞一行
       OUT.windows.csv 每窗汇总
       OUT.report.txt  人读报告 (含自检/单调性/分布)
"""
import argparse
import glob
import os
import re
import sys
from collections import defaultdict

CHUNK = 4194304          # 4 MiB: 每行 got / pc 步长
PIPE_0x23 = 2104         # 0x23 臂在飞管线量 = 2048(镜像 FIFO 64b*256) + 24 + 32
URAM_0x24 = 32800        # 0x24 臂 URAM 载荷容量 = 4100 字 * 8 B
PIPE_0x24 = PIPE_0x23 + URAM_0x24   # = 34,904 (内容臂实测相位)

RL = re.compile(
    r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) read_us=([-\d.]+) "
    r"got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)")
ACC = re.compile(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)")
SUM = re.compile(r"READLOG_SUM n=(\d+) .*dw70_total=(\d+) ddma_total=(\d+)")
DONE = re.compile(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) "
                  r"short=(\d+) ended_early=(\d+) read_error=(\d+) secs=([\d.]+)")
ARGS = re.compile(r"TOOL_ARGS: (.*)")
MD5L = re.compile(r"TOOL_MD5=([0-9a-f]+)")
WINH = re.compile(r"=== WIN (\S+) K=(\d+) MBPS=(\d+) PAYLEN=(\d+) .*?T0=([\d.]+)")
# pre/post 快照里的 W70 行: "W70  0x138  mir_drop_bytes         0x00387e48"
W70S = re.compile(r"^W70\s+0x[0-9A-Fa-f]+\s+\S+\s+0x([0-9A-Fa-f]+)", re.M)


def parse_windows(text, fname):
    """把一份日志切成若干 === WIN 块, 逐块解析"""
    out = []
    parts = re.split(r"(?m)^=== WIN ", text)
    for part in parts[1:]:
        body = part
        m = WINH.match("=== WIN " + body.split("\n", 1)[0] + "\n")
        # WINH 的 .* 不跨行: 重新按首行匹配
        first = body.split("\n", 1)[0]
        m = re.match(r"(\S+) K=(\d+) MBPS=(\d+) PAYLEN=(\d+) BATCH=(\d+) SECS=([\d.]+) "
                     r"SAMPLE_MS=(\d+) CHUNK=(\d+) READLOG=(\d+) AIO=(\d+) PIN=(\S+) TOOL=(\S+) T0=([\d.]+)",
                     first)
        rec = {"file": fname, "tag": m.group(1) if m else "?", "K": int(m.group(2)) if m else None}
        args = ARGS.search(body)
        rec["tool_args"] = args.group(1).strip() if args else None
        md5 = MD5L.search(body)
        rec["tool_md5"] = md5.group(1) if md5 else None

        rows = []
        for mm in RL.finditer(body):
            g = mm.groups()
            rows.append({
                "i": int(g[0]), "t": float(g[1]), "gap": float(g[2]), "mmio": float(g[3]),
                "read": float(g[4]), "got": int(g[5]), "pc": int(g[6]), "w70": int(g[7]),
                "dw70_printed": int(g[8]), "dma": int(g[9]), "ddma": int(g[10])})
        rec["rows"] = rows

        acc = ACC.search(body)
        rec["acc"] = {"pc": int(acc.group(1)), "taken": int(acc.group(2)),
                      "dW70": int(acc.group(3))} if acc else None
        sm = SUM.search(body)
        rec["sum"] = {"n": int(sm.group(1)), "dw70_total": int(sm.group(2)),
                      "ddma_total": int(sm.group(3))} if sm else None
        dn = DONE.search(body)
        rec["done"] = {"pc": int(dn.group(1)), "reads": int(dn.group(2)),
                       "read_error": int(dn.group(7)), "secs": float(dn.group(8))} if dn else None
        # 快照 W70 (pre/post; 取块内出现的全部, 按顺序)
        w70s = [int(x, 16) for x in W70S.findall(body)]
        rec["w70_snaps"] = w70s
        out.append(rec)
    return out


def analyze(rec):
    """t 排序 -> Δw70 -> 洞事件 (Def-A 主 / Def-B 敏感) -> 自检

    ⚠️ 首段口径 (2026-10-14 本脚本自登记): Δ 序列必须**含窗口起始段** —— 即
    delta[0] = rows[0].w70 - pre_w70 (arm 时刻的 W70, 本卷 = 0)。否则首个读数之前的
    丢字节 (本卷 A 臂可达 608 KB) 会被漏算. 实测: 含首段后 ΣΔ == ACCT dW70 == 快照差 (逐窗).
    ⚠️ 另: 打印的 dw70 列 == t 序 w70 逐差 (本卷工具代 48dcbcb2 实测 0 处不一致; 早前
    按"文件序"读会看到"跳变但 dw70=0"的假象 —— dual 窗文件序 = 按线程分两段, 不是 t 序).
    """
    rows = sorted(rec["rows"], key=lambda r: r["t"])
    rec["t_sorted"] = rows
    mono_pc = all(rows[i]["pc"] >= rows[i - 1]["pc"] for i in range(1, len(rows)))
    mono_w70 = all(rows[i]["w70"] >= rows[i - 1]["w70"] for i in range(1, len(rows)))
    rec["mono_pc"], rec["mono_w70"] = mono_pc, mono_w70
    jumps = [i for i in range(1, len(rows)) if rows[i]["t"] < rows[i - 1]["t"]]
    rec["t_jumps"] = len(jumps)

    # pre W70 (快照首值; 本卷应 = 0)
    snaps = rec["w70_snaps"]
    pre_w70 = snaps[0] if snaps else 0
    rec["pre_w70"] = pre_w70

    # 区间序列: idx=0 = [arm, 首采样]; idx=k = (第 k-1 采样, 第 k 采样]
    # anchor[j] = 区间起点 (idx 0 的 anchor = 虚拟原点 pc=0,t=0)
    deltas = [max((rows[0]["w70"] - pre_w70) % (1 << 32), 0)]
    for i in range(1, len(rows)):
        deltas.append(max((rows[i]["w70"] - rows[i - 1]["w70"]) % (1 << 32), 0))
    anchors = [{"t": 0.0, "pc": 0, "i": -1}] + [{"t": rows[i - 1]["t"], "pc": rows[i - 1]["pc"],
                                                "i": rows[i - 1]["i"]} for i in range(1, len(rows))]
    ends = [{"t": rows[0]["t"], "pc": rows[0]["pc"], "i": rows[0]["i"]}] + \
           [{"t": rows[i]["t"], "pc": rows[i]["pc"], "i": rows[i]["i"]} for i in range(1, len(rows))]
    rec["deltas"] = deltas
    rec["sum_my_delta"] = sum(deltas)
    rec["sum_printed"] = sum(r["dw70_printed"] for r in rows)

    def mk_burst(k, i0, i1, depth):
        a = anchors[i0]
        e = ends[i1]
        return {"def": "A", "k": k, "depth": depth, "n_intervals": i1 - i0 + 1,
                "t_start_anchor": a["t"], "t_start_pos": ends[i0]["t"], "t_end": e["t"],
                "pc_anchor": a["pc"], "pc_pos": ends[i0]["pc"], "pc_end": e["pc"],
                "i_anchor": a["i"], "i_pos": ends[i0]["i"],
                "includes_initial": (i0 == 0),
                "phase_anchor_23": (a["pc"] + PIPE_0x23) % CHUNK,
                "phase_anchor_24": (a["pc"] + PIPE_0x24) % CHUNK}

    # Def-A: 极大连续段
    bursts = []
    i = 0
    while i < len(deltas):
        if deltas[i] > 0:
            j = i
            while j < len(deltas) and deltas[j] > 0:
                j += 1
            bursts.append(mk_burst(len(bursts) + 1, i, j - 1, sum(deltas[i:j])))
            i = j
        else:
            i += 1
    rec["bursts"] = bursts

    # Def-B: 每个正区间一个洞
    bursts_b = []
    for idx, d in enumerate(deltas):
        if d > 0:
            b = mk_burst(len(bursts_b) + 1, idx, idx, d)
            b["def"] = "B"
            bursts_b.append(b)
    rec["bursts_b"] = bursts_b
    return rec


def stats(vals):
    if not vals:
        return None
    s = sorted(vals)
    n = len(s)
    med = s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
    return {"n": n, "min": s[0], "med": med, "max": s[-1], "sum": sum(s), "mean": sum(s) / n}


def fmt_bytes(v):
    return f"{v:,}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out-prefix", default="p9_hole")
    a = ap.parse_args()

    files = []
    for pat in a.files:
        g = sorted(glob.glob(pat, recursive=True))
        files.extend(g if g else [pat])

    recs = []
    for f in files:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for r in parse_windows(txt, os.path.basename(f)):
            analyze(r)
            recs.append(r)

    os.makedirs(os.path.dirname(a.out_prefix) or ".", exist_ok=True)
    rep = []
    wrt = rep.append

    wrt("=" * 100)
    wrt("p9_holeparse.py -- READLOG 洞事件解析 (Def-A = 极大连续段; Def-B = 逐区间)")
    wrt("=" * 100)

    # ---- 逐窗自检 ----
    wrt("\n## 0. 四口径对账 (自算 ΣΔw70(t序, 含首段) / ACCT dW70 / READLOG_SUM / 快照 W70 差)")
    all_ok = True
    for r in recs:
        snaps = r["w70_snaps"]
        snap_diff = None
        if len(snaps) >= 2:
            snap_diff = (snaps[-1] - snaps[0]) % (1 << 32)
        # pc 步长检查 (t 序): 每行 pc 差应恰 = 4 MiB
        rows = r["t_sorted"]
        bad_step = sum(1 for i in range(1, len(rows)) if rows[i]["pc"] - rows[i - 1]["pc"] != CHUNK)
        bad_got = sum(1 for x in rows if x["got"] != CHUNK)
        # W70 是**绝对**计数器 (不随 arm 清零; 跨窗累积) ⇒ 尾差口径 = pre + acct − last
        tail_gap = (r["pre_w70"] + r["acc"]["dW70"] - rows[-1]["w70"]) if r["acc"] else None
        vals = {
            "mine": r["sum_my_delta"],
            "acct": r["acc"]["dW70"] if r["acc"] else None,
            "sum": r["sum"]["dw70_total"] if r["sum"] else None,
            "snap": snap_diff}
        uniq = set(v for v in vals.values() if v is not None)
        ok = len(uniq) == 1
        all_ok &= ok
        wrt(f"  {r['tag']:<6} n={len(r['rows']):>3} mine={vals['mine']:>10,} acct={vals['acct']:>10,} "
            f"sum={vals['sum']:>10,} snap={vals['snap'] if vals['snap'] is None else format(vals['snap'], ','):>10} "
            f"-> {'OK' if ok else 'MISMATCH'}"
            f" | printed_sigma={r['sum_printed']:>10,} "
            f"{'==' if r['sum_printed'] == vals['mine'] else '!='} mine"
            f" | pre_w70={r['pre_w70']} tail_gap={tail_gap} "
            f"| mono_pc={r['mono_pc']} mono_w70={r['mono_w70']} bad_pc_step={bad_step} bad_got={bad_got} "
            f"t_jumps={r['t_jumps']}")
    wrt(f"  => 四口径全部闭合: {all_ok}")

    # ---- 逐窗洞结构 ----
    wrt("\n## 1. 逐窗洞结构 (Def-A 主口径)")
    wrt(f"{'tag':<6} {'dW70(B)':>10} {'洞数':>4} {'洞深 min':>9} {'med':>9} {'max':>10} "
        f"{'Σ洞深':>10} {'gap中位(B)':>12} {'主要洞(>50KB)':>14}")
    for r in recs:
        bs = r["bursts"]
        ds = [b["depth"] for b in bs]
        st = stats(ds) if ds else {"n": 0, "min": 0, "med": 0, "max": 0, "sum": 0}
        # 相邻洞间距 (起点 pc 差)
        gaps = [bs[i]["pc_anchor"] - bs[i - 1]["pc_anchor"] for i in range(1, len(bs))]
        gmed = sorted(gaps)[len(gaps) // 2] if gaps else 0
        big = sum(1 for d in ds if d > 51200)
        wrt(f"{r['tag']:<6} {r['sum_my_delta']:>10,} {len(bs):>4} {st['min']:>9,} {int(st['med']):>9,} "
            f"{st['max']:>10,} {st['sum']:>10,} {gmed:>12,} {big:>14}")

    # ---- Def-A vs Def-B ----
    wrt("\n## 2. 定义敏感性: Def-A (合并) vs Def-B (逐区间)")
    wrt(f"{'tag':<6} {'Def-A 洞数':>9} {'Def-A Σ洞深':>11} {'Def-B 洞数':>9} {'Def-B Σ洞深':>11}  (Σ洞深应都 == dW70)")
    for r in recs:
        sa = sum(b["depth"] for b in r["bursts"])
        sb = sum(b["depth"] for b in r["bursts_b"])
        wrt(f"{r['tag']:<6} {len(r['bursts']):>9} {sa:>11,} {len(r['bursts_b']):>9} {sb:>11,}")

    # ---- 逐臂汇总 ----
    wrt("\n## 3. 臂汇总 (按 tag 前缀 S_/F_ + 臂位)")
    arm_of = lambda r: ("S" if r["tag"].startswith("S") else "F", r["tag"].split("_")[-1][0])
    grp = defaultdict(list)
    for r in recs:
        s, w = arm_of(r)
        grp[f"{s}_{w}"].append(r["sum_my_delta"])
    for k in sorted(grp):
        st = stats(grp[k])
        wrt(f"  {k:<6} n={st['n']} each={[format(x, ',') for x in sorted(grp[k])]} "
            f"median={format(int(st['med']), ',')} mean={int(st['mean']):,}")

    # ---- 洞深分布 (全卷 pooled) ----
    wrt("\n## 4. 洞深分布 (pooled; 分 S/F 臂与 A/B 构型)")
    for arm in ("S_A", "S_B", "F_A", "F_B"):
        ds = [b["depth"] for r in recs if arm_of(r) == (arm[0], arm[2]) for b in r["bursts"]]
        st = stats(ds)
        if st:
            q = sorted(ds)
            p90 = q[int(0.9 * (len(q) - 1))]
            wrt(f"  {arm}: n={st['n']} min={st['min']:,} med={int(st['med']):,} "
                f"p90={p90:,} max={st['max']:,} Σ={st['sum']:,}")
        else:
            wrt(f"  {arm}: (无洞)")

    # ---- 相位 ----
    wrt("\n## 5. 相位 (模型; 无内容臂 ⇒ 不可实测)")
    wrt("  说明: pc 只在读完成处步进且步长恒 4 MiB (got 全行 = 4,194,304) ⇒ 任一洞起点的")
    wrt("  交付坐标 = pc_anchor(4MiB 倍数) + 在飞管线 + 容量; 相位 = (2104 + cap) mod 4MiB 按构型恒定.")
    wrt("  本卷 12 窗无 --verify / 无 .bin ⇒ 无实测相位; 下表 = 各窗洞起点的锚 pc 与其模型相位.")
    for r in recs:
        bs = r["bursts"]
        if not bs:
            wrt(f"  {r['tag']:<6} 无洞")
            continue
        ph = set((b["pc_anchor"] + PIPE_0x23) % CHUNK for b in bs)
        ph24 = set(b["phase_anchor_24"] for b in bs)
        mods = set(b["pc_anchor"] % CHUNK for b in bs)
        wrt(f"  {r['tag']:<6} 洞数={len(bs):>3} pc_anchor%4MiB 取值集合={sorted(mods)} "
            f"模型相位(0x23口径)={sorted(ph)} 模型相位(0x24口径)={sorted(ph24)}")

    # ---- 间距 ----
    wrt("\n## 6. 相邻洞间距 (Def-A; 起点 pc 差, 字节)")
    for r in recs:
        bs = r["bursts"]
        gaps = [bs[i]["pc_anchor"] - bs[i - 1]["pc_anchor"] for i in range(1, len(bs))]
        st = stats(gaps)
        if st:
            wrt(f"  {r['tag']:<6} n={st['n']:>3} min={st['min']:,} med={int(st['med']):,} max={st['max']:,}")

    txt = "\n".join(rep)
    open(a.out_prefix + ".report.txt", "w", encoding="utf-8").write(txt)

    # CSV: 每洞
    with open(a.out_prefix + ".bursts.csv", "w", encoding="utf-8") as f:
        f.write("file,tag,def,k,depth,n_intervals,t_start_anchor,t_start_pos,t_end,"
                "pc_anchor,pc_pos,pc_end,i_anchor,i_pos,phase_model_23,phase_model_24\n")
        for r in recs:
            for b in r["bursts"] + r["bursts_b"]:
                f.write(f"{r['file']},{r['tag']},{b['def']},{b['k']},{b['depth']},{b['n_intervals']},{int(b['includes_initial'])},"
                        f"{b['t_start_anchor']:.6f},{b['t_start_pos']:.6f},{b['t_end']:.6f},"
                        f"{b['pc_anchor']},{b['pc_pos']},{b['pc_end']},{b['i_anchor']},{b['i_pos']},"
                        f"{b['phase_anchor_23']},{b['phase_anchor_24']}\n")

    # CSV: 每窗
    with open(a.out_prefix + ".windows.csv", "w", encoding="utf-8") as f:
        f.write("file,tag,K,dW70,n_readlog,n_burstsA,sum_depthA,minA,medA,maxA,n_burstsB,"
                "sum_depthB,sum_printed,mono_pc,mono_w70,t_jumps,read_error,pc_done,tool_md5\n")
        for r in recs:
            da = [b["depth"] for b in r["bursts"]]
            sta = stats(da) if da else {"min": 0, "med": 0, "max": 0, "sum": 0}
            f.write(f"{r['file']},{r['tag']},{r['K']},{r['sum_my_delta']},{len(r['rows'])},"
                    f"{len(r['bursts'])},{sta['sum']},{sta['min']},{int(sta['med'])},{sta['max']},"
                    f"{len(r['bursts_b'])},{sum(b['depth'] for b in r['bursts_b'])},"
                    f"{r['sum_printed']},{r['mono_pc']},{r['mono_w70']},{r['t_jumps']},"
                    f"{r['done']['read_error'] if r['done'] else ''},"
                    f"{r['done']['pc'] if r['done'] else ''},{r['tool_md5']}\n")

    print(f"[OK] 窗数={len(recs)} -> {a.out_prefix}.report.txt / .bursts.csv / .windows.csv")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
