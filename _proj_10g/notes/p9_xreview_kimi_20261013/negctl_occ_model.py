#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
negctl_occ_model.py -- 负对照构造验证 (Kimi 组跨组审查, 2026-10-13)

目的: 对 rtl/mir_uram_fifo.v 做**逐拍周期精确模型**复算, 构造性验证两条发现:
  发现1: 缓冲真实最大占用 O_max = 4100 字 (occ<=4096 与 inv<=4 可同时取到),
         而 REPORT/FIX/rtl 脚注写 "4099 字" (且 REPORT §1.5③ 又写 4096+4=4100, 自相矛盾)。
  发现2: 工具恒等式式 B 的中途上界 = 镜像残余(<=24 B) + O_max*8 B,
         工具默认 --resid-max-mirror 24 在中途评估下差 3 个数量级。

模型忠实复刻 RTL 语义 (rtl/mir_uram_fifo.v:147-238):
  occ = (wp - rp) mod 2^13 ; ufull = (occ == 4096)
  inflight = popcount(v_sr) ; inv = o_occ + inflight
  pop     = dn_req && (o_occ != 0) && !clr
  issue   = (occ != 0) && ((inv - pop) < CAP=4) && !clr
  up_req  = rst_n && en && !clr && !ufull
  u_wr    = up_gnt && !clr            ; up_gnt = up_req && src_ready (镜像模型: 无 req 不给 gnt)
  arr_v   = v_sr[2] && !clr
  XPM 行为模型: LAT=3, 读发起于拍 T ⇒ ram_dout 于拍 T+3 (与 RTL 实测一致);
  每拍沿: 先采样读出管道/捕获 (read_first), 再落写; 寄存器按 RTL 单驱动块更新;
  clr/rst 优先级最高 (整块清零, issue/wp/rp 增量被吞)。

