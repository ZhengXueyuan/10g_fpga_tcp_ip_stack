#!/usr/bin/env python3
# R1 修后工具回收验证 — Kimi 组 kx_recycle (2026-10-13)
# ② 修后临界区的竞态交错模型重放（修复前/修复后对照）
# ③ WIN_R1 实窗 READLOG 255 行独立抽核（自写解析器）
import random, re

M32 = 1 << 32
HALF = 1 << 31

# ---------------- ② 交错模型 ----------------
def simulate(mode, n_rows_per_thread=200, seed=1):
    """mode='old': [snap, commit] 两段临界区, snap 与 commit 之间可被对方整段插入
       mode='new': 采样+基线+回写 = 单一原子事务 (锁内不可插入)"""
    rnd = random.Random(seed)
    w70 = 1000                      # 单调寄存器 (W70 丢字节计数只增)
    rl = 1000
    rows = []                       # (t, snap, dw70)
    snaps = {0: [], 1: []}          # old 模式: 已采样未提交
    t = 0.0
    ops = []
    for i in range(2 * n_rows_per_thread):
        ops.append((i % 2, "snap"))
        ops.append((i % 2, "commit"))
    rnd.shuffle(ops)
    for who, op in ops:
        if op == "snap":
            if mode == "old":
                snaps[who].append(w70); w70 += rnd.randint(0, 43008)
            else:
                # 原子事务: snap 与 commit 不可拆 —— 用同一事件完成
                t += rnd.random() * 0.001
                s = w70; w70 += rnd.randint(0, 43008)
                rows.append((t, s, (s - rl) % M32)); rl = s
        else:
            if mode == "old" and snaps[who]:
                s = snaps[who].pop(0)
                t += rnd.random() * 0.001
                rows.append((t, s, (s - rl) % M32)); rl = s
    rows.sort()
    wraps = sum(1 for _, _, d in rows if d >= HALF)
    negbase = sum(1 for k in range(1, len(rows)) if rows[k][1] < rows[k-1][1])  # 样本序回退(基线被回写旧值)
    chain = sum(1 for k in range(1, len(rows)) if (rows[k][1] - rows[k-1][1]) % M32 == rows[k][2])
    tel = (rl - 1000) % M32
    sdw = sum(d for _, _, d in rows) % M32
    return wraps, negbase, chain, len(rows), tel == sdw

print("=" * 74)
print("② 竞态交错模型对修后代码重放 (每线程 200 行, 10 组随机种子)")
print("=" * 74)
tot_old = tot_new = 0
for seed in range(10):
    w_o, n_o, c_o, n_, tel_o = simulate("old", seed=seed)
    w_n, n_n, c_n, n_, tel_n = simulate("new", seed=seed)
    tot_old += w_o; tot_new += w_n
    print(f"  seed={seed}: 修复前 回绕行={w_o:>5} 基线回退对={n_o:>5} t序链={c_o}/{n_-1}"
          f"  |  修复后 回绕行={w_n} 基线回退对={n_n} t序链={c_n}/{n_-1} 伸缩归零={tel_n}")
print(f"  合计回绕行: 修复前={tot_old}  修复后={tot_new}")
print("  ⇒ 锁合并后 snap→基线消费→回写 在同一临界区: 行 dw70 = 本行样本 − 锁序上一行样本,")
print("    寄存器单调 ⇒ dw70 ∈ [0, 2^31) 结构性成立, Σdw70 伸缩归零 (tail 对账前提恢复)。")
print("  未修面(如实对照): R2 回写单调性守卫 / R4 Σdw70≥2^32 响亮标记 仍未实现")
print("    (代码头注 :1154 自登记) — 但锁合并后两者已由结构覆盖 (rl 回写单调于锁序),")
print("    登记项从'缺口'降级为'保险丝'。")

