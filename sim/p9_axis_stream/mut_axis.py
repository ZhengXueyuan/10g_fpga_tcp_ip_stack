#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
mut_axis.py -- P9 的"该红时红"突变件生成器 (给 run_tb_axis_c2h_stream.bat 用)

从 rtl/axis_c2h_stream.v 生成**单点行为突变** (每个都改"合同里的一条");
锚点随 **D4 板级修正轮** (2026-10-11: clr=丢弃 / stop 不含 clr) 更新。

  --- 原有 7 臂 (锚点跟现源) ---
  mut_last  : mv_last = mv_full ? 1'b0 : 1'b1 -> 1'b0        (永不 tlast ⇒ 收尾拍标记消失;
              G4e/G4c-e/G7?=/G10c/G11b3/G11b-d/G12d 该红)
  mut_keep  : mv_keep 短末拍 16'h00FF          -> 16'hFF00    (末拍 keep 没挤 LSB; *-keep 该红)
  mut_order : mv_data = {s1_data, s0_data}     -> 反序        (拍内字序反; G1b 该红)
  mut_req   : dma_req = en && !clr_drop && 容量 -> en          (无容量也请求 ⇒ 覆盖丢字; G3c 该红)
  mut_cnt   : dma_words + 32'd2                -> + 32'd4     (计数口径错; G1e/G9a 该红)
  mut_clr   : dma_words 的 clr 归零分支封死                       (计数不清零; G7c 该红)
  mut_stop  : stop = (!cap_en) || (!en)        -> (!cap_en)   (en=0 不再算停流 ⇒ 该收尾的不收;
              G4 一族该红)
  --- ⭐ D4 修正轮新增 5 臂 (每件 = 恰 1 行, 对着新用例 G7/G7x/G11/G11b/G12 的牙) ---
  mut_drain : mv_go 半拍路径丢掉 `&& quiet`       -> 见 stop 就碎片化 (旧行为: 每 grant 一拍
              8 B tlast 包; G4a3 / G11a / G11b-a 该红)
  mut_tlast : mv_last 整拍分支 1'b0 -> stop        (停流排空期整拍也打 tlast; G5h / G11a3 /
              G11b-b 该红)
  mut_quiet : qcnt 的 +1 变 no-op                 (永不 quiet ⇒ 收尾拍永远不发; G4b / G11b 该红)
  mut_clrdrop: clr_drop = clr -> 1'b0             (⭐ clr 不再丢弃残拍 ⇒ 旧窗口尾巴漏进新窗口
              头部; G7c0 / G7d / G7g / G7x-c / G7x-f 该红 —— 板级抓到的那条缺陷形态)
  mut_qrst  : qcnt 的 grant 归零分支封死          (排空期 grant 不归零 ⇒ 中途误判"排空完成"
              ⇒ 长排空 (G11b) 中途多冒收尾拍; G11b-b / G11b-j 该红)

纪律 (同 mut_aximm.py): 每个 pattern **恰好 1 处命中**才算成功 (打印命中数供门判);
输出 = 产物 (每次重生成); 只读 rtl/, 只写 sim/p9_axis_stream/mut/。

用法: python mut_axis.py --arm mut_keep|... [--repo R]
"""
from __future__ import print_function
import io, os, sys, argparse

MUTS = {
    "mut_last": [
        ("assign mv_last  = mv_full ? 1'b0 : 1'b1;\n",
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
        ("assign dma_req  = en && !clr_drop && (!s0_v || !s1_v || mv_go);\n",
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
        ("assign stop = (!cap_en) || (!en);\n",
         "assign stop = (!cap_en);   // MUT(mut_stop): en=0 no longer a stop\n", 1),
    ],
    # ---- ⭐ D4 修正轮新增 (2026-10-11) ----
    "mut_drain": [
        ("assign mv_go    = b_free && (mv_full || (stg_half && stop && quiet));\n",
         "assign mv_go    = b_free && (mv_full || (stg_half && stop));   // MUT(mut_drain): fragment on stop\n", 1),
    ],
    "mut_tlast": [
        ("assign mv_last  = mv_full ? 1'b0 : 1'b1;\n",
         "assign mv_last  = mv_full ? stop : 1'b1;   // MUT(mut_tlast): full beats tlast during stop\n", 1),
    ],
    "mut_quiet": [
        ("else if (qcnt != QUIET_N) qcnt <= qcnt + 6'd1;\n",
         "else if (qcnt != QUIET_N) qcnt <= qcnt;   // MUT(mut_quiet): never quiet\n", 1),
    ],
    "mut_clrdrop": [
        ("wire clr_drop = clr;\n",
         "wire clr_drop = 1'b0;   // MUT(mut_clrdrop): clr no longer discards residue\n", 1),
    ],
    "mut_qrst": [
        ("else if (gnt_go)          qcnt <= 6'd0;\n",
         "else if (1'b0)            qcnt <= 6'd0;   // MUT(mut_qrst): grants do not reset quiet cnt\n", 1),
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
