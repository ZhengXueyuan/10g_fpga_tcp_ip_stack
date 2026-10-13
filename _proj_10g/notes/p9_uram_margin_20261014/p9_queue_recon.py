#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
p9_queue_recon.py -- 在飞量(缓冲占用+管线) O* 的重建 (决定外推模型该用哪种事件口径)

模型 (唯一假设: 源交付率 R 恒定, 起始时刻 t0):
    O*_j := R*(t_j - t0) - pc_j - w70_j        (t_j = 第 j 个 READLOG 采样时刻)
    含义 = 已到 tap 但尚未交付给宿主、也未被丢的字节数 = 镜像 FIFO + acc/stg + 成形器 + URAM 占用
    (0x24 结构上界 = 2104 + 32800 = 34904; 0x23 = 2104)
    约束: 0 <= O*_j <= CAP  (CAP = 34904 / 2104; 另试宽松 CAP)
    丢字节发生在某区间 <=> 该区间内 URAM 满 (O* 顶到近 CAP)

方法: 对每个 R 求可行的 t0 区间 [lo(R), hi(R)]; 非空 = 该 R 可解释数据.
     readout: (a) 可行 (R,t0) 是否存在; (b) 在可行域内 O* 路径的极值形态
     —— 关键问题: O* 在两个丢字节簇之间是否回到 ~0 (决定"独立事件" vs "持续亏空" 模型).
"""
import re
import sys
import glob

RL = re.compile(r"READLOG i=(\d+) t=([\d.]+) \S+ \S+ \S+ got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+)")
SUM = re.compile(r"SRC.*?UDP_SUM.*?pay_bytes=(\d+) dur_s=([\d.]+)")
ACC = re.compile(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)")
W70S = re.compile(r"^W70\s+0x[0-9A-Fa-f]+\s+\S+\s+0x([0-9A-Fa-f]+)", re.M)


def load_win(path, tag_want=None):
    txt = open(path, encoding="utf-8", errors="replace").read()
    outs = []
    for part in re.split(r"(?m)^=== WIN ", txt)[1:]:
        tag = part.split()[0]
        if tag_want and tag != tag_want:
            continue
        rows = sorted([(int(g[0]), float(g[1]), int(g[2]), int(g[3]), int(g[4]), int(g[5]))
                       for g in RL.findall(part)], key=lambda r: r[1])
        snaps = [int(x, 16) for x in W70S.findall(part)]
        pre = snaps[0] if snaps else 0
        src = SUM.search(part)
        acc = ACC.search(part)
        outs.append({"tag": tag, "rows": rows, "pre": pre,
                     "pay": int(src.group(1)) if src else None,
                     "dur": float(src.group(2)) if src else None,
                     "acct": int(acc.group(3)) if acc else None})
    return outs


def recon(tag, rows, pre, cap, Rlo_f=0.90, Rhi_f=1.12, nR=221, mdur=None):
    """扫描 R, 求可行 t0 区间"""
    T = [r[1] for r in rows]
    pc = [r[2] for r in rows]
    w = [(r[3] - pre) for r in rows]      # 相对 arm 的累计丢
    R0 = rows[-1][2] / max(mdur, 1e-9)    # 粗估 (仅作扫描中心)
    # 更稳的 R0: 用源总字节/时间 (由调用者给) —— 这里用 pc 总量/跨度兜底
    res = []
    for k in range(nR):
        R = R0 * (Rlo_f + (Rhi_f - Rlo_f) * k / (nR - 1))
        # O*_j = R(t_j - t0) - pc_j - w70_j
        # O* >= 0        -> t0 <= t_j - (pc_j + w_j)/R
        # O* <= cap      -> t0 >= t_j - (pc_j + w_j + cap)/R
        hi = min(T[j] - (pc[j] + w[j]) / R for j in range(len(rows)))
        lo = max(T[j] - (pc[j] + w[j] + cap) / R for j in range(len(rows)))
        if lo <= hi:
            res.append((R, lo, hi))
    return res


def main():
    D = "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_uram_ab_20261014/runs/"
    cases = [("S_A1", D + "WIN_S_A1_20261014_002411.txt", 2104),
             ("S_B1", D + "WIN_S_B1_20261014_002818.txt", 34904),
             ("S_B2", D + "WIN_S_B2_20261014_003601.txt", 34904),
             ("S_B3", D + "WIN_S_B3_20261014_004334.txt", 34904),
             ("S_A2", D + "WIN_S_A2_20261014_003211.txt", 2104),
             ("F_A1", D + "WIN_F_A1_20261014_002501.txt", 2104),
             ("F_B1", D + "WIN_F_B1_20261014_002853.txt", 34904),
             ("F_B2", D + "WIN_F_B2_20261014_003635.txt", 34904),
             ("F_B3", D + "WIN_F_B3_20261014_004410.txt", 34904)]
    print( "# 队列重建: O* = R*(t-t0) - pc - w70,  约束 0<=O*<=CAP")
    print(f"{'tag':<5} {'CAP':>6} {'源R(MB/s)':>9} {'可行t0区间':>18} {'可行带宽宽度':>10}  O*路径形态")
    for tag, path, cap in cases:
        wins = load_win(path, tag)
        if not wins:
            print(f"{tag:<5} 未找到")
            continue
        w = wins[0]
        pay, dur = w["pay"], w["dur"]
        R_true = pay / dur if (pay and dur) else None
        # 用源真值做扫描中心 (KB/µs -> B/s): pay/dur = B/s
        res = recon(tag, w["rows"], w["pre"], cap, mdur=dur)
        if not res:
            print(f"{tag:<5} {cap:>6} {R_true/1e6:>9.2f}   !!! 无可行 (R,t0) => 恒定 R 假设被数据拒绝 (或 CAP 太紧)")
            continue
        Rs = [r[0] for r in res]
        los = [r[1] for r in res]
        his = [r[2] for r in res]
        frac_lo = min(los) / max(his)   # 目测 ~1 即 t0 几乎钉死
        # 取可行域中点做 O* 路径
        Rm = Rs[len(Rs) // 2]
        # t0 选使 O* 峰最靠 CAP 的 (即 lo 端), 也给端点形态
        t0_lo = max(los)
        T = [r[1] for r in w["rows"]]
        pc = [r[2] for r in w["rows"]]
        ww = [r[3] - w["pre"] for r in w["rows"]]
        O_lo = [Rm * (T[j] - t0_lo) - pc[j] - ww[j] for j in range(len(T))]
        O_hi = [Rm * (T[j] - min(his)) - pc[j] - ww[j] for j in range(len(T))]
        print(f"{tag:<5} {cap:>6} {R_true/1e6:>9.2f}   [{min(los):.4f},{max(his):.4f}]   "
              f"{len(res):>3}/{len(res)}档   O*(t0=lo端): min={min(O_lo):>7.0f} max={max(O_lo):>7.0f} | "
              f"O*(t0=hi端): min={min(O_hi):>7.0f} max={max(O_hi):>7.0f}")


if __name__ == "__main__":
    main()
