#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""0x28 构建轮 ①: `board/wrapper_p4.v` BID bump 0x27 -> 0x28 (+ 注释块插新块 / 旧块降级逐字保留)。
⛔ 二进制安全: 按文件自身行尾 (CRLF) 处理; 只做**一处**连续替换 (单 hunk)。
⛔ 幂等: 已 bump 过 => 直接退出。
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
P = os.path.join(REPO, "board", "wrapper_p4.v")

s = io.open(P, encoding="utf-8", newline="").read()
if "32'h00000028" in s:
    print("ALREADY BUMPED (0x28 已在文件里) => 不动")
    sys.exit(0)

OLD = (
    "        .BUILD_ID_V (32'h00000027),     // ⚠️ 每次改动自增 (前置闸读这一项认位流; 换流门 R5 = 0x27)\r\n"
    "                                        //   ⭐ 本轮构建 (2026-10-15): **0x26 → 0x27** = 换流门 R5"
)

NEW = (
    "        .BUILD_ID_V (32'h00000028),     // ⚠️ 每次改动自增 (前置闸读这一项认位流; E12 观测计数器 = 0x28)\r\n"
    "                                        //   ⭐ 本轮构建 (2026-10-15): **0x27 → 0x28** = **E12 观测计数器**\n"
    "                                        //      (换流门四计数器: `stat_up_ev` / `stat_sw_req` /\n"
    "                                        //       `stat_sw_apply` / `stat_up_pend` —— `rtl/app_pattern.v`\n"
    "                                        //       **+48/−1**: 4 个出端口 + **1 个 async-reset 计数块**\n"
    "                                        //       (整块在 `SWC_OK` 常量门里 = 默认关时折叠)+\n"
    "                                        //       三态恒等式注释 (`ev_up` 恰落进 {当拍应用,\n"
    "                                        //       `ev_same_act`, `ev_other_act`} 之一)。\n"
    "                                        //       依据 = `_proj_10g/notes/p9_impl_e12_20261015/REPORT.md`\n"
    "                                        //       (SWC 门 8 运行全 RC=0 — 新增 34 条 E12 判据\n"
    "                                        //       + OFF 折叠正控; p6e 全链 148/0 与 counters 26/0;\n"
    "                                        //       本代窗口静态核对 96/0; 96/96 dump 逐字节退化重申)。\n"
    "                                        //      ⚠️ 用途 = \"触发条件本身\"研究的关键仪器 + K0 判据\n"
    "                                        //       \"负对照未现形\"的破题件 (**纯观测**: 4×32 FF + 常量门)。\n"
    "                                        //      ⛔ 几何**变** (M1 以来首例): **71 → 75 字**\n"
    "                                        //       (`SNAP_P7BDP_NW` 31 → 35; 四计数器占 p7bdp\n"
    "                                        //        槽 31..34, 装配 **MSB 端 +4 项** = W71..W74;\n"
    "                                        //        快照预算复算注释同批订正) ⇒ 未实现地址\n"
    "                                        //       **0x14C → 0x15C** (word 87) ⇒ 读侧**不止**\n"
    "                                        //       `EXPECT_BID` **0x27 → 0x28** (阶段 ⑬ = 24 处 / 14 文件):\n"
    "                                        //       还有 **NW 默认值 71 → 75** (`SNAP_WORDS=` / `NW=` /\n"
    "                                        //       `SW=` / `NW_FIX` / `awk -v NW=` / 指纹 bat) +\n"
    "                                        //       **标签表补 W71..W74** (`WLABEL` / `NAME[]` /\n"
    "                                        //       假板 `FAKE_TAIL` / `V=` / `W=[…]` /\n"
    "                                        //       `check_window.py` 的 `nnew_top 5→9`)。\n"
    "                                        //      ⚠️ 位流身份仍只由 sha256 + BID 分版 (全代 15,431,261 B)。\n"
    "                                        //   ---- (以下为历史, 逐字保留) ----\n"
    "                                        //   ⭐ 上一轮 (2026-10-15): **0x26 → 0x27** = 换流门 R5"
)

n = s.count(OLD)
assert n == 1, "锚点命中 %d (期望 1)" % n
s = s.replace(OLD, NEW)
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("BID BUMP DONE: 0x27 -> 0x28 (单 hunk; 新块 %d 行)" % (NEW.count("\n") + 1 - 4))
print("新 sha256 见下一步")
