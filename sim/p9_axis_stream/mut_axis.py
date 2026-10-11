#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
mut_axis.py -- P9 的"该红时红"突变件生成器 (给 run_tb_axis_c2h_stream.bat 用)

从 rtl/axis_c2h_stream.v 生成**单点行为突变** (每个都改"合同里的一条"):
  mut_last  : mv_last  = mv_full ? stop : 1'b1  -> 1'b0        (永不 tlast; G4e/G4c-e/G7g 该红)
  mut_keep  : mv_keep  = ... : 16'h00FF         -> 16'hFF00    (末拍 keep 没挤 LSB; G4d 该红)
  mut_order : mv_data  = {s1_data, s0_data}     -> 反序        (拍内字序反; G1b 该红)
  mut_req   : dma_req  = en && (容量)           -> en          (无容量也请求 ⇒ 覆盖丢字; G3c 该红)
  mut_cnt   : dma_words + 32'd2                 -> + 32'd4     (计数口径错; G1e/G9a 该红)
  mut_clr   : dma_words 的 clr 归零分支封死                       (计数不清零; G7c 该红)
  mut_stop  : stop = (!cap_en)||(!en)||clr      -> 去掉 clr     (clr 不 flush 残拍; G7d 该红)

纪律 (同 mut_aximm.py): 每个 pattern **恰好 1 处命中**才算成功 (打印命中数供门判);
输出 = 产物 (每次重生成); 只读 rtl/, 只写 sim/p9_axis_stream/mut/。

用法: python mut_axis.py --arm mut_keep|... [--repo R]
"""
from __future__ import print_function
import io, os, sys, argparse

MUTS = {
    "mut_last": [
        ("assign mv_last  = mv_full ? stop : 1'b1;\n",
         "assign mv_last  = 1'b0;   // MUT(mut_last): never tlast\n", 1),
    ],
    "mut_keep": [
        ("assign mv_keep  = mv_full ? 16'hFFFF : 16'h00FF;\n",
         "assign mv_keep  = mv_full ? 16'hFFFF : 16'hFF00;   // MUT(mut_keep)\n", 1),
    ],
    "mut_order": [
        ("assign mv_data  = mv_full ? {s1_data, s0_data} : {64'd0, s0_data};\n",
         "assign mv_data  = mv_full ? {s0_data, s1_data} : {64'd0, s0_data};   // MUT(mut_order)\n", 1),
    ],
    "mut_req": [
        ("assign dma_req  = en && (!s0_v || !s1_v || mv_go);\n",
         "assign dma_req  = en;   // MUT(mut_req): no capacity term\n", 1),
    ],
    "mut_cnt": [
        ("else if (gnt_go)     dma_words <= dma_words + 32'd2;\n",
         "else if (gnt_go)     dma_words <= dma_words + 32'd4;   // MUT(mut_cnt)\n", 1),
    ],
    "mut_clr": [
        ("else if (clr)        dma_words <= 32'd0;\n",
         "else if (1'b0)       dma_words <= 32'd0;   // MUT(mut_clr): never clear\n", 1),
    ],
    "mut_stop": [
        ("assign stop = (!cap_en) || (!en) || clr;\n",
         "assign stop = (!cap_en) || (!en);   // MUT(mut_stop): clr not in stop set\n", 1),
    ],
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm", required=True, choices=sorted(MUTS.keys()))
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    a = ap.parse_args()
    src = os.path.join(a.repo, "rtl", "axis_c2h_stream.v")
    dst_dir = os.path.join(a.repo, "sim", "p9_axis_stream", "mut")
    dst = os.path.join(dst_dir, "axis_c2h_stream_%s.v" % a.arm)
    text = io.open(src, encoding="utf-8", newline="").read()
    total = 0
    for old, new, want in MUTS[a.arm]:
        hits = text.count(old)
        print("MUT_AXIS pattern hits = %d (want %d)" % (hits, want))
        if hits != want:
            print("MUT_AXIS FAIL: anchor hits != want")
            return 2
        text = text.replace(old, new)
        total += hits
    print("MUT_AXIS total_replacements = %d" % total)
    if not os.path.isdir(dst_dir):
        os.makedirs(dst_dir)
    with io.open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("MUT_AXIS WROTE %s" % dst)
    print("MUT_AXIS_OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