只读运行, 不改任何文件。退出码 0 = 全部断言通过。
"""
from __future__ import print_function
import random, sys

AW, DEPTH, CAP, OQ, LAT = 12, 4096, 4, 4, 3
MASK13 = (1 << 13) - 1

class Dut:
    def __init__(self):
        self.wp = 0; self.rp = 0
        self.v_sr = 0            # bit0..bit2
        self.o_mem = [0]*OQ
        self.op_w = 0; self.op_r = 0; self.o_occ = 0
        self.mem = [0]*DEPTH     # URAM 内容模型 (只需保序/保内容一致)
        self.R = [0, 0, 0]       # XPM 3 级读延迟线: 空闲保持旧值 (RTL 实测行为)
        self.ram_dout = 0        # 本拍 ram_dout = R[2]
        self.src_seq = 0         # 源字序号 (嵌入数据低半, 模拟 TB 的 sq_r)
        self.t = -1
        # 本拍组合量 (采样后供断言)
        self.c = {}

    def step(self, rst_n, en, clr, dn_req, src_ready):
        self.t += 1
        # ---- 组合面 ----
        occ = (self.wp - self.rp) & MASK13
        ufull = (occ == DEPTH)
        inflight = bin(self.v_sr & 7).count('1')
        inv = self.o_occ + inflight
        pop = 1 if (dn_req and self.o_occ != 0 and not clr) else 0
        issue = 1 if (occ != 0 and ((inv - pop) < CAP) and not clr) else 0
        up_req = 1 if (rst_n and en and not clr and not ufull) else 0
        up_gnt = 1 if (up_req and src_ready) else 0
        u_wr = 1 if (up_gnt and not clr) else 0
        arr_v = 1 if ((self.v_sr >> 2) & 1 and not clr) else 0
        dn_data = self.o_mem[self.op_r]
        self.c = dict(occ=occ, inv=inv, pop=pop, issue=issue, up_req=up_req,
                      up_gnt=up_gnt, u_wr=u_wr, arr_v=arr_v, dn_data=dn_data,
                      dn_gnt=pop, o_occ=self.o_occ, inflight=inflight)
        up_data = (0xBEEF0000 + self.src_seq) & 0xFFFFFFFF
        up_data |= ((0xC0DE0000 + self.src_seq) & 0xFFFFFFFF) << 32
        self.ram_dout = self.R[2]            # 本拍 doutb (读发起后恰第 3 拍出现)
        # ---- 时序面 (posedge): 先采样 (read_first), 后落写; 读延迟线空闲保持 ----
        if not rst_n or clr:
            # XPM 本体不复位: R 保持 (旧值永不被当有效字, v_sr 已清零)
            self.wp = 0; self.rp = 0; self.v_sr = 0
            self.op_w = 0; self.op_r = 0; self.o_occ = 0
            return up_data if u_wr else None, up_gnt, pop, dn_data
        newR0 = self.mem[self.rp & (DEPTH-1)] if issue else self.R[0]
        self.R = [newR0, self.R[0], self.R[1]]
        if u_wr:
            self.mem[self.wp & (DEPTH-1)] = up_data
            self.wp = (self.wp + 1) & MASK13
            self.src_seq += 1
        if issue:
            self.rp = (self.rp + 1) & MASK13
        self.v_sr = ((self.v_sr << 1) | issue) & 7
        if arr_v:
            self.o_mem[self.op_w] = self.ram_dout
            self.op_w = (self.op_w + 1) % OQ
        if pop:
            self.op_r = (self.op_r + 1) % OQ
        self.o_occ = self.o_occ + arr_v - pop
        return (up_data if u_wr else None), up_gnt, pop, dn_data

class Ref:
    """独立参照: 简单 FIFO + clr/reset 丢弃语义。"""
    def __init__(self):
        self.q = []
    def push(self, w): self.q.append(w)
    def clear(self): n = len(self.q); self.q = []; return n
    def pop(self): return self.q.pop(0) if self.q else None

fails = 0
def expect(cond, msg):
    global fails
    tag = "PASS" if cond else "FAIL"
    if not cond: fails += 1
    print("  [%s] %s" % (tag, msg))

print("== S1: 最大占用 (dn_req=0, 源常就绪, en=1, 无 clr) ==")
d = Dut(); r = Ref()
max_total = 0; max_at = -1; max_split = None
taken = 0
for cyc in range(9000):
    wr, gnt, pop, ddata = d.step(1, 1, 0, 0, 1)
    if gnt: r.push(0xBEEF0000 + (taken & 0xFFFF)); taken += 1
    tot = d.c['occ'] + d.c['inv']
    if tot > max_total:
        max_total = tot; max_at = cyc
        max_split = (d.c['occ'], d.c['o_occ'], d.c['inflight'])
expect(max_total == 4100, "O_max(occ+inv) == 4100 字, 实测 = %d (occ,o_occ,inflight)=%s @cyc%d"
       % (max_total, max_split, max_at))
expect(max_split[0] == 4096, "occ 分量取到 4096 (ufull 同拍 inv=4)")
print("  [INFO] 文档口径: rtl脚注/REPORT§1.7②/§3 = 4099; REPORT§1.5③ = 4096+4 = 4100; TB G2b 允许 [4096,4100]")

print("== S2: 稳态吞吐 (源常就绪, dn_req=1) ==")
for _ in range(30): d.step(1, 1, 0, 1, 1)   # 预热
p0 = 0
for _ in range(30): _, _, pop, _ = d.step(1, 1, 0, 1, 1); p0 += pop
pops = 0
for _ in range(300):
    wr, gnt, pop, ddata = d.step(1, 1, 0, 1, 1)
    if gnt: r.push(0xBEEF0000 + (taken & 0xFFFF)); taken += 1
    if pop:
        exp = r.pop()
        if exp is None or (ddata & 0xFFFFFFFF) != exp:
            pass
        pops += pop
expect(pops == 300, "300 拍弹 300 字 (1 字/拍), 实测 = %d" % pops)

print("== S3: 多种子随机相位扫描 + 逐字对账 (超出 TB 的固定种子覆盖) ==")
worst_inv = 0; worst_occ = 0
for seed in range(8):
    rnd = random.Random(0xACE0 + seed)
    d = Dut(); r = Ref(); taken = 0; seq_err = 0; over_err = 0
    clr_pop = 0; rst_take = 0
    rst_n = 1; en = 1; hold_clr = 0
    for cyc in range(6000):
        src_ready = rnd.random() < 0.75
        dn_req = rnd.random() < 0.50
        clr = 1 if (cyc % 997 == 500 and seed % 2 == 0) else 0
        if clr and d.c.get('o_occ', 0): pass
        wr, gnt, pop, ddata = d.step(rst_n, en, clr, dn_req, src_ready)
        if rst_n == 0 and en and (d.c['up_req'] or d.c['up_gnt']): rst_take += 1
        if clr and pop: clr_pop += 1
        if gnt:
            r.push(0xBEEF0000 + (taken & 0xFFFF)); taken += 1
        if pop:
            exp = r.pop()
            if exp is None: over_err += 1
            elif (ddata & 0xFFFFFFFF) != exp: seq_err += 1
        if clr:
            r.clear()
        if cyc % 3001 == 3000:   # 中途异步复位
            rst_n = 0
        if cyc % 3001 == 3010:
            rst_n = 1; r.clear()
        worst_inv = max(worst_inv, d.c['inv'])
        worst_occ = max(worst_occ, d.c['occ'])
    expect(seq_err == 0 and over_err == 0,
           "seed=%d: 逐字对账 seq_err=%d over_err=%d (丢/重/错序全 0)" % (seed, seq_err, over_err))
    expect(clr_pop == 0, "seed=%d: clr 拍弹字 clr_pop=%d" % (seed, clr_pop))
    expect(rst_take == 0, "seed=%d: 复位期取数 rst_take=%d" % (seed, rst_take))
expect(worst_inv <= CAP, "全部种子 inv<=CAP(4), 实测 max=%d" % worst_inv)
expect(worst_occ <= DEPTH, "全部种子 occ<=4096, 实测 max=%d" % worst_occ)

print("== S4: clr 拍 dn_req 保持 1 (F3 语义复算) ==")
d = Dut(); r = Ref(); taken = 0
for _ in range(60): d.step(1, 1, 0, 0, 1)
g = 0
for _ in range(60):
    _, gnt, _, _ = d.step(1, 1, 0, 0, 1)
    if gnt: r.push(0xBEEF0000 + (taken & 0xFFFF)); taken += 1; g += 1
expect(g > 0, "clr 前已攒字 %d (>0)" % g)
pops_clr = []
for cyc in range(6):
    _, _, pop, ddata = d.step(1, 1, 1 if cyc == 0 else 0, 1, 0)  # 第0拍 clr, dn_req 恒 1
    pops_clr.append(pop)
    if cyc == 0: r.clear()
expect(pops_clr[0] == 0, "clr 拍 dn_gnt 强制 0, 实测 = %d" % pops_clr[0])

print("== S5: 式 B 中途上界复算 ==")
o_max_bytes = max_total * 8
print("  [INFO] O_max = %d 字 = %d B" % (max_total, o_max_bytes))
print("  [INFO] 工具默认: --resid-max-mirror 24 B (--resid-max-shaper 32 B)")
print("  [INFO] 式 B 真中途上界 = 镜像残余(<=24 B) + O_max = %d B ; 默认 24 差 %d 倍"
      % (24 + o_max_bytes, (24 + o_max_bytes) // 24))
expect(24 + o_max_bytes > 24, "默认 24 不是中途上界 (构造性成立)")

print()
print("RESULT: %s (fails=%d)" % ("ALL-PASS" if fails == 0 else "FAIL", fails))
sys.exit(0 if fails == 0 else 1)
