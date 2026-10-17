#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""`P7B_BIZ_WINDOW.md` 同步到 **76 字 / BID 0x2A / 未实现 0x160** (任务 C 点名)。
补两代: P9 E12 (W71..W74, 75 字) + p9 孤儿修复 (W75, 76 字); 顺带补记 W70 (M1, 该表停在 W69)。
默认 dry-run; `--apply` 才写。"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
DOC = os.path.normpath(os.path.join(HERE, "..", "..", "P7B_BIZ_WINDOW.md"))


def rep(s, a, b, tag):
    assert s.count(a) == 1, "anchor[%s] hits=%d" % (tag, s.count(a))
    return s.replace(a, b)


def main():
    s = io.open(DOC, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    s = s.replace("\r\n", "\n")

    # 1) 顶部更新块 (插在 2026-10-10 块之前)
    anchor = "> ### ⭐ **2026-10-10 更新（P7B 构建 F）：现役窗口 = 70 字**\n"
    block = (
        "> ### ⭐ **2026-10-17 更新（p9 孤儿修复）：现役窗口 = 76 字 / BID 0x2A**\n"
        "> **W75 = `app_ctrl.stat_orphan`**（孤儿会话/槽回收提交数；加在 **MSB 端**，旧字逐项未动），\n"
        "> `BUILD_ID_V 0x28 → 0x2A`，**未实现地址 `0x15C` → `0x160`**（word 88）。\n"
        "> ⚠️ 同批补记两代（本表此前停在 W69 / 构建 F）：**W70 = `app_rx_mirror.drop_bytes`**（M1，71 字）·\n"
        "> **W71..W74 = P9 E12 四观测计数器**（0x28，75 字）· **0x29 拆刀**（75 字 / BID 0x29；=\n"
        "> 0x28 内容 + `PERSIST_EN=0`，非功能代）。施工与证据 = `_proj_10g/notes/p9_build_0x2A_20261017/`。\n\n")
    s = rep(s, anchor, block + anchor, "top")

    # 2) §1 标题
    s = rep(s,
        "## 1. 现役槽位表（**完整**；地址 = `0x20 + 4*W`；61 字 = BIZ 轮，**63 字 = WU 轮现役**）",
        "## 1. 现役槽位表（**完整**；地址 = `0x20 + 4*W`；**现役 = 76 字 / BID 0x2A / 未实现 0x160**；"
        "61 字 = BIZ 轮，63 字 = WU 轮为历史代）", "hdr")

    # 3) 表尾补 W70..W75
    w69 = ("| **W69** | `0x134` | dp[29] | `tcp_tx_frame.o_win_at_winstall` | dp_clk | ⭐ **构建 F**："
           "最近一次等窗拍的 `{win_inflight, win_wnd_eff}` 锁存（⚠️ **仅 `ΔW66 > 0` 时有效**） |\n")
    rows = ("| **W70** | `0x138` | dp[30] | `app_rx_mirror.drop_bytes` | dp_clk | **M1 (0x1F)**：载荷镜像拒收字节数 |\n"
            "| **W71** | `0x13C` | dp[31] | `app_pattern.stat_up_ev` | dp_clk | **P9 E12 (0x28)**：app 实收 `ev_up` 事件数 |\n"
            "| **W72** | `0x140` | dp[32] | `app_pattern.stat_sw_req` | dp_clk | **P9 E12 (0x28)**：换流收尾请求数（`ev_same_act`） |\n"
            "| **W73** | `0x144` | dp[33] | `app_pattern.stat_sw_apply` | dp_clk | **P9 E12 (0x28)**：换流应用数（`sw_apply`） |\n"
            "| **W74** | `0x148` | dp[34] | `app_pattern.stat_up_pend` | dp_clk | **P9 E12 (0x28)**：A3 异槽登记数（`ev_other_act`） |\n"
            "| **W75** | `0x14C` | dp[35] | `app_ctrl.stat_orphan` | dp_clk | ⭐ **p9 孤儿修复 (0x2A)**：孤儿会话/槽回收提交数 |\n")
    s = rep(s, w69, w69 + rows, "rows")

    # 4) 未实现地址
    s = rep(s,
        "- **未实现地址 = `0x138`**（= `0x20 + 4*70`，word 78；**构建 F 现役**）⇒ 读回 `0xffffffff`（SLVERR 负对照）。\n"
        "  ⚠️ 逐代回溯: `0x12C`（67 字/构建 E）· `0x128`（66 字/构建 D）· `0x124`（65 字/构建 C）· `0x11C`（63 字/WU 轮）·\n"
        "  `0x114`（61 字/BIZ 轮）· `0xEC`（51 字/RATE 轮）—— **旧值现在全是窗口内的真字**（读它们得真数据, 不是 SLVERR）。\n",
        "- **未实现地址 = `0x160`**（= `0x20 + 4*76 + 16`，word 88；**p9 孤儿修复 0x2A 现役**）⇒ 读回 `0xffffffff`（SLVERR 负对照）。\n"
        "  ⚠️ 逐代回溯: `0x15C`（75 字/P9 E12 0x28；**0x29 同几何**）· `0x14C`（71 字/M1）· `0x138`（70 字/构建 F）·\n"
        "  `0x12C`（67 字/构建 E）· `0x128`（66 字/构建 D）· `0x124`（65 字/构建 C）· `0x11C`（63 字/WU 轮）·\n"
        "  `0x114`（61 字/BIZ 轮）· `0xEC`（51 字/RATE 轮）—— **旧值现在全是窗口内的真字**（读它们得真数据, 不是 SLVERR）。\n"
        "  ⚠️ M1 起公式 = `0x20 + 4*NW + 16`（快照末字后接 MIR_STATUS/DATA/CTRL/DMA_CNT 四字）。\n", "unimpl")

    out = s.replace("\n", nl)
    if "--apply" in sys.argv:
        io.open(DOC, "w", encoding="utf-8", newline="").write(out)
        print("APPLIED %s (%d -> %d bytes)" % (DOC, len(s.encode("utf-8")), len(out.encode("utf-8"))))
    else:
        print("DRY-RUN OK (would write %s)" % DOC)
    return 0


if __name__ == "__main__":
    sys.exit(main())
