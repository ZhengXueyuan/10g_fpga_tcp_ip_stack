#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mk_mut_swc.py -- 从现役 rtl/app_pattern.v 生成 P9 换流门 (TX_SWCLOSE) 的负对照变异件。

   输出到 sim/p9_swc_gate/mut/*.v (由 run_tb_p9_swc.bat 消费)。
   形状/纪律照 sim/p7b_longsend/mk_mut_cont.py (参照件):
     · 全成或全不落 (all-or-nothing): 逐锚点核命中数, 任一不符 => 不落盘任何件 +
       删掉本清单里的同名旧件 (PURGED); 落盘前后各核一次源文件 sha256 未变。
     · 命中数一律在【未修改的源文本】上计; 多行锚点用 \\n + 读入即 CRLF 归一化。

   变异集 (设计件 v2 §4.3-2 / v2r3 §2):
     M6   = 把 E4/E5/E6 回退成 **v1 字面方程** (sw_now 加 !closing 门槛 + 登记被
            !(SWC_OK && sw_ev) 堵死 + up_slot 不加 SWC 分支)
            => "v1-型洞" (H-1 的两个静默丢弃) 复现。
            ⚠️ 实测红集 = **全部臂** (v1 方程连"空闲到达的会话起点"一起丢, 见轮报告);
               设计件写的 "u_swc3/u_swc4 必红" 是它的子集。
     M6B  = **超出设计件的补充对照 (登记)**: 只把 `ev_same_act` 加上 `!closing`
            => 单独隔离"during-closing 事件被丢"这一条 (u_swc3/u_swc3b 红, 其余绿)。
     M7   = 把 E13 的守卫回退成 v2r2 版 (`sw_pend` 而不是 `closing`)
            => u_swc5h (R3-1 交接序列) 必红。

   `--dry-run` (或 `--check`): 只匹配 + 打印逐锚点命中表, 0 字节写盘。
   退出码: 0 = 全部锚点命中数 == 声明值; 1 = 有差异。
"""
import hashlib
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "rtl", "app_pattern.v")
OUT = os.path.join(HERE, "mut")

MUTS = []   # (name, [(old, new, hits)], note)


def add(name, subs, note):
    MUTS.append((name, subs, note))


# ---- M6: E4/E5/E6 回退成 v1 字面方程 (H-1 型洞) ----
M6_A_OLD = """    wire        up_ev   = ev_up || up_pend_r || (SWC_OK && sw_pend);
    wire [3:0]  up_slot = ev_up ? ev_slot :
                          (SWC_OK ? (up_pend_r ? up_pend_id : sw_slot) : up_pend_id);
    wire        same_slot = (up_slot == act_id);
    wire        idle_now  = !active;
    wire        up_ok   = idle_now || (same_slot && (frm_wait || (seg_sent == 12'd0)));  // 原名/原式保留
    wire        up_do   = up_ev && up_ok;                                                // 仅供 SWC_OK=0
    wire        sw_apply = SWC_OK ? (idle_now && up_ev) : up_do;                         // I1/I2
"""
M6_A_NEW = """    wire        up_ev   = ev_up || up_pend_r;                          // M6: v1 字面
    wire [3:0]  up_slot = ev_up ? ev_slot : up_pend_id;                // M6: v1 字面
    wire        same_slot = (up_slot == act_id);
    wire        idle_now  = !active;
    wire        up_ok   = idle_now || (same_slot && (frm_wait || (seg_sent == 12'd0)));
    wire        up_do   = up_ev && up_ok;
    wire        sw_ev    = up_ev && same_slot;                          // M6: v1 字面
    wire        sw_now   = SWC_OK && sw_ev && active && !closing && !sw_pend;  // M6: v1 字面 (+!closing)
    wire        sw_apply = SWC_OK ? (sw_pend && !active) : up_do;       // M6: v1 字面
    wire        up_acc   = SWC_OK ? sw_now : up_do;                     // M6: v1 字面
"""
M6_B_OLD = """            if (SWC_OK) begin
                if (sw_apply) begin sw_pend <= 1'b0; up_pend_r <= 1'b0; end
                else if (ev_same_act)  begin sw_pend <= 1'b1; sw_slot <= ev_slot; up_pend_r <= 1'b0; end
                else if (ev_other_act) begin up_pend_r <= 1'b1; up_pend_id <= ev_slot; sw_pend <= 1'b0; end
            end else begin
"""
M6_B_NEW = """            if (SWC_OK) begin
                if (sw_apply) sw_pend <= 1'b0;                          // M6: v1 字面
                else if (sw_now) begin sw_pend <= 1'b1; sw_slot <= up_slot; end   // M6: v1 字面
            end else begin
"""
M6_C_OLD = """            if (up_do) up_pend_r <= 1'b0;
            else if (ev_up) begin
                up_pend_r  <= 1'b1;
                up_pend_id <= ev_slot;
            end
            end
"""
M6_C_NEW = """            end
            if (up_acc) up_pend_r <= 1'b0;                              // M6: v1 字面
            else if (ev_up && !(SWC_OK && sw_ev)) begin                 // M6: v1 字面 (登记被堵死)
                up_pend_r  <= 1'b1;
                up_pend_id <= ev_slot;
            end
"""

add("m6_v1_eq", [
    (M6_A_OLD, M6_A_NEW, 1),
    (M6_B_OLD, M6_B_NEW, 1),
    (M6_C_OLD, M6_C_NEW, 1),
], "M6 E4/E5/E6 -> v1 字面方程 (H-1 两个静默丢弃洞; 期望红 = 全部臂)")

# ---- M6B: 只加 !closing (隔离 during-closing 洞; 超出设计件的补充对照) ----
add("m6b_closing_drop", [(
    "    wire        ev_same_act  = ev_up && same_slot && !idle_now;   // 同槽 + 存活 (含 closing)",
    "    wire        ev_same_act  = ev_up && same_slot && !idle_now && !closing;  // M6B: closing 态丢弃",
    1)], "M6B closing 态事件被丢 (期望红 = {u_swc3, u_swc3b})")

# ---- M7: E13 守卫回退成 v2r2 的 sw_pend 版 ----
add("m7_guard_swpend", [(
    # ⚠️ R5 裁决 A: 现役守卫文本 = `closing || !active` (锚点随改; 逐条见报告 §R5 锚点表)
    "            if (frm_wait && tx_ok && !(SWC_OK && (closing || !active))) begin",
    "            if (frm_wait && tx_ok && !(SWC_OK && (sw_pend || sw_apply))) begin   // M7: v2r2 版守卫",
    1)], "M7 E13 守卫 -> sw_pend 版 (R5 后咬点 = u_swcwing 闲置翼臂; 见报告 §R5 变更表)")


def norm(s):
    """换行归一化: \\r\\n / 单独 \\r 一律成 \\n (幂等)."""
    return s.replace("\r\n", "\n").replace("\r", "\n")


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def plan(src_lf):
    out = []
    for name, subs, note in MUTS:
        out.append((name, subs, note, [src_lf.count(norm(old)) for old, _, _ in subs]))
    return out


def render(src_lf, subs):
    t = src_lf
    for old, new, _ in subs:
        t = t.replace(norm(old), norm(new))
    return t


def purge(results):
    for name, _, _, _ in results:
        p = os.path.join(OUT, name + ".v")
        if os.path.exists(p):
            os.remove(p)
            print("PURGED %s" % p)


def main(argv):
    dry = ("--dry-run" in argv) or ("--check" in argv)
    raw_bytes = open(SRC, "rb").read()
    src = norm(io.open(SRC, encoding="utf-8", newline="").read())
    ref = sha256_bytes(raw_bytes)
    n_crlf = raw_bytes.count(b"\r\n")
    n_cr = raw_bytes.count(b"\r") - n_crlf
    print("SRC %s  %d B  sha256 %s" % (SRC, len(raw_bytes), ref))
    if n_crlf or n_cr:
        print("NORM: %d CRLF / %d lone CR -> LF" % (n_crlf, n_cr))

    results = plan(src)
    fails = []
    for name, subs, note, hits in results:
        want = [e for _, _, e in subs]
        if hits != want:
            for i, (h, e) in enumerate(zip(hits, want), 1):
                if h != e:
                    print("MUTFAIL %s: pattern hits=%d expect=%d" % (name, h, e))
            fails.append(name)

    if dry:
        print("%-18s %-4s %s" % ("mutant", "sub", "hits/expect"))
        for name, subs, note, hits in results:
            for i, ((_, _, e), h) in enumerate(zip(subs, hits), 1):
                print("%-18s s%-3d %d/%d %s" % (name, i, h, e, "" if h == e else "<== MISMATCH"))
            print("%-18s %s" % ("", "USABLE" if hits == [e for _, _, e in subs] else "BROKEN"))
        print("DRYRUN %s (0 bytes written)" % ("OK" if not fails else "FAIL %d" % len(fails)))
        return 0 if not fails else 1

    if fails:
        print("MUTGEN FAIL %d" % len(fails))
        purge(results)
        return 1

    now = sha256_bytes(open(SRC, "rb").read())
    if now != ref:
        print("SRC-CHANGED during generation: %s -> %s" % (ref, now))
        print("MUTGEN FAIL 1")
        purge(results)
        return 1

    texts = [(name, note, render(src, subs)) for name, subs, note, _ in results]
    os.makedirs(OUT, exist_ok=True)
    for name, note, text in texts:
        io.open(os.path.join(OUT, name + ".v"), "w", encoding="utf-8", newline="").write(text)
        print("WROTE %-22s %s" % (name, note))

    now = sha256_bytes(open(SRC, "rb").read())
    if now != ref:
        print("SRC-CHANGED after write: %s -> %s" % (ref, now))
        print("MUTGEN FAIL 1")
        purge(results)
        return 1

    n_subs = sum(len(subs) for _, subs, _, _ in results)
    print("ANCHORS: all %d mutants matched (%d subs, each hits==expect)" % (len(results), n_subs))
    print("MUTGEN OK (%d mutants)" % len(MUTS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
