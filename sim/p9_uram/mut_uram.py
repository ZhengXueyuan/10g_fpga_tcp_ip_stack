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

用法: python mut_uram.py --arm mut_full_off|... [--repo R]
"""
from __future__ import print_function
import io, os, sys, argparse

MUTS = {
    "mut_full_off": [
        ("    assign      up_req   = en && !clr && !ufull;\n",
         "    assign      up_req   = en && !clr;   // MUT(mut_full_off): no full gate\n", 1),
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
        ("    assign      up_req   = en && !clr && !ufull;\n",
         "    assign      up_req   = en && !ufull;   // MUT(mut_clr_take): take on clr cycle\n", 1),
    ],
    "mut_dnreq": [
        ("    assign      dn_gnt   = pop;\n",
         "    assign      dn_gnt   = dn_req;   // MUT(mut_dnreq): phantom grant (no data)\n", 1),
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
