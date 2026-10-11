#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑦ (EDITS_22) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_22 = []` + `def E7(...)`;  ② `STAGES` 追加 0x22;  ③ ⑬ 段 (E7 块) 插到 ⑧ 段前;
 ④ 顶部 docstring 加 ⑦ 指针;  ⑤ ALLOW 追加 4 条 (B 面分类)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_22_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_22" in s:
    print("ALREADY SPLICED (EDITS_22 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E7 构造函数 ----
sub1("""EDITS_21 = []          # 阶段 ⑥: 0x20 树 -> 0x21 树 (P8-STG 16 B 字节粒度弹性暂存; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_21 = []          # 阶段 ⑥: 0x20 树 -> 0x21 树 (P8-STG 16 B 字节粒度弹性暂存; **BID-only**: 几何不变 71/0x14C)
EDITS_22 = []          # 阶段 ⑦: 0x21 树 -> 0x22 树 (P9 XDMA MM→AXIS; **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_22 声明")

sub1("""def E6(rel, old, new, n=1):
    EDITS_21.append((rel, old, new, n))
""",
     """def E6(rel, old, new, n=1):
    EDITS_21.append((rel, old, new, n))


def E7(rel, old, new, n=1):
    EDITS_22.append((rel, old, new, n))
""", "①b E7() 构造函数")

# ---- ② STAGES 追加 0x22 ----
sub1("""          ("0x00000021", EDITS_21, "P8-STG 16 B 弹性暂存 (2026-10-11)", 71, 0x14C)]""",
     """          ("0x00000021", EDITS_21, "P8-STG 16 B 弹性暂存 (2026-10-11)", 71, 0x14C),
          ("0x00000022", EDITS_22, "P9 XDMA MM→AXIS (2026-10-11)", 71, 0x14C)]""",
     "② STAGES 追加 0x22")

# ---- ③ ⑬ 段 (E7 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑬ 阶段 ⑦ (0x21 → 0x22, **P9 XDMA MM→AXIS**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = `board/wrapper_p4.v` 的 PCIe 用户接口 **AXI4-MM → AXI4-Stream** 改造
#   (新件 `rtl/axis_c2h_stream.v` + 端口表 75→50 + `board/build_p7b_ku5p.tcl` 的 XDMA 配置/
#   断言块 + `_proj_pcie/rtl/axi_regs.v` ver 3→4 + sim 桩/TB); 实施 + EDA 读数 =
#   `_proj_10g/notes/p9_axis_impl_20261011/IMPL_REPORT.md` (+ `p8_axis_conf_20261011/CONF.md`)。
#   BID 面 = stage ⑥ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑥/⑤ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩 —— IMPL_REPORT §0-2);
#     · 生成方式 = ⑥ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x22/gen_edits22.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
sub1("""# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     HDR + BLOCK + """
# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     "③ ⑬ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑦ 指针 ----
sub1("""     （P8 镜像 8 B/拍 / **BID-only**, 几何同 ④）/ ⑥ `0x21`（**P8-STG 16 B 字节粒度弹性暂存** /
     **BID-only**, 几何同 ④⑤）—— **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     （P8 镜像 8 B/拍 / **BID-only**, 几何同 ④）/ ⑥ `0x21`（**P8-STG 16 B 字节粒度弹性暂存** /
     **BID-only**, 几何同 ④⑤）/ ⑦ `0x22`（**P9 XDMA MM→AXIS** / **BID-only**, 几何同 ④⑤⑥）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑦ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 核过内容, 见 REPORT) ----
sub1("""    (r"^_proj_10g/notes/p8_board_0x20_20261011/",""",
     """    (r"^_proj_10g/notes/p8_board_0x21_20261011/",
     "旧位流读法: P8 板级轮 0x21 现场 (烧的是 **0x21** 归档位流 ⇒ `burn_0x21.sh` 的 "
     "`WANT=fbb6fca8…`(0x21 位流 sha256)/`EXPBID=0x00000021`/`NW=71` 与 `_tools/run_arm.sh` 的 "
     "`BID=${BID:-0x00000021}`、`final_state.sh` 的 `EXPECT_BID=0x00000021` 都是**那一代的真值**, "
     "由 `WANT` sha256 钉死; 改它反而毁掉该轮取证 —— 登记为 2026-10-11 阶段 ⑦ (0x22) 的新命中)"),
    (r"^_proj_10g/notes/p8_tcp_0x21_20261011/",
     "旧位流读法: P8/TCP 板级轮 0x21 现场 (同上; `_tools/run_tcp_*.sh` 的 `BID=${BID:-0x00000021}` / "
     "`final_state_tcp.sh` 的 `EXPECT_BID=0x00000021` = 那一代真值) —— 阶段 ⑦ (0x22) 的新命中"),
    (r"^_proj_10g/notes/p9_axis_impl_20261011/head_negapp/",
     "诊断副本: P9 实现轮的 **HEAD wrapper 工作副本** (+ ¬APP_MODE 打补丁版) —— "
     "`wrapper_p4_head.v` = 被 copy 的那一刻的 HEAD (BID `0x21` / NW 71 / `SNAP_NW_P6E` 行), "
     "`wrapper_p4_negapp_patched.v` = 在其上打 ¬APP_MODE 的探针副本; 两者都是**编过就丢的一次性副本** "
     "(证据 = 同目录 `xelab_negapp.log`), ⛔ 改它们 = 伪造那次排练的产物 ⇒ 只登记不动"),
    (r"^_proj_10g/notes/p9_build_0x22/",
     "现役: 本轮 (阶段 ⑦ = 0x22) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p8_board_0x20_20261011/",""", "⑤ ALLOW 追加 4 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
