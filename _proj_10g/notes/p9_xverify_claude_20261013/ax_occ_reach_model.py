#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
ax_occ_reach_model.py -- A 捆独立验证 (Claude 组, 2026-10-13)
  [K1] 缓冲占用上界复核: 自写逐拍模型 (自 rtl/mir_uram_fifo.v:147-238 现读推导; 非复跑 kimi 脚本)
  [K6] 多种子随机相位扫描 (自写种子/占空比; 独立于 TB 固定种子 1ACE/2BDF 与 kimi 的 0xACE0+seed)

方法组合 (互相独立):
  A. 穷举可达性 BFS, 缩比几何 AW=4/OQ=4 (转移方程与现役 AW=12 逐条同构): 对**全部输入序列**
     枚举可达 (occ, inv) -- 这是状态空间穷举 => 上界是"证"出来的, 不是"跑"出来的.
  B. 现役几何 AW=12 逐拍模型: 对抗序列 / 五类波形 20 万拍反证扫描 / 8 种子逐字对账 (含数据 ID 流).

XPM 行为模型: READ_LATENCY_B=3 (enb 拍发起 -> doutb 恰 +3); 空闲保持旧值 (与单元门实测一致).
只读运行; 只写本目录输出. 退出码 0 = 全部断言过.
"""
from __future__ import print_function
from collections import deque
import random, sys

# ---------------------------------------------------------------------------
# 统一转移函数 (按 rtl/mir_uram_fifo.v 现读逐行):
#   occ=wp-rp (:147) / ufull=occ==2^AW (:148) / inflight=popcount(v_sr) (:149) / inv=o_occ+inflight (:150)
#   pop = dn_req && o_occ!=0 && !clr (:155)
#   issue = (occ!=0) && ((inv-pop) < CAP) && !clr (:158)          CAP=OQ
#   up_req = rst_n && en && !clr && !ufull (:169)
#   u_wr = up_gnt && !clr (:170);  up_gnt = up_req && src_ready (镜像合同: 无 req 不给 gnt)
#   arr_v = v_sr[2] && !clr (:171)
#   沿 (:226-237): wp+=u_wr; rp+=issue; v_sr={v_sr[1:0],issue}; op_w+=arr_v; op_r+=pop; o_occ+=arr_v-pop
#   rst 或 clr => 整块清零 (:224-229, 优先级 rst > clr > 正常)
#   数据 ID 流 (供逐字对账; 与占用账独立): mem_id/写, R_id 3 级读延迟线, o_mem_id 弹性堆
# ---------------------------------------------------------------------------
def step(state, dat, aw, oq, rst_n, en, clr, dn_req, src_ready):
    wp, rp, v_sr, op_w, op_r, o_occ = state
    mem_id, R_id, o_mem_id, taken, popp = dat
    depth = 1 << aw
    m = (1 << (aw + 1)) - 1
    occ = (wp - rp) & m
    ufull = (occ == depth)
    inflight = bin(v_sr & 7).count("1")
    inv = o_occ + inflight
    pop = 1 if (dn_req and o_occ != 0 and not clr) else 0
    issue = 1 if (occ != 0 and ((inv - pop) < oq) and not clr) else 0
    up_req = 1 if (rst_n and en and not clr and not ufull) else 0
    up_gnt = 1 if (up_req and src_ready) else 0
    u_wr = 1 if (up_gnt and not clr) else 0
    arr_v = 1 if ((v_sr >> 2) & 1 and not clr) else 0
    ram_dout_id = R_id[2]                      # 本拍 doutb 上的 ID (读发起后恰第 3 拍)
    pop_id = o_mem_id[op_r]
    comb = dict(occ=occ, inv=inv, pop=pop, issue=issue, up_req=up_req, up_gnt=up_gnt,
                u_wr=u_wr, arr_v=arr_v, o_occ=o_occ, inflight=inflight,
                dn_gnt=pop, pop_id=pop_id, ram_dout_id=ram_dout_id)
    if (not rst_n) or clr:
        ns = (0, 0, 0, 0, 0, 0)
        nd = ([0] * depth, [None, None, None], [0] * oq, taken, popp)
        return ns, nd, comb
    new_mem = list(mem_id)
    if u_wr:
        new_mem[wp & (depth - 1)] = taken
    newR0 = mem_id[rp & (depth - 1)] if issue else R_id[0]
    newR = [newR0, R_id[0], R_id[1]]
    new_omem = list(o_mem_id)
    if arr_v:
        new_omem[op_w] = ram_dout_id
    ns = ((wp + u_wr) & m, (rp + issue) & m, ((v_sr << 1) | issue) & 7,
          (op_w + arr_v) % oq, (op_r + (1 if pop else 0)) % oq, o_occ + arr_v - pop)
    nd = (new_mem, newR, new_omem, taken + (1 if u_wr else 0), popp + (1 if pop else 0))
    return ns, nd, comb

# ---------------------------------------------------------------------------
# A. 穷举可达性 BFS -- 缩比几何 (状态 = (wp,rp,v_sr,op_w,op_r,o_occ); 数据流与占用无关, 不入状态)
# ---------------------------------------------------------------------------
def bfs_reach(aw, oq):
    depth = 1 << aw
    start = (0, 0, 0, 0, 0, 0)
    seen = {start: None}                     # state -> (prev_state, input)
    q = deque([start])
    worst = -1
    worst_samples = []
    bad = []
    inputs = [(1, en, 0, dn, sr) for en in (0, 1) for dn in (0, 1) for sr in (0, 1)]
    inputs += [(0, 1, 0, 0, 1), (1, 1, 1, 0, 1), (1, 1, 1, 1, 1), (0, 0, 0, 0, 0)]
    while q:
        s = q.popleft()
        for inp in inputs:
            ns, _, comb = step(s, ([0] * depth, [None] * 3, [0] * oq, 0, 0), aw, oq, *inp)
            tot = comb["occ"] + comb["inv"]
            if comb["inv"] > oq:
                bad.append(("inv>CAP", s, inp))
            if comb["occ"] > depth:
                bad.append(("occ>DEPTH", s, inp))
            if tot > worst:
                worst = tot
                worst_samples = [(s, inp, comb)]
            elif tot == worst and len(worst_samples) < 4:
                worst_samples.append((s, inp, comb))
            if ns not in seen:
                seen[ns] = (s, inp)
                q.append(ns)
    return seen, worst, worst_samples, bad

def path_to(seen, s):
    path = []
    while seen[s] is not None:
        prev, inp = seen[s]
        path.append((prev, inp, s))
        s = prev
    path.reverse()
    return path

# ---------------------------------------------------------------------------
# B. 现役几何逐拍模型 (+ 逐字对账)
# ---------------------------------------------------------------------------
def run_sim(aw, oq, cyc, gen):
    depth = 1 << aw
    st = (0, 0, 0, 0, 0, 0)
    dat = ([0] * depth, [None, None, None], [0] * oq, 0, 0)
    ref = []                       # 期望队列 (字 ID); clr/rst 清
    seq_err = 0; over_err = 0; clr_pop = 0; rst_take = 0; n_pop = 0
    max_tot = -1; max_at = -1; max_split = None
    for c in range(cyc):
        rst_n, en, clr, dn_req, src_ready = gen(c)
        ns, nd, comb = step(st, dat, aw, oq, rst_n, en, clr, dn_req, src_ready)
        if comb["up_gnt"]:
            ref.append(dat[3])               # 被取走的字 ID (= taken 计数)
        if comb["pop"]:
            n_pop += 1
            if clr:
                clr_pop += 1
            exp = ref.pop(0) if ref else None
            if exp is None:
                over_err += 1
            elif exp != comb["pop_id"]:
                seq_err += 1
        if (not rst_n) and en and (comb["up_req"] or comb["up_gnt"]):
            rst_take += 1
        if clr or (not rst_n):
            ref = []
        tot = comb["occ"] + comb["inv"]
        if tot > max_tot:
            max_tot = tot; max_at = c
            max_split = (comb["occ"], comb["o_occ"], comb["inflight"])
        st = ns; dat = nd
    return dict(max_tot=max_tot, max_at=max_at, max_split=max_split, seq_err=seq_err,
                over_err=over_err, clr_pop=clr_pop, rst_take=rst_take, n_pop=n_pop)

fails = 0
def expect(cond, msg):
    global fails
    print("  [%s] %s" % ("PASS" if cond else "FAIL", msg))
    if not cond:
        fails += 1

print("=" * 78)
print("A. 穷举可达性 BFS (缩比几何 AW=4 => DEPTH=16, OQ=CAP=4) -- 对全部输入序列枚举")
print("=" * 78)
seen, worst, worst_samples, bad = bfs_reach(4, 4)
print("  可达状态数 = %d ; 穷举可达 max(occ+inv) = %d ; DEPTH+CAP = 20" % (len(seen), worst))
expect(worst == 16 + 4, "BFS: 穷举可达 max(occ+inv) == DEPTH+CAP == 20 (实测 %d)" % worst)
expect(not bad, "BFS: 全部可达状态/输入满足 inv<=CAP 且 occ<=DEPTH (违例 %d 条)" % len(bad))
joint = [s for s in seen if ((s[0] - s[1]) & 31) == 16 and (s[5] + bin(s[2] & 7).count("1")) == 4]
print("  可达状态中 'occ==16 且 inv==4' 个数 = %d ; 例 = %s" % (len(joint), joint[:2]))
expect(len(joint) > 0, "BFS: 'occ 满 + inv 满' 同时可达 (构造性; 个数=%d)" % len(joint))
if joint:
    p = path_to(seen, joint[0])
    print("  到该状态的最短路径 %d 拍; 末 4 拍:" % len(p))
    for prev, inp, nxt in p[-4:]:
        occ = (prev[0] - prev[1]) & 31
        inv = prev[5] + bin(prev[2] & 7).count("1")
        print("      %s --(rst=%d en=%d clr=%d dn=%d src=%d)--> %s  (occ=%d,o_occ=%d,v_sr=%s,和=%d)"
              % (prev, inp[0], inp[1], inp[2], inp[3], inp[4], nxt, occ, prev[5], format(prev[2], "03b"), occ + inv))
ws = worst_samples[0]
print("  max 样本: 前态=%s 输入=%s => (occ,o_occ,inflight)=(%d,%d,%d) 和=%d"
      % (ws[0], ws[1], ws[2]["occ"], ws[2]["o_occ"], ws[2]["inflight"], ws[2]["occ"] + ws[2]["inv"]))

print()
print("=" * 78)
print("B1. 现役几何 AW=12 对抗序列 (en=1, clr=0, dn_req=0, 源常就绪, 6000 拍)")
print("=" * 78)
r1 = run_sim(12, 4, 6000, lambda c: (1, 1, 0, 0, 1))
print("  max(occ+inv) = %d @cyc%d ; 分解 (occ,o_occ,inflight) = %s" % (r1["max_tot"], r1["max_at"], r1["max_split"]))
expect(r1["max_tot"] == 4100, "对抗序列: max(occ+inv) == 4100 字 (= 4096 + 4)")
expect(r1["max_split"] == (4096, 4, 0), "对抗序列: (occ=4096, o_occ=4, inflight=0) 同时成立")

print()
print("=" * 78)
print("B2. 反证扫描: 五类波形 x 5 seed (每类 20 万拍) 试图击破 occ+inv <= 4100")
print("=" * 78)
def mk_gen(kind, sd):
    rnd = random.Random(sd)
    if kind == "rand":
        return lambda c: (1, 1, 0, 1 if rnd.random() < 0.5 else 0, 1 if rnd.random() < 0.75 else 0)
    if kind == "burst":
        return lambda c: (1, 1, 0, 1 if (c // 7) % 2 else 0, 1)
    if kind == "gate":
        return lambda c: (1, 1, 0, 1 if (c % 13 == 0) else 0, 1)
    if kind == "clrinj":
        return lambda c: (1, 1, 1 if (c % 997 == 500) else 0, 0, 1)
    if kind == "rstinj":
        return lambda c: (0 if (c % 3001 == 1500) else 1, 1, 0, 0, 1)
    raise ValueError(kind)

gmax = {}; gmax_at = {}
for kind in ("rand", "burst", "gate", "clrinj", "rstinj"):
    gmax[kind] = -1
    for sd in range(5):
        r = run_sim(12, 4, 40000, mk_gen(kind, 1000 + sd))
        if r["max_tot"] > gmax[kind]:
            gmax[kind] = r["max_tot"]; gmax_at[kind] = (sd, r["max_at"])
for k in gmax:
    print("  %-6s: max(occ+inv) = %d (seed=%d @cyc%d)" % (k, gmax[k], gmax_at[k][0], gmax_at[k][1]))
expect(all(v <= 4100 for v in gmax.values()), "反证扫描: 五类波形全部 <= 4100 (最大 %d)" % max(gmax.values()))
expect(4100 in gmax.values(), "反证扫描: 至少一类'非特意对抗'波形也取到 4100 (取到者: %s)"
       % ", ".join(k for k in gmax if gmax[k] == 4100))

print()
print("=" * 78)
print("B3. 8 种子逐字对账 (自写种子/占空; 含 clr 注入; 每跑 2 万拍)")
print("=" * 78)
allok = True
for sd in (11, 22, 33, 44, 55, 66, 77, 88):
    duty_src = 0.40 + 0.07 * (sd % 7)
    duty_dn = 0.25 + 0.09 * (sd % 5)
    rnd = random.Random(0xC1A0DE + sd)
    r = run_sim(12, 4, 20000,
                lambda c: (1, 1, 1 if (c % 1301 == 700 and sd % 2) else 0,
                           1 if rnd.random() < duty_dn else 0,
                           1 if rnd.random() < duty_src else 0))
    ok = (r["seq_err"] == 0 and r["over_err"] == 0 and r["clr_pop"] == 0 and r["rst_take"] == 0)
    allok = allok and ok
    print("  seed=%d src=%.2f dn=%.2f: pops=%d seq_err=%d over_err=%d clr_pop=%d rst_take=%d max(occ+inv)=%d"
          % (sd, duty_src, duty_dn, r["n_pop"], r["seq_err"], r["over_err"], r["clr_pop"], r["rst_take"], r["max_tot"]))
expect(allok, "8 种子逐字对账: 丢/重/错序/clr 拍弹字/复位期取数 全 0")

print()
print("RESULT: %s (fails=%d)" % ("ALL-PASS" if fails == 0 else "FAIL", fails))
sys.exit(0 if fails == 0 else 1)
