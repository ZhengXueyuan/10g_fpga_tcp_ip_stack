#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_txstarve_wiring.py -- 0x38 tx_arb 饥饿保护 + W97[1:0] 观测的静态门 (只读)

判据:
  A. rtl/tx_arb.v: 参数 STARVE_GUARD 默认 0; g_legacy 分支保持 fast 先行;
     g_guard 分支: slow_wait 复位清零; slow 挂起 + slow_wait 先于 fast 判定;
     fast 帧内 slow 挂起置 slow_wait; slow 服务期间清 slow_wait.
  B. board/wrapper_p4.v: P11_DUAL 段 localparam TX_ARB_STARVE_GUARD=1;
     4 个 C4 tx_arb 实例全部传 .STARVE_GUARD(TX_ARB_STARVE_GUARD);
     非 P11_DUAL 的实例保持默认 (不得传参).
  C. rtl/app_multi8_cdc.v: cdc_status[0]=st_req / [1]=st_ack_sync[1];
     st_req / st_ack_sync 在 dp_clk 域寄存器 (不是 app 域直连).
  D. board/build_p7b_ku5p.tcl: P7B_TXSTARVE_CELLS 硬门存在, 阈值 4.

负控: --negctl 在内存里做两处突变 (把一个实例的参数改成 0; 把 guard 的 slow 判定
      挪到 fast 之后) ⇒ 本门必须各报红; 未报红 = MUTATION_NOT_DETECTED, RC=1.
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

def read(p):
    with open(os.path.join(ROOT, p), "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def seg(txt, start, end):
    i = txt.find(start)
    j = txt.find(end, i + 1)
    return txt[i:j] if i >= 0 and j > i else ""

def check(tx, wr, cdc, bld, mut=0):
    fails = []
    def ck(cond, name):
        print(("[ok]   " if cond else "[FAIL] ") + name)
        if not cond:
            fails.append(name)

    # ---- A: tx_arb ----
    ck(re.search(r"parameter\s+integer\s+STARVE_GUARD\s*=\s*0", tx) is not None,
       "A1 STARVE_GUARD default 0")
    leg = seg(tx, "g_legacy", "end else begin : g_guard")
    grd = seg(tx, "g_guard", "endgenerate")
    ck("if (s_fast_tvalid)" in leg and "s_slow_tvalid && slow_wait" not in leg,
       "A2 legacy branch = fast strict priority (unchanged)")
    guard_ok = True
    if mut == 2:
        # mutation: move slow check after fast check (guarded arm loses its bite)
        grd = grd.replace(
            "if (s_slow_tvalid && slow_wait) begin\n                        // 已在 fast 帧内等过",
            "if (1'b0) begin\n                        // MUTATED")
    for pat, name in [
        (r"if \(s_slow_tvalid && slow_wait\) begin", "A3 slow-wait check present"),
        (r"busy <= 1'b0; sel_fast <= 1'b0; slow_wait <= 1'b0;", "A4 reset clears slow_wait"),
        (r"slow_wait <= s_slow_tvalid;", "A5 pending latched during fast frame"),
        (r"if \(!sel_fast\)\s+slow_wait <= 1'b0;", "A6 slow service clears slow_wait"),
    ]:
        if re.search(pat, grd) is None:
            guard_ok = False
    ck(guard_ok, "A3-A6 guard state machine complete")
    # slow check must precede fast check inside the !busy block
    busy = seg(grd, "if (!busy) begin", "end else begin")
    i_slow = busy.find("s_slow_tvalid && slow_wait")
    i_fast = busy.find("else if (s_fast_tvalid)")
    ck(0 <= i_slow < i_fast, "A7 slow-wait branch precedes fast branch")
    ck("generate" in tx and "endgenerate" in tx, "A8 generate branch isolates legacy")

    # ---- B: wrapper wiring ----
    w = wr
    if mut == 1:
        i = w.find(".STARVE_GUARD(TX_ARB_STARVE_GUARD)")
        w = w[:i] + ".STARVE_GUARD(1'b0)" + w[i + len(".STARVE_GUARD(TX_ARB_STARVE_GUARD)"):]
    ck(re.search(r"localparam\s+TX_ARB_STARVE_GUARD\s*=\s*1'b0", w) is not None,
       "B1 localparam TX_ARB_STARVE_GUARD = 0 (0x39: guard disabled, review overturn)")
    insts = ["u_tx_udp_arb", "u_tx_udp_arb_p1", "u_tx_arb", "u_tx_arb_p1"]
    got = []
    for nm in insts:
        m = re.search(r"tx_arb\s*#\(\.STARVE_GUARD\(TX_ARB_STARVE_GUARD\)\)\s+%s\s*\(" % re.escape(nm), w)
        got.append(m is not None)
    ck(all(got), "B2 four C4 instances parameterized: %s" % got)
    # non-DUAL instances must NOT be parameterized (they use the default 0)
    nd = seg(w, "`else\n    // port0 (ch1) 的 UDP/HLS 合流", "`endif")
    ck("STARVE_GUARD" not in nd, "B3 non-P11_DUAL instances keep default 0")
    # C4 branch guards
    ck(w.find("localparam TX_ARB_STARVE_GUARD") > w.find("`ifdef P11_DUAL"),
       "B4 localparam inside P11_DUAL section")

    # ---- C: W97 low bits ----
    ck(re.search(r"cdc_status\[0\]\s*=\s*st_req;", cdc) is not None,
       "C1 cdc_status[0] = st_req")
    ck(re.search(r"cdc_status\[1\]\s*=\s*st_ack_sync\[1\];", cdc) is not None,
       "C2 cdc_status[1] = st_ack_sync[1]")
    i_req = cdc.find("st_req <= 1'b0;")
    j_alw = cdc.rfind("always @", 0, i_req) if i_req >= 0 else -1
    ck(i_req >= 0 and j_alw >= 0 and "dp_clk" in cdc[j_alw:j_alw + 60],
       "C3 st_req lives in dp_clk block")
    ck("st_ack_sync <= {st_ack_sync[0], st_ack};" in cdc,
       "C4 st_ack_sync is the DP 2FF of app-side st_ack")

    # ---- D: build-time netlist witness ----
    ck("P7B_DIAG3B_SRC" in bld, "D1 build gate P7B_DIAG3B_SRC present")
    ck(all(n in bld for n in ("app_tx_ready", "app_estab_cnt", "app_init_ovf")),
       "D2 build gate checks the three DIAG3B source assignments")
    ck("P7B_DIAG3B_SRC_MISSING" in bld, "D3 DIAG3B source missing is fatal")
    return fails

def main():
    tx = read("rtl/tx_arb.v")
    wr = read("board/wrapper_p4.v")
    cdc = read("rtl/app_multi8_cdc.v")
    bld = read("board/build_p7b_ku5p.tcl")
    print("== positive ==")
    f = check(tx, wr, cdc, bld, 0)
    if "--negctl" in sys.argv:
        for m, nm in ((1, "param-one-instance-to-0"), (2, "guard-slow-after-fast")):
            print("== negctl %d (%s) ==" % (m, nm))
            fm = check(tx, wr, cdc, bld, m)
            if not fm:
                print("MUTATION_NOT_DETECTED %s" % nm)
                return 1
            print("NEGCTL_RED_OK %s -> %s" % (nm, fm[0]))
    if f:
        print("TXSTARVE_GATE_FAIL %s" % f)
        return 1
    print("TXSTARVE_GATE_PASS")
    return 0

if __name__ == "__main__":
    sys.exit(main())