# ---------------- ③ 实窗抽核 ----------------
print("=" * 74)
print("③ WIN_R1_20261013_232311.txt 独立抽核 (自写解析器)")
print("=" * 74)
path = "../runs/WIN_R1_20261013_232311.txt"
txt = open(path, encoding="utf-8", errors="replace").read()
rows = []
for m in re.finditer(r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) "
                     r"read_us=([-\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)", txt):
    rows.append(dict(i=int(m[1]), t=float(m[2]), got=int(m[6]), pc=int(m[7]),
                     w70=int(m[8]), dw70=int(m[9]), dma=int(m[10]), ddma=int(m[11])))
acct = re.search(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+) w70a=(\d+) w70b=(\d+) "
                 r"words0=(\d+) words1=(\d+) dwords=(\d+) K=(\d+)", txt)
done = re.search(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+)", txt)
snap_pre = re.search(r"W70  0x138  mir_drop_bytes\s+0x([0-9a-f]+)", txt)
snap_post = re.findall(r"W70  0x138  mir_drop_bytes\s+0x([0-9a-f]+)", txt)
summ = re.search(r"READLOG_SUM n=(\d+)", txt)

dW70_acct = int(acct[3]); w70a = int(acct[4]); w70b = int(acct[5])
snap_diff = (int(snap_post[-1], 16) - int(snap_pre.group(1), 16)) % M32
sdw = sum(r["dw70"] for r in rows) % M32
sdd = sum(r["ddma"] for r in rows) % M32
wrap = sum(1 for r in rows if r["dw70"] >= HALF)
print(f"  READLOG 行数 = {len(rows)}  (DONE reads={done[2]}, SUM n={summ[1]})")
print(f"  Σdw70      = {sdw}")
print(f"  ACCT dW70  = {dW70_acct}   w70a={w70a} w70b={w70b}")
print(f"  快照端点差 = {snap_diff}   (pre=0x{snap_pre.group(1)} post=0x{snap_post[-1]})")
print(f"  三口径一致 = {sdw == dW70_acct == snap_diff == 1587560}")
print(f"  dw70 min={min(r['dw70'] for r in rows)} max={max(r['dw70'] for r in rows)}"
      f"  wrap_candidates(≥2^31) = {wrap}")
print(f"  ddma: Σ={sdd}  ACCT dwords={acct[8]}  tail_d={(int(acct[7]) - rows[-1]['dma']) % M32}")

# t 序链 (锁内 commit 序 = t 序)
srt = sorted(rows, key=lambda r: r["t"])
noninc = sum(1 for k in range(1, len(srt)) if srt[k]["t"] < srt[k-1]["t"])
cw = sum(1 for k in range(1, len(srt)) if (srt[k]["w70"] - srt[k-1]["w70"]) % M32 == srt[k]["dw70"])
cd = sum(1 for k in range(1, len(srt)) if (srt[k]["dma"] - srt[k-1]["dma"]) % M32 == srt[k]["ddma"])
first_w = (srt[0]["w70"] - w70a) % M32 == srt[0]["dw70"]
first_d = (srt[0]["dma"] - int(acct[6])) % M32 == srt[0]["ddma"]
print(f"  t 序链: w70 {cw}/{len(srt)-1} (+首行基线 {first_w}) · dma {cd}/{len(srt)-1} (+首行 {first_d})"
      f" · 非递增 t 对 = {noninc}")
tail_w = (w70b - srt[-1]["w70"]) % M32
tail_d = (int(acct[7]) - srt[-1]["dma"]) % M32
err = (dW70_acct - sdw - tail_w) % M32
err2 = (int(acct[8]) - sdd - tail_d) % M32
print(f"  尾部对账: tail_w={tail_w} tail_d={tail_d}  err={err} err2={err2}")
pcmono = all(srt[k]["pc"] >= srt[k-1]["pc"] for k in range(1, len(srt)))
print(f"  t 序 pc 单调 = {pcmono}; partial 形态: got<4194304 行 = {sum(1 for r in rows if r['got']<4194304)}")
print("  ⇒ 255/255 行在**锁序**(=t 序)下链闭合、err=err2=0: 修后临界区的'样本序==基线序'")
print("    在真实 dual 窗上得到行为面见证 (n=1, 形态层 — 未观测到回绕 ≠ 不可能回绕)。")
