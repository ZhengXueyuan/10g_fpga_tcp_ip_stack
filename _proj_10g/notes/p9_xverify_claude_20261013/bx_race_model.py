#!/usr/bin/env python3
# bx_race_model.py -- Claude 组独立验证 B-1（dual READLOG dw70 两段锁竞态）
#   ⛔ 自建（不读 kimi 的 xreview_b_verify.py）。
#   M1: 锁序枚举 —— 两线程各一对 (S=snap, C=commit)，锁互斥 + 线程内程序序 S<C；
#       snap 值**按时间序**赋值（计数器单调 + 两 S 之间可发生丢事件）——
#       与 kimi 手推的差别：snap 值不能与锁序无关地钉死。
#   M2: 对抗调度蒙特卡洛（显式强制线程内 S_k<C_k<S_{k+1} = kimi 模型缺失的那条约束）。
#   M3: 我方"相位分离 + 瞬态重叠"形态模型（参数是假设，标注清楚）。
import random, itertools

M32 = 1 << 32
def dw(snap, rl):
    return (snap - rl) % M32

def M1():
    print("=" * 84)
    print("M1: 锁序枚举（互斥 + 线程内 S<C；snap 值按时间序赋值：先 S 读 v_lo，后 S 读 v_hi>v_lo）")
    print("=" * 84)
    orders = [p for p in itertools.permutations("A1 A2 B1 B2".split())]
    def admissible(seq):
        i = {op: k for k, op in enumerate(seq)}
        return i["A1"] < i["A2"] and i["B1"] < i["B2"]
    nwrap = 0
    wrap_seq = []
    for seq in orders:
        if not admissible(seq):
            continue
        # snap 值: 按 S 出现的时间序，v_lo=1000 (先), v_hi=1500 (后)。rl 初值 = 1000 (前一条 commit)
        s_ops = [op for op in seq if op.endswith("1")]
        val = {s_ops[0]: 1000, s_ops[1]: 1500}
        rl = 1000
        out = []
        for op in seq:
            if op.endswith("1"):
                continue
            v = val[op[0] + "1"]
            d = dw(v, rl)
            out.append((op, d))
            rl = v
        wrap = any(d >= (1 << 31) for _, d in out)
        if wrap:
            nwrap += 1; wrap_seq.append(" ".join(seq))
        desc = "  ".join(f"{op}:dw={d}" + ("(WRAP)" if d >= (1 << 31) else "") for op, d in out)
        print(f"  {'WRAP ' if wrap else '     '} {' '.join(seq):20s} ⇒ {desc}")
    print(f"⇒ 可行锁序 6 种；回绕序 = {nwrap} 种: {wrap_seq}")
    print("  本质（定理）: 回绕 ⟺ **两线程的 S 先后与 C 先后相反（两个逐 read 窗嵌套）**；"
          "\n  否则（同序/顺序）零回绕。且回绕还需两 S 之间有 ≥1 字节丢事件（v_hi>v_lo）。")
    print("  ⚠️ 与 kimi 手推的对照: 其确定性交错 = 嵌套序之一（A1 B1 B2 A2），成立；"
          "\n     但其随机模型允许**违反线程内程序序**的调度（commit 漂到下一次 snap 之后）⇒ 高估。")

def M2(rows_per_thread=8, trials=20000, seed=20261013):
    print()
    print("=" * 84)
    print("M2: 对抗调度蒙特卡洛（强制线程内 S_k<C_k<S_{k+1}；op 原子；两窗可任意重叠）")
    print("=" * 84)
    rnd = random.Random(seed)
    tot_rows = tot_wrap = 0
    for _ in range(trials):
        ops = [[] for _ in range(2)]
        for t in range(2):
            for k in range(rows_per_thread):
                ops[t] += [(t, "S"), (t, "C")]
        ptr = [0, 0]; rl = 0; w70 = 0; snap = [0, 0]; wrapped = 0; rows = 0
        while ptr[0] < len(ops[0]) or ptr[1] < len(ops[1]):
            avail = [t for t in (0, 1) if ptr[t] < len(ops[t])]
            t = rnd.choice(avail)
            kind = ops[t][ptr[t]][1]; ptr[t] += 1
            if kind == "S":
                snap[t] = w70
                w70 += rnd.randint(0, 43008)
            else:
                d = dw(snap[t], rl); rl = snap[t]
                if d >= (1 << 31): wrapped += 1
                rows += 1
        tot_rows += rows; tot_wrap += wrapped
    print(f"  每线程 {rows_per_thread} 行 × {trials} 次: 回绕行 {tot_wrap}/{tot_rows} = "
          f"{100.0*tot_wrap/max(tot_rows,1):.1f}%")
    print("  ⚠️ op 瞬时 + 两窗任意重叠 ⇒ 这是「代码级允许度」的**最坏界**，不是真机频率；"
          "\n     真机两窗被 desc_lock 相位分离（见报告 §B-1）。")

def M3(trials=4000, seed=7):
    print()
    print("=" * 84)
    print("M3: 相位分离形态模型（假设参数: 块间 26 ms / 窗宽 5 µs / 瞬态重叠率 p_ov）")
    print("=" * 84)
    for p_ov in (0.0, 0.005, 0.02, 0.10):
        rnd = random.Random(seed)
        tot = wrap = 0
        for _ in range(trials):
            n = 64
            events = []
            for t in range(2):
                base = 0.0 if t == 0 else 0.013
                for k in range(n // 2):
                    events.append([base + k * 0.026, t, "S"])
                    events.append([base + k * 0.026 + 5e-6, t, "C"])
            if rnd.random() < p_ov:                  # 瞬态: 10% 的事件再加微抖动
                for e in events:
                    if rnd.random() < 0.1:
                        e[0] += rnd.uniform(-6e-6, 6e-6)
            events.sort(key=lambda x: x[0])
            rl = 0; w70 = 0; snap = [0, 0]
            for _, t, kind in events:
                if kind == "S":
                    snap[t] = w70
                    w70 += rnd.randint(0, 43008)
                else:
                    d = dw(snap[t], rl); rl = snap[t]
                    if d >= (1 << 31): wrap += 1
                    tot += 1
        print(f"  p_ov={p_ov:<5}: 回绕行 {wrap}/{tot} = {100.0*wrap/max(tot,1):.3f}%")
    print("  ⚠️ 参数 p_ov/抖动幅度均为**假设值**；本模型只用于说明"
          "\n     「相位重叠是唯一触发条件」，不是真机频率测量。")

if __name__ == "__main__":
    M1(); M2(); M3()
