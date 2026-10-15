#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 ⑬ (0x27 -> 0x28, P9 **E12 观测计数器**) 的 EDITS_28 生成器。

两种来源:
  A. **BID 面 24 处 / 14 文件** —— 照抄 p9_build_0x27/gen_edits27.py 的做法: 取 `EDITS_27` 的
     **new 侧** (= 盘上现状) 当 ⑬ 的 old 侧; new 侧 = old 侧经**逐条显式变换** (值 0x27 -> 0x28 +
     代名 "换流门 R5" -> "P9 E12 观测计数器" + 逐代历史链追加/裁到 3 项)。
  B. **几何面 (本轮新增, 手写)** —— 71 -> 75 字 / 未实现地址 0x14C -> 0x15C / 标签表补
     W71..W74: NW 默认值族 (`NW=` / `SNAP_WORDS=` / `SW=` / `NW_FIX` / `awk -v NW=` /
     指纹 bat / `localparam integer NW`) + 表族 (`WLABEL` / `NAME[]` / 假板 `FAKE_TAIL` /
     `V=` / `W=[…]`) + 地址族 (`0x14C -> 0x15C` 的活行/判据名) + `check_window.py` 的
     `nnew_top 5->9`。
⛔ 不做任何通配替换到仓内文件: 本脚本只**打印** E13(...) 块文本 (写 EDITS_28_BLOCK.txt)。
⛔ 每条 old 侧必须**逐字命中**盘上现状恰 n 次 (自检; 不中 = 响亮失败)。
"""
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
spec = importlib.util.spec_from_file_location("arb", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

NEWNAME = "P9 E12 观测计数器"
DATE = "2026-10-15"


def rep(s, a, b, tag):
    assert s.count(a) >= 1, "entry[%s] 锚点 0 命中: %r" % (tag, a[:70])
    return s.replace(a, b)


# ===========================================================================
# A. BID 面 (24 处) —— 逐条显式变换 (index 与 EDITS_27 序一致)
# ===========================================================================
def f0(s):      # [0]/[1] j6+tcpreg EXPECT_BID 裸行
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000027}   # 2026-10-15 换流门 R5 (71 字; 原 0x00000026 = RFC seq 修复 / 0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲)",
        "EXPECT_BID=${EXPECT_BID:-0x00000028}   # 2026-10-15 P9 E12 观测计数器 (75 字; 原 0x00000027 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x25 = F-3 修复)",
        "0")


def f2(s):      # [2]/[3] j6+tcpreg 档表: 顶部插新行 (旧行逐字保留于下)
    return ('  "75|0x00000028|61 62|P9 E12 观测计数器 (2026-10-15) 75 字 / BID 0x28 '
            '(E12 四观测计数器: `rtl/app_pattern.v` 的 `stat_up_ev`/`stat_sw_req`/'
            '`stat_sw_apply`/`stat_up_pend` 接快照 W71..W74; **几何变**: 71 → 75 字, '
            '未实现地址 0x14C → 0x15C)"\n' + s)


def f4(s):      # [4] p7b_snap EXPECT_BID
    return rep(s, "EXPECT_BID=${EXPECT_BID:-0x00000027}",
                  "EXPECT_BID=${EXPECT_BID:-0x00000028}", "4")


def f5(s):      # [5] p7b_snap 头部"现役"块: 顶部插新块, 旧块逐字保留于下
    s = rep(s, "**现役 = 71 字 / BID 0x27**", "**现役 = 75 字 / BID 0x28**", "5a")
    return rep(s,
        "#   ⭐ 换流门 R5 (2026-10-15): 身份 0x26 → **0x27** (**字长/未实现地址不变** = 71 字 / 0x14C;\n",
        "#   ⭐ P9 E12 观测计数器 (2026-10-15): **字长 71 → 75** (W71..W74 = 四观测计数器\n"
        "#      `stat_up_ev`/`stat_sw_req`/`stat_sw_apply`/`stat_up_pend`) + 身份 0x27 → **0x28**;\n"
        "#      未实现地址 **0x14C → 0x15C** (快照末字后仍是 MIR 四字; 公式 `0x20+4*NW+16` 不变)。\n"
        "#   ⭐ 换流门 R5 (2026-10-15): 身份 0x26 → **0x27** (**字长/未实现地址不变** = 71 字 / 0x14C;\n",
        "5b")


def f6(s):      # [6] p6e_snap_check EXPECT_BID 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000027}       # ⛔ 2026-10-15 换流门 R5: 原默认 0x00000026 (RFC seq 修复) / 0x25 (F-3 修复) / 0x0A (Stage C)",
        "EXPECT_BID=${EXPECT_BID:-0x00000028}       # ⛔ 2026-10-15 P9 E12 观测计数器: 原默认 0x00000027 (换流门 R5) / 0x26 (RFC seq 修复) / 0x0A (Stage C)",
        "6")


def f7(s):      # [7] gate4_accept 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000027}      # 换流门 R5 = 0x27 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x26 = RFC seq 修复 / 0x25 = F-3 修复)",
        "EXPECT_BID=${EXPECT_BID:-0x00000028}      # P9 E12 观测计数器 = 0x28 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x27 = 换流门 R5 / 0x26 = RFC seq 修复)",
        "7")


def f8(s):      # [8] gate4_selftest 现役注释行 + FAKE_BID 旧口径行
    return rep(s,
        "  #    而\"正例必须 0 FAIL\"是本脚本的断言⑤)。现役 = **0x27** (换流门 R5 71 字 —— ⛔ 2026-10-15 同步轮: 原 0x26 = RFC seq 修复 /\n"
        "  #    0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲 / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时\n"
        "  #    FAKE_BID=0x00000026 (RFC seq 修复; SNAP_WORDS=71) / 0x00000025 (F-3 修复; 71) / 0x00000017 / 0x00000008。\n",
        "  #    而\"正例必须 0 FAIL\"是本脚本的断言⑤)。现役 = **0x28** (P9 E12 观测计数器 75 字 —— ⛔ 2026-10-15 同步轮: 原 0x27 = 换流门 R5 /\n"
        "  #    0x26 = RFC seq 修复 / 0x25 = F-3 修复 / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时\n"
        "  #    FAKE_BID=0x00000027 (换流门 R5; SNAP_WORDS=71) / 0x00000026 (RFC seq 修复; 71) / 0x00000017 / 0x00000008。\n",
        "8")


def f9(s):      # [9] FAKE_BID 活行
    return rep(s, "  0X04) V=\\${FAKE_BID:-0x00000027};;",
                  "  0X04) V=\\${FAKE_BID:-0x00000028};;", "9")


def f10(s):     # [10] negctrl 几何块首行: 换新 + 旧行降级为"原句"
    return rep(s,
        "# 几何: **71 字 (W0..W70)** —— 换流门 R5 (2026-10-15, BID=0x27 / 未实现 0x14C);\n",
        "# 几何: **75 字 (W0..W74)** —— P9 E12 观测计数器 (2026-10-15, BID=0x28 / 未实现 0x15C);\n"
        "#       (原句: \"71 字 (W0..W70) —— 换流门 R5 (2026-10-15, BID=0x27 / 未实现 0x14C)\" = 历史代, 逐字保留于下)\n",
        "10")


def f11(s):     # [11] negctrl BID echo 历史链移一格
    s = rep(s, "echo \"BID 0x00000027\"", "echo \"BID 0x00000028\"", "11a")
    return rep(s,
        "换流门 R5: 原 0x26 = RFC seq 修复 / 0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲",
        "P9 E12 观测计数器: 原 0x27 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x25 = F-3 修复",
        "11b")


def f12(s):     # [12] livefake 注释块: 顶部插新块, 旧块"现役代"改"当时的现役代"
    return ("    #   ⛔ 2026-10-15 (换流门 R5 → P9 E12 观测计数器): **几何变** —— 75 字槽 = **0x28**\n"
            "    #      (71 字槽的身份停在上代 0x27); 兜底值同改 0x28 (现役代)。\n"
            "    #      ⚠️ 本字典**按 NW 索引** ⇒ 读 71 字及更早归档位流时须配套回改。\n"
            + rep(s, "兜底值同改 0x27 (现役代)", "兜底值同改 0x27 (当时的现役代)", "12"))


def f13(s):     # [13] livefake bid 字典活行 (新 NW 槽插在最前)
    return rep(s,
        '    bid = {71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x00000027")',
        '    bid = {75: "0x00000028", 71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x00000028")',
        "13")


def f14(s):     # [14] p6e_snap_selftest_fix2: 历史链移一格
    return rep(s,
        "  0X04) V=\\${FAKE_BID:-0x00000027};;   # 换流门 R5 = 0x27 (⛔ 原 0x26 = RFC seq 修复 / 0x25 = F-3 修复 / 0x0A = Stage C);",
        "  0X04) V=\\${FAKE_BID:-0x00000028};;   # P9 E12 观测计数器 = 0x28 (⛔ 原 0x27 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x0A = Stage C);",
        "14")


def f15(s):     # [15] final_state.sh 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000027}   # ⛔ 2026-10-15 换流门 R5 (71 字); 原 0x26 = RFC seq 修复",
        "EXPECT_BID=${EXPECT_BID:-0x00000028}   # ⛔ 2026-10-15 P9 E12 观测计数器 (75 字); 原 0x27 = 换流门 R5",
        "15")


def f16(s):     # [16] gen_inputs docstring: 顶部插新行 + 旧行降级
    return rep(s,
        "         ⚠️ 几何 = **71 字 / BID 0x27** (换流门 R5, 2026-10-15 同步轮从 71 字/BID 0x26 同步)\n"
        "            ⛔ 2026-10-15 换流门-R5 同步: 上一行原写 \"几何 = 71 字 / BID 0x26 (RFC seq 修复)\";\n",
        "         ⚠️ 几何 = **75 字 / BID 0x28** (P9 E12 观测计数器, 2026-10-15 同步轮从 71 字/BID 0x27 同步)\n"
        "            ⛔ 2026-10-15 E12 同步: 上一行原写 \"几何 = 71 字 / BID 0x27 (换流门 R5)\";\n"
        "            ⛔ 2026-10-15 换流门-R5 同步: 那一行的上一行原写 \"几何 = 71 字 / BID 0x26 (RFC seq 修复)\";\n",
        "16")


def f17(s):     # [17] 夹具自述行
    return rep(s,
        "本夹具现 = **71 字 / BID 0x27**, accept 默认也已是 71 字 / BID 0x27",
        "本夹具现 = **75 字 / BID 0x28**, accept 默认也已是 75 字 / BID 0x28",
        "17")


def f18(s):     # [18] 逐代链: 末尾追加新格 + 旧格去粗
    return rep(s,
        "→ **71 字/0x27 (换流门 R5, 未实现地址 0x14C 不变)**。",
        "→ 71 字/0x27 (换流门 R5) → **75 字/0x28 (P9 E12 观测计数器, 未实现地址 0x14C → 0x15C)**。",
        "18")


def f19(s):     # [19] BID_FIX: 历史值移一格
    return rep(s,
        "BID_FIX = 0x00000027       # 位流身份 (换流门 R5) —— ⛔ 2026-10-15: 原值 0x00000026 (RFC seq 修复)",
        "BID_FIX = 0x00000028       # 位流身份 (P9 E12 观测计数器) —— ⛔ 2026-10-15: 原值 0x00000027 (换流门 R5)",
        "19")


def f20(s):     # [20] counters TB: 历史链移一格
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (换流门 R5 71-word = 0x27; 原 71-word=0x26(RFC seq 修复) / 0x25(F-3 修复) / 63-word=9)\", v, 32'h00000027);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (P9 E12 观测计数器 75-word = 0x28; 原 71-word=0x27(换流门 R5) / 0x26(RFC seq 修复) / 63-word=9)\", v, 32'h00000028);",
        "20")


def f21(s):     # [21] wrapper TB
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (换流门 R5 构建 = 0x27)\", v, 32'h00000027);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (P9 E12 观测计数器构建 = 0x28)\", v, 32'h00000028);",
        "21")


def f22(s):     # [22] step0 第 1 处
    return rep(s,
        "#     (i)  缺省档 (NW=71 / 0x14C / BID 0x27) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);",
        "#     (i)  缺省档 (NW=75 / 0x15C / BID 0x28) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);",
        "22")


def f23(s):     # [23] step0 第 2 处
    return rep(s,
        "echo \"### C-a) 默认档 (NW=71 / 0x14C / BID 0x27) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x27)\"",
        "echo \"### C-a) 默认档 (NW=75 / 0x15C / BID 0x28) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x28)\"",
        "23")


BID_OVERRIDES = {
    0: f0, 1: f0, 2: f2, 3: f2, 4: f4, 5: f5, 6: f6, 7: f7, 8: f8, 9: f9,
    10: f10, 11: f11, 12: f12, 13: f13, 14: f14, 15: f15, 16: f16, 17: f17,
    18: f18, 19: f19, 20: f20, 21: f21, 22: f22, 23: f23,
}

bid_rows = []
for i, (rel, _o, new, n) in enumerate(m.EDITS_27):
    f = BID_OVERRIDES.get(i)
    assert f is not None, "entry %d 无变换 (逐条显式; 不许漏)" % i
    bid_rows.append((rel, new, f(new), n))

# ===========================================================================
# B. 几何面 (手写; 每条 old 必须逐字命中盘上现状 n 次)
# ===========================================================================
#   ⚠️ `_TAIL71` = `p7b_gate4_selftest.sh` 盘上**现读**的 71 档 FAKE_TAIL 分支全文
#      (从 `if [ "$SW" -ge 71 ]; then` 到闭引号后换行; 由下方自检再核一遍).
_TAIL71 = (
    'if [ "$SW" -ge 71 ]; then\n'
    "  FAKE_TAIL='  0X114) V=1234;;  # W61 app_ctrl.stat_wu (次数; 非 0 才像真板)\n"
    '  0X118) V=0;;     # W62 app_ctrl.rx_occ_bytes (17 位 ⇒ 高位恒 0)\n'
    '  0X11C) V=0;;     # W63 app_pattern.stat_frmwait_cyc (停滞拍数; 0 = 无停顿)\n'
    '  0X120) V=0;;     # W64 app_pattern.stat_bp_cyc (背压拍数)\n'
    '  0X124) V=0;;     # W65 mac_tx_10g.stat_tx_idle (S_IDLE 拍数; 0 = 空载, 建 D 新增)\n'
    '  0X128) V=0;;     # W66 tcp_tx_frame.stat_winstall (窗口门停顿拍数, 建 E 新增)\n'
    '  0X12C) V=0;;     # W67 tcp_tx_frame.stat_winstall_cap (板帽侧等窗拍数, 建 F 新增)\n'
    '  0X130) V=0;;     # W68 tcp_rx.stat_ack_adv (推进 snd_una 的 ACK 次数, 建 F 新增)\n'
    '  0X134) V=0;;     # W69 tcp_tx_frame.o_win_at_winstall (等窗拍操作点锁存, 建 F 新增)\n'
    '  0X138) V=0;;     # W70 app_rx_mirror.drop_bytes (载荷镜像拒收字节数, M1 新增; 真字)\n'
    "  0X14C) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (71 字; M1 起 = 0x20+4*SW+16)'\n"
)

GEOM = [
    # ---- G1 j6/tcpreg: NW 默认值 + 几何门注释 ----
    ("_proj_10g/notes/p7b_affinity/j6_r6fix.sh",
     "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-71}` (M1 镜像窗; 更早构建 F=70 / E=67 / P7B-A7=66 / P7B-GAP9-TX=65 / 原 63) 且 **export**",
     "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-75}` (P9 E12 观测计数器; 更早 M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export**", 1),
    ("_proj_10g/notes/p7b_affinity/j6_r6fix.sh", "\nNW=${NW:-71}\n", "\nNW=${NW:-75}\n", 1),
    ("_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh",
     "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-71}` (M1 镜像窗; 更早构建 F=70 / E=67 / P7B-A7=66 / P7B-GAP9-TX=65 / 原 63) 且 **export**",
     "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-75}` (P9 E12 观测计数器; 更早 M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export**", 1),
    ("_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh", "\nNW=${NW:-71}\n", "\nNW=${NW:-75}\n", 1),
    # ---- G3 p7b_snap: NW / UNIMPL 注 / NAME 表 ----
    ("_proj_pcie/p7b_biz/p7b_snap.sh", "\nNW=${NW:-71}\n", "\nNW=${NW:-75}\n", 1),
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*NW + 16 )))}   # 71 ⇒ 0x14C (M1 期B 起; 70 字及更早 = 0x138/0x12C/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*NW + 16 )))}   # 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)", 1),
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     "# ⭐ M1 (2026-10-11): W70 —— 载荷镜像的拒收字节数 (真值源 = wrapper 装配段 `p7bdp_dout[30*32 +: 32]`):\n[70]=mir_drop_bytes\n)",
     "# ⭐ M1 (2026-10-11): W70 —— 载荷镜像的拒收字节数 (真值源 = wrapper 装配段 `p7bdp_dout[30*32 +: 32]`):\n"
     "[70]=mir_drop_bytes\n"
     "# ⭐ P9 E12 (2026-10-15): W71..W74 —— 换流门四观测计数器 (真值源 = wrapper 装配段\n"
     "#    `p7bdp_dout[31..34*32 +: 32]` / 槽 31..34):\n"
     "[71]=app_stat_up_ev      [72]=app_stat_sw_req     [73]=app_stat_sw_apply\n"
     "[74]=app_stat_up_pend\n)", 1),
    ("_proj_pcie/p7b_biz/p7b_snap.sh",
     "#    地址由 NW 派生: UNIMPL_ADDR = 0x20+4*63 = **0x11C** (⛔ 2026-10-10: 现役 NW=65 ⇒ **0x124**)。",
     "#    地址由 NW 派生: UNIMPL_ADDR = 0x20+4*63 = **0x11C** (⛔ 2026-10-10: 现役 NW=65 ⇒ **0x124**;\n"
     "#    ⭐ P9 E12: 现役 NW=75 / MIR 四字在中间 ⇒ **0x15C** = 0x20+4*75+16)。", 1),
    # ---- G4 p6e_snap_check: SNAP_WORDS / UNIMPL 注 / WLABEL ----
    ("_proj_pcie/p6e_snap_check.sh", "SNAP_WORDS=${SNAP_WORDS:-71}", "SNAP_WORDS=${SNAP_WORDS:-75}", 1),
    ("_proj_pcie/p6e_snap_check.sh",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 71 ⇒ 0x14C (M1 期B 起; 70 字及更早 = 0x138/0x12C/0x124/0x11C/0xEC —— 读旧位流须显式覆盖)",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0xEC —— 读旧位流须显式覆盖)", 1),
    ("_proj_pcie/p6e_snap_check.sh",
     " #       真值源 = `board/wrapper_p4.v` 的装配段注释。表长必须 == SNAP_WORDS (71),\n"
     " #       否则循环把它们打成 `<无标签>` (2026-10-10 加固轮: 本表原只到 W64; M1 再补 W70)。",
     " #       真值源 = `board/wrapper_p4.v` 的装配段注释。表长必须 == SNAP_WORDS (75),\n"
     " #       否则循环把它们打成 `<无标签>` (2026-10-10 加固轮: 本表原只到 W64; M1 再补 W70;\n"
     " #       P9 E12 再补 W71..W74 —— 四个换流门观测计数器)。", 1),
    ("_proj_pcie/p6e_snap_check.sh",
     ' "mir_drop_bytes     (app_rx_mirror.drop_bytes: 载荷镜像拒收字节数; M1)" )',
     ' "mir_drop_bytes     (app_rx_mirror.drop_bytes: 载荷镜像拒收字节数; M1)"\n'
     ' # ---- P9 E12 (2026-10-15) 新增 4 字 (71 → 75 字窗口; 换流门四观测计数器) ----\n'
     ' "app_stat_up_ev     (app_pattern.stat_up_ev: app 实收 ev_up 事件数; P9 E12)"\n'
     ' "app_stat_sw_req    (app_pattern.stat_sw_req: 换流收尾请求数 (ev_same_act); P9 E12)"\n'
     ' "app_stat_sw_apply  (app_pattern.stat_sw_apply: 换流应用数 (sw_apply); P9 E12)"\n'
     ' "app_stat_up_pend   (app_pattern.stat_up_pend: A3 异槽登记数 (ev_other_act); P9 E12)" )', 1),
    # ---- G5 p7b_gate4_accept: SNAP_WORDS / UNIMPL ----
    ("_proj_pcie/p7b_gate4_accept.sh", "SNAP_WORDS=${SNAP_WORDS:-71}", "SNAP_WORDS=${SNAP_WORDS:-75}", 1),
    ("_proj_pcie/p7b_gate4_accept.sh",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 71 ⇒ 0x14C (M1 期B 起; 70 字及更早 = 0x138/0x12C/0x128/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)",
     "UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x128/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)", 1),
    ("_proj_pcie/p7b_gate4_accept.sh",
     "#    ⇒ 71 字 = **0x14C**。⚠️ 读旧位流 (≤70 字) 必须显式 `UNIMPL_ADDR=` 覆盖, 否则默认值会指到真字。",
     "#    ⇒ 71 字 = **0x14C** (M1 期B); ⭐ P9 E12 起 75 字 = **0x15C**。\n"
     "#    ⚠️ 读旧位流 (≤71 字) 必须显式 `UNIMPL_ADDR=` 覆盖, 否则默认值会指到真字。", 1),
    # ---- G6 p7b_gate4_selftest: SW= / 注释 / 新 FAKE_TAIL 分支 ----
    ("_proj_pcie/p7b_gate4_selftest.sh", "SW=${SNAP_WORDS:-71}", "SW=${SNAP_WORDS:-75}", 1),
    ("_proj_pcie/p7b_gate4_selftest.sh",
     "#   SW ≥ 71 (2026-10-11 M1 起) ⇒ 0x138 也是**窗口内的真字** (W70), 且未实现地址 = 0x14C\n"
     "#     (M1 起公式 `0x20+4*SW+16`) ⇒ `FAKE_UNIMPL` 挪到 **0x14C**;\n",
     "#   SW ≥ 75 (2026-10-15 P9 E12 起) ⇒ 0x13C/0x140/0x144/0x148 也是**窗口内的真字**\n"
     "#     (W71..W74 = 换流门四观测计数器), 且未实现地址 = 0x15C ⇒ `FAKE_UNIMPL` 挪到 **0x15C**;\n"
     "#   SW ≥ 71 (2026-10-11 M1 起) ⇒ 0x138 也是**窗口内的真字** (W70), 且未实现地址 = 0x14C\n"
     "#     (M1 起公式 `0x20+4*SW+16`) ⇒ `FAKE_UNIMPL` 在 **0x14C**;\n", 1),
    #   ⚠️ FAKE_TAIL 分档: 新 **75 档** 必须是**新分支** (`if -ge 75`), 旧的 `-ge 71` 分支
    #      逐字保留 (降为 elif) —— 否则 71 字代的读数会拿到 75 档的表 (结构性错代)。
    ("_proj_pcie/p7b_gate4_selftest.sh", _TAIL71,
     _TAIL71.replace('if [ "$SW" -ge 71 ]; then', 'if [ "$SW" -ge 75 ]; then', 1)
     .replace("  0X14C) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (71 字; M1 起 = 0x20+4*SW+16)'",
              "  0X13C) V=0;;     # W71 app_pattern.stat_up_ev (换流门观测; P9 E12)\n"
              "  0X140) V=0;;     # W72 app_pattern.stat_sw_req (P9 E12)\n"
              "  0X144) V=0;;     # W73 app_pattern.stat_sw_apply (P9 E12)\n"
              "  0X148) V=0;;     # W74 app_pattern.stat_up_pend (P9 E12)\n"
              "  0X15C) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (75 字; = 0x20+4*SW+16)'", 1)
     + 'elif [ "$SW" -ge 71 ]; then\n' + _TAIL71, 1),
    # ---- G7 negctrl: V 表 / 循环界 / awk NW ----
    ("_proj_pcie/p7b_gate4_negctrl.sh",
     "                0 0 0 0)   # W51..W70 (M1: W70 = app_rx_mirror.drop_bytes)\n",
     "                0 0 0 0 0 0 0 0)   # W51..W74 (M1: W70 = app_rx_mirror.drop_bytes; E12: W71..W74 = 换流门四观测计数器)\n", 1),
    ("_proj_pcie/p7b_gate4_negctrl.sh",
     "    local i; for (( i = 0; i < 71; i++ )); do printf 'W%d 0x%X\\n' \"$i\" \"${V[$i]}\"; done\n",
     "    local i; for (( i = 0; i < 75; i++ )); do printf 'W%d 0x%X\\n' \"$i\" \"${V[$i]}\"; done\n", 1),
    ("_proj_pcie/p7b_gate4_negctrl.sh", "shift1(){ awk -v NW=71 ", "shift1(){ awk -v NW=75 ", 1),
    # ---- G8 livefake: W 表长度 ----
    ("_proj_pcie/p7b_gate4_livefake.sh",
     "        + [0] * 20          # W51..W70 = P7B-BIZ/WU/C/D/E/F + M1 新增字 (accept 只要求窗口齐全 + 无 0xffffffff)",
     "        + [0] * 24          # W51..W74 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 新增字 (accept 只要求窗口齐全 + 无 0xffffffff)", 1),
    # ---- G9 selftest_fix2: 假板地址表 ----
    ("_proj_pcie/p6e_snap_selftest_fix2.sh",
     "# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **71 字 / 未实现 0x14C**; 2026-10-11 M1 镜像窗;\n",
     "# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **75 字 / 未实现 0x15C**; 2026-10-15 P9 E12 观测计数器;\n"
     "#    原句 = 71 字 / 0x14C (M1 镜像窗);\n", 1),
    ("_proj_pcie/p6e_snap_selftest_fix2.sh",
     "  0X14C) V=0xffffffff;;                                       # 未实现地址 (71 字; M1 起 = 0x20+4*SW+16)\n",
     "  0X13C) V=0x00000000;;                                       # W71 app_pattern.stat_up_ev (75 字起; P9 E12)\n"
     "  0X140) V=0x00000000;;                                       # W72 app_pattern.stat_sw_req (P9 E12)\n"
     "  0X144) V=0x00000000;;                                       # W73 app_pattern.stat_sw_apply (P9 E12)\n"
     "  0X148) V=0x00000000;;                                       # W74 app_pattern.stat_up_pend (P9 E12)\n"
     "  0X15C) V=0xffffffff;;                                       # 未实现地址 (75 字; = 0x20+4*SW+16)\n", 1),
    # ---- G10 final_state.sh: UNIMPL 地址 + 注 + 末字读数 ----
    ("_proj_10g/notes/p7b_gate4_3/final_state.sh",
     'echo "MAGIC=$(rd 0x00) BID=$BID MARKER=$(rd 0x14) UNIMPL=$(rd 0x14c) gen=$(( (s >> 16) & 0xffff ))"',
     'echo "MAGIC=$(rd 0x00) BID=$BID MARKER=$(rd 0x14) UNIMPL=$(rd 0x15c) gen=$(( (s >> 16) & 0xffff ))"', 1),
    ("_proj_10g/notes/p7b_gate4_3/final_state.sh",
     "# ⚠️ UNIMPL 地址跟窗口宽度走: **71 字 (M1, 2026-10-11 起) ⇒ 0x14C** (word 83; 快照末字后接 MIR 四字\n"
     "#     ⇒ 公式 = 0x20+4*NW+16); 70 字 (构建 F 起) = 0x138 (word 78);\n",
     "# ⚠️ UNIMPL 地址跟窗口宽度走: **75 字 (P9 E12, 2026-10-15 起) ⇒ 0x15C** (word 87; 快照末字后接\n"
     "#     MIR 四字 ⇒ 公式 = 0x20+4*NW+16); 71 字 (M1, 2026-10-11 起) = 0x14C (word 83);\n"
     "#     70 字 (构建 F 起) = 0x138 (word 78);\n", 1),
    ("_proj_10g/notes/p7b_gate4_3/final_state.sh",
     'echo "W70=$(rd 0x138)  # M1: app_rx_mirror.drop_bytes (载荷镜像拒收字节数)"\n',
     'echo "W70=$(rd 0x138)  # M1: app_rx_mirror.drop_bytes (载荷镜像拒收字节数)"\n'
     'echo "W71=$(rd 0x13c) W72=$(rd 0x140) W73=$(rd 0x144) W74=$(rd 0x148)  # P9 E12: 换流门四观测计数器 (up_ev / sw_req / sw_apply / up_pend)"\n', 1),
    # ---- G11 gen_inputs.py: NW_FIX + 快照行 ----
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "NW_FIX = 71                # 快照字数 (W0..W70; M1 起 —— 原 70)",
     "NW_FIX = 75                # 快照字数 (W0..W74; P9 E12 起 —— 原 71 (M1) / 70)", 1),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "  快照 : SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W70 / UNIMPL / SNAP_END",
     "  快照 : SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W74 / UNIMPL / SNAP_END", 1),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "    \"\"\"**71 字 (W0..W70)**; lat = 该块锁存的时刻 (秒) ⇒ 三个域自由计数由它算出。",
     "    \"\"\"**75 字 (W0..W74)**; lat = 该块锁存的时刻 (秒) ⇒ 三个域自由计数由它算出。", 1),
    ("_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
     "            ⛔ M1 起未实现地址不再 = 0x20+4*NW (快照末字后接 MIR 四字) ⇒ = 0x20+4*NW+16 = **0x14C**;",
     "            ⛔ M1 起未实现地址不再 = 0x20+4*NW (快照末字后接 MIR 四字) ⇒ = 0x20+4*NW+16 = 0x14C (M1) / **0x15C** (P9 E12 起);", 1),
    # ---- G12 p7b_chain TB: 地址 + 判据名 + 界注 ----
    ("_proj_10g/p7b_chain/sim/tb_p7b_chain.v",
     "        u_dut.u_pcie_xdma.axil_read(32'h14C, v);\n"
     '        chk("7b 0x14C reads 0 no wrap",\n'
     '            (v === 32\'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2\'d2),\n'
     '            "axi_regs decode; 71-word bound (M1: 0x14C = 0x20+4*71+16; 原 70 字/0x138, 67 字/0x12C, 63 字/0x11C; 2026-10-11 M1 订正)");',
     "        u_dut.u_pcie_xdma.axil_read(32'h15C, v);\n"
     '        chk("7b 0x15C reads 0 no wrap",\n'
     '            (v === 32\'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2\'d2),\n'
     '            "axi_regs decode; 75-word bound (P9 E12: 0x15C = 0x20+4*75+16; 原 71 字/0x14C, 70 字/0x138, 63 字/0x11C; 2026-10-15 E12 订正)");', 1),
    # ---- G13 三个指纹 bat ----
    ("_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat",
     'findstr /C:"SNAP_NW_P6E = 71" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 71-word version & exit /b 92 )',
     'findstr /C:"SNAP_NW_P6E = 75" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 75-word version & exit /b 92 )', 1),
    ("_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat",
     'findstr /C:"SNAP_NW_P6E = 71" "%ROOT%\\board\\wrapper_p4.v" >NUL || ( echo [FINGERPRINT FAIL] wrapper is not 71-word & exit /b 92 )',
     'findstr /C:"SNAP_NW_P6E = 75" "%ROOT%\\board\\wrapper_p4.v" >NUL || ( echo [FINGERPRINT FAIL] wrapper is not 75-word & exit /b 92 )', 1),
    ("sim/p5wu_p1p2/run_xvlog_wrapper63.bat",
     'findstr /C:"SNAP_NW_P6E = 71" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 71-word version & exit /b 92 )',
     'findstr /C:"SNAP_NW_P6E = 75" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 75-word version & exit /b 92 )', 1),
    # ---- G14 tb_biz_win.v ----
    ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
     "    localparam integer NW = 71;  // = wrapper 的 SNAP_NW_P6E (M1; 原 70 = 构建 F / 61/63/65/66/67)",
     "    localparam integer NW = 75;  // = wrapper 的 SNAP_NW_P6E (P9 E12; 原 71 = M1 / 70 = 构建 F / 61/63/65/66/67)", 1),
    # ---- G15 check_window.py: nnew_top 5 -> 9 ----
    ("_proj_10g/notes/p7b_biz_win/check_window.py",
     "    nnew_top = 5                              # ⭐ M1: W70/W69/W68/W67/W66 (p7bdp 槽 30/29/28/27/26)\n"
     "                                              #   —— 上一代 (构建 F) 是 4 (W69..W66); 新字 W70 落\n"
     "                                              #   在最上面 ⇒ 顶端段 +1 (本条**每代都要按该代接线核**)",
     "    nnew_top = 9                              # ⭐ P9 E12: W74/W73/W72/W71 (槽 34/33/32/31)\n"
     "                                              #   + W70/W69/W68/W67/W66 (槽 30/29/28/27/26)\n"
     "                                              #   —— 上一代 (M1) 是 5 (W70..W66); E12 四个字全落\n"
     "                                              #   在最上面 ⇒ 顶端段 +4 (本条**每代都要按该代接线核**)", 1),
    ("_proj_10g/notes/p7b_biz_win/check_window.py",
     "    ntx = 1                                   # 其后的 tx 束项数 (W65) —— 现在排第 6 项",
     "    ntx = 1                                   # 其后的 tx 束项数 (W65) —— 现在排第 10 项", 1),
    #   ⚠️ 判据 5a 的**标签**写死了 "W(NW-1)/…-4" 与"槽 …"两项 (它按 nnew_top 打 4 个名字) ⇒ 标签要跟上
    ("_proj_10g/notes/p7b_biz_win/check_window.py",
     '       "5a 最上面 %d 项 = W%d/W%d/W%d/W%d (p7bdp 束槽 %d/%d/%d/%d; 构建 F)"\n'
     '       % (nnew_top, NW - 1, NW - 2, NW - 3, NW - 4, pdp - 1, pdp - 2, pdp - 3, pdp - 4),',
     '       "5a 最上面 %d 项 = %s (p7bdp 束槽 %s; P9 E12)"\n'
     '       % (nnew_top, "/".join("W%d" % (NW - 1 - i) for i in range(nnew_top)),\n'
     '          "/".join("%d" % (pdp - 1 - i) for i in range(nnew_top))),', 1),
]

# ---- 自检 1: old 侧必须逐字在盘上 (否则 ⑬ 的锚点会 FAIL) ----
rows = list(bid_rows)
bad = 0
for rel, o, nw_, n in rows:
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    b, nl = m.rd(p)
    cnt = b.decode("utf-8").count(o.replace("\n", nl.decode()))
    if cnt != n:
        bad += 1
        print("SELFCHECK FAIL old-side on-disk hits=%d/%d  %s" % (cnt, n, rel))
print("SELFCHECK(BID) old-side: %d 条中 %d 条不匹配" % (len(rows), bad))

geo_rows = []
gbad = 0
for rel, o, nw_, n in GEOM:
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    b, nl = m.rd(p)
    cnt = b.decode("utf-8").count(o.replace("\n", nl.decode()))
    if cnt != n:
        gbad += 1
        print("SELFCHECK FAIL(GEOM) hits=%d/%d  %s :: %r" % (cnt, n, rel, o[:70]))
    geo_rows.append((rel, o, nw_, n))
print("SELFCHECK(GEOM) old-side: %d 条中 %d 条不匹配" % (len(geo_rows), gbad))

# ---- 自检 2: new 侧必须与 old 侧不同; 残留旧值打印 (须为"逐字保留的历史") ----
warns = 0
for i, (rel, o, nw_, n) in enumerate(rows):
    assert o != nw_, "entry %d new == old" % i
    if "0x00000027" in nw_ or "32'h00000027" in nw_:
        warns += 1
        print("WARN entry %d 仍含 8 位旧值 0x00000027 (须为'逐字保留的历史'): %s" % (i, rel))
print("SELFCHECK new-side: %d 条 WARN (历史保留 = 预期; 逐条人工核)" % warns)


def vlit(s):
    out = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + out + "'"


lines = []
for rel, o, nw_, n in rows:
    lines.append("E13(%s," % vlit(rel))
    lines.append("  %s," % vlit(o))
    lines.append("  %s, %d)" % (vlit(nw_), n))
lines.append("")
lines.append("# ---- 几何面 (本轮新增; 71 -> 75 / 0x14C -> 0x15C / 标签表补 W71..W74) ----")
for rel, o, nw_, n in geo_rows:
    lines.append("E13(%s," % vlit(rel))
    lines.append("  %s," % vlit(o))
    lines.append("  %s, %d)" % (vlit(nw_), n))
block = "\n".join(lines) + "\n"
with open(os.path.join(HERE, "EDITS_28_BLOCK.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write(block)
print("WROTE EDITS_28_BLOCK.txt: %d 条 (BID %d + GEOM %d) / %d 文件"
      % (len(rows) + len(geo_rows), len(rows), len(geo_rows),
         len(set(r[0] for r in rows) | set(r[0] for r in geo_rows))))
