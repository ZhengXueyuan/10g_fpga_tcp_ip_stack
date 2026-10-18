#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_edits_2d.py — 生成 P11 F-21 / 0x2D 读侧阶段的**显式增量** (EDITS_2D).

用法: python gen_edits_2d.py [--check]
  * 默认 = 落盘: 对 15 个读侧文件做 0x2C -> 0x2D 的 BID 行替换, 并打印可直接
    粘贴进 `apply_readside_bid1c.py` 的 EDITS_2D 条目。
  * --check = 只验证当前磁盘是否已处于 0x2D 态 (每条 old 命中 0 / new 命中 1)。

设计:
  * **只动 BID 行** (身份默认值 / 自述"现役"行 / GEOM_TIERS 新增一行);
    几何 (NW=88 / 未实现 0x190) 一律不动。
  * 历史注释**逐字保留** (0x2C 阶段的原文不动); 只改"现役代"自述 —— 这些行
    被 `apply_readside_bid1c.py` 的 DEFAULT_SPECS 断言, 属于**活判据**, 不是历史。
  * 完整的 old/new **整行** 写进 EDITS_2D (唯一命中; 行尾由 apply 脚本按文件现读
    的 CRLF/LF 适配) ⇒ 从 0x2C 树重放应逐字节得到本树。
