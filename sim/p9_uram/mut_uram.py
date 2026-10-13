#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
mut_uram.py -- URAM 板内缓冲 (rtl/mir_uram_fifo.v) 的"该红时红"突变件生成器

从 rtl/mir_uram_fifo.v 生成**单点行为突变** (每个都改"头注释不变式里的一条");
每个 pattern **恰好 1 处命中**才算成功 (打印命中数供门判); 只读 rtl/, 只写 sim/p9_uram/mut/。

  mut_full_off  : up_req 去掉 !ufull                     满态还取数 ⇒ 覆盖未读字 (静默丢字)
  mut_full_e1   : UFULL 常量 -1                          容量少 1 ⇒ "恰好满 = 4096" 结构性锚该红
  mut_issue_free: issue 去掉 (inv-pop < CAP) 上限         停收时到达覆盖弹性堆 (静默丢字)
  mut_val1      : arr_v 取 v_sr[1] 而不是 v_sr[2]         到达早一拍 ⇒ 数据错拍/丢字
  mut_clr_off   : clr 分支封死                            窗口边界不丢弃 ⇒ 旧字漏进新窗口
  mut_clr_take  : up_req 去掉 !clr                        clr 拍取数 ⇒ "已取走既不计也不交付"
  mut_dnreq     : dn_gnt = dn_req                         无数据也成交 (幻影弹; 成形器拿到垃圾)
  --- 2026-10-13 复核轮 F2/F3/F4 补臂 (与新增 TB 场景成对; 每条都要能被对应判据抓红) ---
  mut_rstn_off  : up_req 去掉 rst_n (重开 F2 洞)          复位期取数 ⇒ GR1/G9g 该红
  mut_en_off    : up_req 去掉 en                          停排空还取数 ⇒ G6a 该红
  mut_dnclr     : pop 去掉 !clr (重开 F3 洞)              clr 拍弹旧头字 ⇒ GC1/G9f 该红
  mut_wp_nmc    : wp 增量丢掉绕回位 (AW 位写窄)           帧容量锚/长流账该红 (G2a/G8)
  mut_guard_off : 删守卫③ 的 $display                     仅供 rogue 臂对照 (arm mut_guard_off
                                                          与 guard_rogue 配成"守卫有牙"的一对)
  --- 2026-10-13 FIX 轮 (验证 A-K5) 补 3 臂: 补上"clr 分支内部"与"64 位数据面"两类零覆盖 ---
  mut_clrv      : clr 分支删 `v_sr <= 3'd0;` (部分清)    旧 valid 链不清 ⇒ 旧字漏进新窗口 (G5/
                                                          G5b/GC 家族与 G9 账该红)
  mut_omem      : dn_data 读错槽 (op_r -> op_w)           弹性堆 FWFT 读出臂 (o_occ∈1..3 时读错槽
                                                          ⇒ G1b/G4b/… 逐字对账该红)
  mut_oocc      : o_occ 更新丢 `+ arr_v` 项               占用账不记到达 ⇒ 弹发饿死 (G7/G2f 家族该红)

