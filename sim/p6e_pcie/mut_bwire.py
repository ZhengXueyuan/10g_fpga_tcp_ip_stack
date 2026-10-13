#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
mut_bwire.py -- M1 **期 B** 的"该红时红"突变件生成器 (给 run_tb_p6e_pcie_mut2.bat 用)

做什么: 把 board/wrapper_p4.v 里**C2H 数据通路的数据线**一行改掉 ——
        `.dma_data (mir_dma_data),` -> `.dma_data (64'd0),`
        落到 sim/p6e_pcie/mut/wrapper_p4_mut_bwire.v。

为什么这么改 (与 mut_srcinv.py 的差别): srcinv 是**期 A** 的突变 (它的红来自期 A 的
        M1-10* 判据) —— 它**不覆盖期 B 的接线**。本突变只动期 B 的一根数据线: 链路照常收到
        "grant/写脉冲"(**计数器照涨** ⇒ M1-B-1/3a 仍过), 但**送出的数据恒 0** ⇒ 只该由
        **内容对账**那几条判据 (M1-B-2e / M1-B-3d; P9 起 = P9-B-* 内容判据) 翻红。
        这就是"期 B 的新判据有自己的牙"的证明 (若全绿 ⇒ 内容判据是空判据)。

⛔ 锚点重对 (2026-10-13, 构建轮 0x24): 原锚 = `u_mir` 的 `mir_dma_ring` 例化里的
   `.src_data (mir_dma_data),` —— 该例化**在 `173b18d` (P9 XDMA MM→AXIS 落地) 被整体删除**
   (环被 AXIS 成形器取代), 自那以后本生成器 hits=0 ⇒ **mut2 门结构性空转**
   (症状 = `MUT-BWIRE-GENFAIL`, 且**不会**被读成"门通过")。新锚 = AXIS 架构下同一语义的那根线:
   成形器的 **`.dma_data (mir_dma_data)`** (来自 `u_mir_buf.dn_data`) ⇒ 突变语义**不变**
   (计数器照涨 / 数据恒 0)。

纪律 (全局 #90-#94 精神, 同 mut_srcinv.py):
  · **恰好 1 处命中**才算成功 (打印 new_hits 供 bat 判); 只做一次替换;
  · 不改仓库里的任何源文件 (只读 wrapper, 只写 mut/ 下)。

用法: python mut_bwire.py [--repo <repo>]      (退出码 0 = 已生成且 hits==1)
"""
from __future__ import print_function
import io, os, sys, argparse

# ⚠️ 锚点**不带换行** —— wrapper_p4.v 是 CRLF 行尾 (带 \n 的锚点会 0 命中; 实测踩过),
#    而带 \r\n 的锚点又会让本脚本自身行尾敏感 ⇒ 只锚行内容。
OLD = "        .dma_data       (mir_dma_data),       // ← 64 位 = {后出, 先出} (缓冲 FWFT 头字)"
NEW = "        .dma_data       (64'd0),              // MUT(bwire v2): c2h stream data pinned 0"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    a = ap.parse_args()
    src = os.path.join(a.repo, "board", "wrapper_p4.v")
    dst_dir = os.path.join(a.repo, "sim", "p6e_pcie", "mut")
    dst = os.path.join(dst_dir, "wrapper_p4_mut_bwire.v")
    text = io.open(src, encoding="utf-8", newline="").read()
    hits = text.count(OLD)
    print("MUT_BWIRE anchor_hits = %d" % hits)
    if hits != 1:
        print("MUT_BWIRE FAIL: anchor must hit exactly 1 line (got %d)" % hits)
        return 2
    out = text.replace(OLD, NEW)
    if out.count(NEW) != 1:
        print("MUT_BWIRE FAIL: replacement count != 1")
        return 2
    if not os.path.isdir(dst_dir):
        os.makedirs(dst_dir)
    with io.open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(out)
    print("MUT_BWIRE WROTE %s (bytes=%d)" % (dst, len(out)))
    print("MUT_BWIRE_OK")
    return 0

if __name__ == "__main__":
    sys.exit(main())