"""
import argparse
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

# (rel, old, new) —— old 必须是 0x2C 树里的**唯一**子串; new = 0x2D 树。
E = [
    # ---- 1. step0_selfcheck.sh (两处"现役档"自述; DEFAULT_SPECS 断言) ----
    ("_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh",
     "#     (i)  缺省档 (NW=88 / 0x190 / BID 0x2C) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);",
     "#     (i)  缺省档 (NW=88 / 0x190 / BID 0x2D) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);"),
    ("_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh",
     'echo "### C-a) 默认档 (NW=88 / 0x190 / BID 0x2C) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x2C)"',
     'echo "### C-a) 默认档 (NW=88 / 0x190 / BID 0x2D) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x2D)"'),
    # ---- 2/3. j6 两个台架: EXPECT_BID + GEOM_TIERS 顶端新增一行 ----
    ("_proj_10g/notes/p7b_affinity/j6_r6fix.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}   # 2026-10-18 P11 P2-甲 双口+双 IP (88 字; 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 P11 F-21 修复 (88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)"),
    ("_proj_10g/notes/p7b_affinity/j6_r6fix.sh",
     '  "88|0x0000002C|61 62|P11 P2-甲 双口+双 IP (2026-10-18) 88 字 / BID 0x2C (双 SFP+ 数据面接入: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; **几何变**: 83 -> 88 字, 未实现地址 0x17C -> 0x190)"',
     '  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"\n'
     '  "88|0x0000002C|61 62|P11 P2-甲 双口+双 IP (2026-10-18) 88 字 / BID 0x2C (双 SFP+ 数据面接入: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; **几何变**: 83 -> 88 字, 未实现地址 0x17C -> 0x190)"'),
    ("_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}   # 2026-10-18 P11 P2-甲 双口+双 IP (88 字; 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 P11 F-21 修复 (88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)"),
    ("_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh",
     '  "88|0x0000002C|61 62|P11 P2-甲 双口+双 IP (2026-10-18) 88 字 / BID 0x2C (双 SFP+ 数据面接入: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; **几何变**: 83 -> 88 字, 未实现地址 0x17C -> 0x190)"',
     '  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"\n'
     '  "88|0x0000002C|61 62|P11 P2-甲 双口+双 IP (2026-10-18) 88 字 / BID 0x2C (双 SFP+ 数据面接入: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; **几何变**: 83 -> 88 字, 未实现地址 0x17C -> 0x190)"'),
    # ---- 4. tb_biz_win.v (参数 + 判据 1b) ----
    ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
     "    axi_regs #(.MAGIC_V(32'h50360001), .BUILD_ID_V(32'h0000002C), .SNAP_NW(NW)) u_dut (",
     "    axi_regs #(.MAGIC_V(32'h50360001), .BUILD_ID_V(32'h0000002D), .SNAP_NW(NW)) u_dut ("),
    ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
     '        axil_rd(32\'h04, v, resp); chk("1b BUILD_ID", v, 32\'h0000002C);',
     '        axil_rd(32\'h04, v, resp); chk("1b BUILD_ID", v, 32\'h0000002D);'),
    # ---- 5. final_state.sh ----
    ("_proj_10g/notes/p7b_gate4_3/final_state.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}   # ⛔ 2026-10-18 P11 P2-甲 双口+双 IP (88 字); 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}   # ⛔ 2026-10-18 P11 F-21 修复 (88 字); 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复"),
    # ---- 6. gen_inputs.py (几何自述 3 处 + BID_FIX) ----
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "         ⚠️ 几何 = **88 字 / BID 0x2C** (P11 P2-甲 双口+双 IP, 2026-10-18 同步轮从 83 字/BID 0x2B 同步)",
     "         ⚠️ 几何 = **88 字 / BID 0x2D** (P11 F-21 修复, 2026-10-18 同步轮从 0x2C 同步; 几何同 0x2C)"),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     '# 现应读作 "不同代 ⇒ 假红": 本夹具现 = **88 字 / BID 0x2C**, accept 默认也已是 88 字 / BID 0x2C',
     '# 现应读作 "不同代 ⇒ 假红": 本夹具现 = **88 字 / BID 0x2D**, accept 默认也已是 88 字 / BID 0x2D'),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "→ **88 字/0x2C (P11 P2-甲 双口+双 IP, 未实现地址 0x17C → 0x190)**。",
     "→ **88 字/0x2D (P11 F-21 修复, 几何同 0x2C, 未实现地址 0x190)**。"),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "BID_FIX = 0x0000002C       # 位流身份 (P11 P2-甲 双口+双 IP) —— ⛔ 2026-10-18: 原值 0x0000002B (P11 P1)",
     "BID_FIX = 0x0000002D       # 位流身份 (P11 F-21 修复) —— ⛔ 2026-10-18: 原值 0x2C (P2-甲未烧板) / 0x2B (P11 P1)"),
    # ---- 7/8. _proj_pcie 两个假板子 ----
    ("_proj_pcie/p6e_snap_check.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}       # ⛔ 2026-10-18 P11 P2-甲 双口+双 IP: 原默认 0x2B (P11 P1 ch0 bring-up) / 0x2A (p9 孤儿修复) / 0x29 (0x29 拆刀) / 0x28 (P9 E12) / 0x0A (Stage C)",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}       # ⛔ 2026-10-18 P11 F-21 修复: 原默认 0x2C (P2-甲未烧板) / 0x2B (P11 P1 ch0 bring-up) / 0x2A (p9 孤儿修复) / 0x29 (0x29 拆刀) / 0x28 (P9 E12) / 0x0A (Stage C)"),
    ("_proj_pcie/p6e_snap_selftest_fix2.sh",
     '  0X04) V=\\${FAKE_BID:-0x0000002C};;   # P11 P2-甲 双口+双 IP = 0x2C (⛔ 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x0A = Stage C);',
     '  0X04) V=\\${FAKE_BID:-0x0000002D};;   # P11 F-21 修复 = 0x2D (⛔ 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x0A = Stage C);'),
    # ---- 9. p7b_snap.sh (头部"现役" + EXPECT_BID + 一行逐代注记) ----
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     '# p7b_snap.sh -- 板侧快照窗口取数器 (**现役 = 88 字 / BID 0x2C**; 标题原文 = "板侧 **63** 字',
     '# p7b_snap.sh -- 板侧快照窗口取数器 (**现役 = 88 字 / BID 0x2D**; 标题原文 = "板侧 **63** 字'),
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}"),
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     "#      + 身份 0x2B → **0x2C**; 未实现地址 **0x17C → 0x190**。",
     "#      + 身份 0x2B → **0x2C**; 未实现地址 **0x17C → 0x190**。\n"
     "#   ⭐ F-21 (2026-10-18): 身份 0x2C → **0x2D** (W83..W87 改经 p7bdp CDC; 字长/未实现地址不变)。"),
    # ---- 10/11. _proj_pcie 验收/自检 ----
    ("_proj_pcie/p7b_gate4_accept.sh",
     "EXPECT_BID=${EXPECT_BID:-0x0000002C}      # P11 P2-甲 双口+双 IP = 0x2C (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12)",
     "EXPECT_BID=${EXPECT_BID:-0x0000002D}      # P11 F-21 修复 = 0x2D (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12)"),
    ("_proj_pcie/p7b_gate4_selftest.sh",
     "现役 = **0x2C** (P11 P2-甲 双口+双 IP 88 字; 原 0x2B = P11 P1 ch0 bring-up 83 字 ——",
     "现役 = **0x2D** (P11 F-21 修复 88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 ch0 bring-up 83 字 ——"),
    ("_proj_pcie/p7b_gate4_selftest.sh",
     "  0X04) V=\\${FAKE_BID:-0x0000002C};;",
     "  0X04) V=\\${FAKE_BID:-0x0000002D};;"),
    # ---- 12/13. negctrl + livefake ----
    ("_proj_pcie/p7b_gate4_negctrl.sh",
     "# 几何: **88 字 (W0..W87)** —— P11 P2-甲 双口+双 IP (2026-10-18, BID=0x2C / 未实现 0x190);",
     "# 几何: **88 字 (W0..W87)** —— P11 F-21 修复 (2026-10-18, BID=0x2D / 未实现 0x190);"),
    ("_proj_pcie/p7b_gate4_negctrl.sh",
     '    echo "MAGIC 0x50360001"; echo "BID 0x0000002C"; echo "MARKER 0xdeadbeef"   # P11 P2-甲 双口+双 IP: 原 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x27 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x25 = F-3 修复',
     '    echo "MAGIC 0x50360001"; echo "BID 0x0000002D"; echo "MARKER 0xdeadbeef"   # P11 F-21 修复: 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x27 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x25 = F-3 修复'),
    ("_proj_pcie/p7b_gate4_livefake.sh",
     '    bid = {88: "0x0000002C", 83: "0x0000002B", 76: "0x0000002A", 75: "0x00000029", 71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x0000002C")',
     '    bid = {88: "0x0000002D", 83: "0x0000002B", 76: "0x0000002A", 75: "0x00000029", 71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x0000002D")'),
    # ---- 14/15. p6e 两个 TB ----
    ("sim/p6e_pcie/tb_p6e_pcie_counters.v",
     '        u_dut.u_pcie_xdma.axil_read(32\'h04, v); chk("0b BUILD_ID (P11 P2-甲 88-word = 0x2C; 原 83-word=0x2B / 75-word=0x29 / 0x28 / 63-word=9)", v, 32\'h0000002C);',
     '        u_dut.u_pcie_xdma.axil_read(32\'h04, v); chk("0b BUILD_ID (P11 F-21 88-word = 0x2D; 原 0x2C / 83-word=0x2B / 75-word=0x29 / 0x28 / 63-word=9)", v, 32\'h0000002D);'),
    ("sim/p6e_pcie/tb_p6e_pcie_wrapper.v",
     '        u_dut.u_pcie_xdma.axil_read(32\'h04, v); chk("2  BUILD_ID (P11 P2-甲 双口+双 IP 构建 = 0x2C)", v, 32\'h0000002C);',
     '        u_dut.u_pcie_xdma.axil_read(32\'h04, v); chk("2  BUILD_ID (P11 F-21 修复 构建 = 0x2D)", v, 32\'h0000002D);'),
]


def rd(p):
    b = open(p, "rb").read()
    return b, ("\r\n" if b.count(b"\r\n") else "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    fails = 0
    by_file = {}
    for rel, old, new in E:
        p = os.path.join(REPO, rel.replace("/", os.sep))
        b, nl = rd(p)
        cur = b.decode("utf-8")
        old2 = old.replace("\n", nl)
        new2 = new.replace("\n", nl)
        k_old = cur.count(old2)
        k_new = cur.count(new2)
        if a.check:
            # 插入型 edit (GEOM_TIERS 新增行): new 里**逐字包含** old ⇒ old 仍命中 1 属预期
            # (全局 #91: 插入型编辑不能用"旧串必须消失"当判据; 用 new_hits >= 1)。
            insertion = old in new
            ok = (k_new >= 1) and (insertion or k_old == 0)
            print("%s %-54s old_hits=%d new_hits=%d%s"
                  % ("OK  " if ok else "FAIL", rel, k_old, k_new, " [insertion]" if insertion else ""))
            if not ok:
                fails += 1
            continue
        if k_old != 1:
            print("FAIL %-54s old_hits=%d (期望 1)" % (rel, k_old))
            fails += 1
            continue
        out = cur.replace(old2, new2)
        io.open(p, "w", encoding="utf-8", newline="").write(out)
        print("EDIT %-54s (old_hits=1)" % rel)
        by_file[rel] = by_file.get(rel, 0) + 1
    if a.check:
        print("CHECK_2D %s" % ("OK" if not fails else "FAIL fails=%d" % fails))
        return 1 if fails else 0
    print("\n# ---- EDITS_2D (generated; %d entries / %d files) ----" % (len(E), len(by_file)))
    for rel, old, new in E:
        print("EDITS_2D.append((%r,\n  %r,\n  %r, 1))" % (rel, old, new))
    print("EDIT_FILES %d: %s" % (len(by_file), ", ".join(sorted(by_file))))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