用法: python mut_uram.py --arm mut_full_off|... [--repo R]
"""
from __future__ import print_function
import io, os, sys, argparse

# ⚠️ 锚点必须与**当前** rtl/mir_uram_fifo.v 逐字一致 (2026-10-13 复核轮: `up_req` 行已并入
#    `rst_n`、`pop` 行已并入 `!clr` ⇒ 三条旧锚同步改写, 失配时本工具硬失败 MUT-URAM-GENFAIL)。
UP_REQ_LINE = "    assign      up_req   = rst_n && en && !clr && !ufull;\n"

MUTS = {
    "mut_full_off": [
        (UP_REQ_LINE,
         "    assign      up_req   = rst_n && en && !clr;   // MUT(mut_full_off): no full gate\n", 1),
    ],
    "mut_full_e1": [
        ("    localparam [AW:0] UFULL= {1'b1, {AW{1'b0}}};      // occ 满值 = 2^AW\n",
         "    localparam [AW:0] UFULL= {1'b1, {AW{1'b0}}} - {{AW{1'b0}}, 1'b1};   // MUT(mut_full_e1)\n", 1),
    ],
    "mut_issue_free": [
        ("    wire        issue    = (occ != {(AW+1){1'b0}}) && ((inv - {3'd0, pop}) < CAP) && !clr;\n",
         "    wire        issue    = (occ != {(AW+1){1'b0}}) && !clr;   // MUT(mut_issue_free)\n", 1),
    ],
    "mut_val1": [
        ("    wire        arr_v    = v_sr[2] && !clr;                           // 本拍 ram_dout 上是有效字\n",
         "    wire        arr_v    = v_sr[1] && !clr;   // MUT(mut_val1): arrive one cycle early\n", 1),
    ],
    "mut_clr_off": [
        ("        end else if (clr) begin\n",
         "        end else if (1'b0) begin   // MUT(mut_clr_off): clr no longer clears\n", 1),
    ],
    "mut_clr_take": [
        (UP_REQ_LINE,
         "    assign      up_req   = rst_n && en && !ufull;   // MUT(mut_clr_take): take on clr cycle\n", 1),
    ],
    "mut_dnreq": [
        ("    assign      dn_gnt   = pop;\n",
         "    assign      dn_gnt   = dn_req;   // MUT(mut_dnreq): phantom grant (no data)\n", 1),
    ],
    # ---- F2: 复位期取数 (GR1 / G9g 该红) ----
    "mut_rstn_off": [
        (UP_REQ_LINE,
         "    assign      up_req   = en && !clr && !ufull;   // MUT(mut_rstn_off): no rst_n gate (F2 hole reopened)\n", 1),
    ],
    # ---- F4-1: en 项 (G6a 该红) ----
    "mut_en_off": [
        (UP_REQ_LINE,
         "    assign      up_req   = rst_n && !clr && !ufull;   // MUT(mut_en_off): no en term\n", 1),
    ],
    # ---- F3: clr 拍弹字 (GC1 / G9f 该红) ----
    "mut_dnclr": [
        ("    wire        pop      = dn_req && (o_occ != 3'd0) && !clr;\n",
         "    wire        pop      = dn_req && (o_occ != 3'd0);   // MUT(mut_dnclr): no clr gate on pop (F3 hole)\n", 1),
    ],
    # ---- F4-5: wp 计数器绕回位写窄 (G2a / G8 该红) ----
    "mut_wp_nmc": [
        ("            if (u_wr)  wp <= wp + {{AW{1'b0}}, 1'b1};\n",
         "            if (u_wr)  wp <= {1'b0, wp[AW-1:0] + {{(AW-1){1'b0}}, 1'b1}};   // MUT(mut_wp_nmc): wrap bit dropped\n", 1),
    ],
    # ---- F4-3: 守卫有牙的一对 (arm guard_rogue 期望串在 / mut_guard_off 期望串不在) ----
    "mut_guard_off": [
        ("            if (up_gnt && !up_req)\n"
         "                $display(\"FATAL mir_uram_fifo: upstream grant without req (violates aux contract, t=%0t)\", $time);\n",
         "            if (up_gnt && !up_req)\n"
         "                ;   // MUT(mut_guard_off): guard display removed (rogue arm must go blind)\n", 1),
    ],
    # =================================================================================
    # 2026-10-13 FIX 轮补臂 (验证 A-K5): 原 12 臂全落在"写门/读门/计数器/clr 总开关/守卫"七类
    #   控制点上 —— **clr 分支内部单行**与**64 位数据面**两类零覆盖。以下 3 臂补齐这两类。
    #   每臂 = 单点、锚点必须与现行 rtl/mir_uram_fifo.v 逐字一致 (hits != 1 ⇒ GENFAIL)。
    # =================================================================================
    # ---- A-K5-①: clr 分支"部分清" (删 v_sr 清链一行; wp/rp 仍清) ----
    #   后果预期 (验证 §5 推演): clr 后旧 valid 链持续对齐 ⇒ 旧 ram_dout 被 arr_v 采入弹性堆
    #   ⇒ 旧窗口的字弹进新窗口 ⇒ over_err/seq_err ⇒ G5/G5b/GC 家族 + G9e 账该红。
    "mut_clrv": [
        ("        end else if (clr) begin\n"
         "            wp <= {(AW+1){1'b0}};  rp <= {(AW+1){1'b0}};  v_sr <= 3'd0;\n",
         "        end else if (clr) begin\n"
         "            wp <= {(AW+1){1'b0}};  rp <= {(AW+1){1'b0}};   // MUT(mut_clrv): v_sr NOT cleared (clr partial-clear)\n", 1),
    ],
    # ---- A-K5-②: 弹性堆 FWFT 读出臂 (dn_data 读错槽: op_r -> op_w) ----
    #   o_occ∈1..3 时 op_w ≠ op_r ⇒ 读到非头字 (o_occ==0/4 时 op_w≡op_r, 不暴露) ⇒ 逐字对账该红。
    "mut_omem": [
        ("    assign      dn_data  = o_mem[op_r];\n",
         "    assign      dn_data  = o_mem[op_w];   // MUT(mut_omem): wrong FWFT slot (op_r -> op_w)\n", 1),
    ],
    # ---- A-K5-③: o_occ 更新丢 `+ arr_v` (占用账不记到达) ----
    #   o_occ 永不自增 ⇒ pop 恒 0 ⇒ 下游弹发饿死 (逐字对账/吞吐/账目家族该红)。
    "mut_oocc": [
        ("            o_occ <= o_occ + {2'd0, arr_v} - {2'd0, pop};\n",
         "            o_occ <= o_occ - {2'd0, pop};   // MUT(mut_oocc): +arr_v term dropped\n", 1),
    ],
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", required=True, choices=sorted(MUTS.keys()))
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    a = ap.parse_args()
    src = os.path.join(a.repo, "rtl", "mir_uram_fifo.v")
    dst_dir = os.path.join(a.repo, "sim", "p9_uram", "mut")
    dst = os.path.join(dst_dir, "mir_uram_fifo_%s.v" % a.arm)
    text = io.open(src, encoding="utf-8", newline="").read()
    total = 0
    for old, new, want in MUTS[a.arm]:
        hits = text.count(old)
        print("MUT_URAM pattern hits = %d (want %d)" % (hits, want))
        if hits != want:
            print("MUT_URAM FAIL: anchor hits != want")
            return 2
        text = text.replace(old, new)
        total += hits
    print("MUT_URAM total_replacements = %d" % total)
    if not os.path.isdir(dst_dir):
        os.makedirs(dst_dir)
    with io.open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("MUT_URAM WROTE %s" % dst)
    print("MUT_URAM_OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
