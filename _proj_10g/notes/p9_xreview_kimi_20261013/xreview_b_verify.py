#!/usr/bin/env python3
# B 捆对抗审查 — 构造性验证脚本 (Kimi 组跨组审查, 2026-10-13)
# V1: --dual 合并状态机推演 (现读代码 lines 1265-1274 的逐字复刻)
# V2: dual READLOG dw70 两段锁窗口竞态 (代码 lines 1199-1210)
# V3: print_readlog 中位数口径 vs 交付分析器 statistics.median (真实窗 LAD_1048576)
import random, re, statistics

CH = 4 * 1024 * 1024  # 4 MiB 块

def merge_pc(got_of, len_of):
    """逐字复刻 p7b_mir_dump.cpp:1266-1274 的合并循环"""
    pc = 0
    for j in range(len(got_of)):
        got = got_of[j]
        pc += got
        if got < len_of[j]:
            break
    return pc

def V1():
    print("=" * 72)
    print("V1: dual 合并状态机 — pc 记账对完成次序/截断/短读的推演")
    print("=" * 72)
    n = 8
    len_of = [CH] * n

    # (a) 正常交错: 全部满块, 任何完成次序
    got_of = [CH] * n
    pc = merge_pc(got_of, len_of)
    print(f"(a) 全满块 8/8:            pc={pc:>11}  == {n*CH} ? {pc == n*CH}")

    # (b) 看门狗截断: chunk3 之后没有数据 (chunk3 读失败, 4..7 未尝试)
    got_of = [CH]*3 + [0]*5
    len_of2 = [CH]*3 + [0]*5          # 未尝试块 len_of=0 (初始值)
    pc = merge_pc(got_of, len_of2)
    print(f"(b) wd 截断 (3 满, 后未尝试): pc={pc:>11}  == {3*CH} ? {pc == 3*CH}")

    # (c) 完成次序颠倒: 字节账与次序无关 (合并按块号, 不按完成序)
    got_of = [CH]*n
    pc = merge_pc(got_of, len_of)
    print(f"(c) OOO 完成 (记账序不变):  pc={pc:>11}  == {n*CH} ? {pc == n*CH}")

    # (d) 中部短读: chunk4 只回 2 MiB (驱动短读无错), 两线程继续读 5/6/7
    got_of = [CH]*4 + [CH//2] + [CH]*3
    pc = merge_pc(got_of, len_of)
    print(f"(d) chunk4 半块 (无错继续): pc={pc:>11}  == {4*CH+CH//2} ? {pc == 4*CH+CH//2}")
    print("    ⚠ (d) 的记账仍是'每块各读一次之和', 但 chunk5/6/7 缓冲里装的")
    print("      是短读点之后的续流 — buf[pc..] 内容相对流序错位;")
    print("      verify 只查 [0,pc) ⇒ (d) 形态下 pc 之后的内容错位不可见,")
    print("      若 chunk5 与 chunk6 的提交序再颠倒 ⇒ [0,pc) 内部交换, 仅 verify 可抓")

    # (e) 漏计/重复计扫描: 每块恰好一次读、got 只加一次 ⇒ 无重复计入路径
    print("(e) 重复计入路径扫描: dual 无重读分支 (got<0/got==0 均 break 且不再读本块)")
    print("    ⇒ 未发现'某缓冲出错重读导致字节双计'的代码路径 (覆盖面=1186-1216 全分支)")

V2_shown = 0
def V2():
    print("=" * 72)
    print("V2: dual READLOG dw70 竞态 — 两段锁窗口的对抗调度")
    print("=" * 72)
    # 代码结构 (lines 1199-1210):
    #   T_A: dual_mmio_snap()  -> {lock; w70n_A=snap; unlock}
    #   (窗口 W: 无锁, 仅本地计算)
    #   T_A: {lock; dw70_A = w70n_A - rl_w70; rl_w70 = w70n_A; unlock}
    # 若 W 内 T_B 完成了" snap(更晚的 w70) + 更新 rl_w70 ", 则 A 的
    # dw70 = 旧样本 - 更晚基准 = uint32 回绕大数; 且 Σdw70 不再伸缩归零。
    # 构造性调度 (确定性 hand-trace):
    trace = []
    state = {"w70": 1000, "rl_w70": 1000}
    def snap(who):
        state[f"snap_{who}"] = state["w70"]
        trace.append(f"{who}: snap w70n={state['w70']}")
    def commit(who):
        d = (state[f"snap_{who}"] - state["rl_w70"]) % (1 << 32)
        state["rl_w70"] = state[f"snap_{who}"]
        trace.append(f"{who}: dw70={d} (uint32)  rl_w70:={state['rl_w70']}")
        return d
    snap("A"); state["w70"] += 500; snap("B"); commit("B"); dwA = commit("A")
    print("确定性交错 (A 先采样, B 全程插入 A 的两锁窗口之间):")
    for t in trace: print("   ", t)
    print(f"    ⇒ A 行 dw70 = {dwA} = 0x{dwA:08X} (回绕负值; 真区间增量应为 0)")
    # 随机调度仿真: 两线程各 200 行, snap/commit 间有随机概率被插入
    random.seed(20261013)
    wrapped = 0; runs = 2000
    for _ in range(runs):
        w70 = 0; rl = 0; rows = []
        pend = []  # 已采样未提交的 (snap_val,)
        order = []
        for i in range(400):
            order.append((i % 2, "snap")); order.append((i % 2, "commit"))
        random.shuffle(order)
        snaps = {0: [], 1: []}
        for who, op in order:
            if op == "snap":
                snaps[who].append(w70)
                w70 += random.randint(0, 43008)
            else:
                if snaps[who]:
                    s = snaps[who].pop(0)
                    rows.append((s - rl) % (1 << 32)); rl = s
        wrapped += sum(1 for d in rows if d > (1 << 31))
    print(f"随机调度 {runs} 次 (snap/commit 间可任意穿插): 回绕 dw70 行数合计 = {wrapped}")
    print("  注: 真机窗口仅数条指令、概率极低; 但代码**无原子性保证**, 口径句")
    print("  'Δw70/Δdma 属 [上一条→本条] 整区间' (REPORT §1) 对 dual 窗不成立,")
    print("  且 Σdw70 不保证 == drop (同步/AIO 单累计器路径才伸缩归零)。")

def V3():
    print("=" * 72)
    print("V3: READLOG_SUM 中位数口径 vs 交付分析器 (真实窗 LAD_1048576)")
    print("=" * 72)
    path = "../p9_hostread_20261013/runs/LAD_1048576.txt"
    rows = []
    summ = None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"READLOG i=\d+ t=[\d.]+ gap_us=([-\d.]+) mmio_us=([-\d.]+) "
                     r"read_us=([-\d.]+) got=\d+ pc=\d+ w70=\d+ dw70=\d+ dma=\d+ ddma=\d+", line)
        if m:
            rows.append((float(m[1]), float(m[2]), float(m[3])))
        if line.startswith("READLOG_SUM"):
            summ = line.strip()
    g = sorted(r[0] for r in rows); m_ = sorted(r[1] for r in rows); r_ = sorted(r[2] for r in rows)
    n = len(rows)
    upper = lambda v: v[n // 2]          # 工具口径: v[v.size()/2] (偶数 n = 上中位)
    stmed = lambda v: statistics.median(v)
    print(f"n={n} (偶数)")
    for name, v in [("gap_us", g), ("mmio_us", m_), ("read_us", r_)]:
        print(f"  {name:8s} 工具(上中位)={upper(v):>10.1f}  statistics.median={stmed(v):>10.1f}  "
              f"lower={v[(n-1)//2]:>10.1f}")
    print("  件内 READLOG_SUM 行:")
    print("   ", summ[:150], "...")
    print("  ⇒ 偶数 n 时工具口径=**上中位** (v[n/2]), 分析器=两中位均值。")
    print("    大量并列值下差值小但非零 — 'READLOG_SUM med' 与 analyze_readlog.py")
    print("    不可互推; 低-2 (N32b 107,000.8 vs 107,000.0) 即此族口径缝。")

V1(); V2(); V3()
