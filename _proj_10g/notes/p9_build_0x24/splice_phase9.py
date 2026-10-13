#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑨ (EDITS_24) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_24 = []` + `def E9(...)`;  ② `STAGES` 追加 0x24;  ③ ⑮ 段 (E9 块) 插到 ⑧ 段前;
  ④ 顶部 docstring 加 ⑨ 指针;  ⑤ ALLOW 追加 9 条 (B 面分类, 见 §ALLOW)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_24_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_24" in s:
    print("ALREADY SPLICED (EDITS_24 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E9 构造函数 ----
sub1("""EDITS_23 = []          # 阶段 ⑧: 0x22 树 -> 0x23 树 (P9 D4 clr 口径修正; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_23 = []          # 阶段 ⑧: 0x22 树 -> 0x23 树 (P9 D4 clr 口径修正; **BID-only**: 几何不变 71/0x14C)
EDITS_24 = []          # 阶段 ⑨: 0x23 树 -> 0x24 树 (P9 URAM 板内缓冲 (修正收口); **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_24 声明")

sub1("""def E8(rel, old, new, n=1):
    EDITS_23.append((rel, old, new, n))
""",
     """def E8(rel, old, new, n=1):
    EDITS_23.append((rel, old, new, n))


def E9(rel, old, new, n=1):
    EDITS_24.append((rel, old, new, n))
""", "①b E9() 构造函数")

# ---- ② STAGES 追加 0x24 ----
sub1("""          ("0x00000023", EDITS_23, "P9 D4 clr 口径修正 (2026-10-12)", 71, 0x14C)]""",
     """          ("0x00000023", EDITS_23, "P9 D4 clr 口径修正 (2026-10-12)", 71, 0x14C),
          ("0x00000024", EDITS_24, "P9 URAM 板内缓冲 (2026-10-13)", 71, 0x14C)]""",
     "② STAGES 追加 0x24")

# ---- ③ ⑮ 段 (E9 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑮ 阶段 ⑨ (0x23 → 0x24, **P9 URAM 板内缓冲 (修正收口)**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = **URAM288 板内缓冲** (`rtl/mir_uram_fifo.v` = `u_mir_buf`, 4096×64 = 32 KB 载荷 +
#   4 字弹性堆 + 3 级读流水; 接在 `u_mir` aux 读口与 `u_mir_axis` 之间, 两侧同钟 ⇒ 无新 CDC)
#   + **F2/F3 修正** (`up_req` 并入 `rst_n`; clr 拍 `pop &&= !clr`)。
#   依据 = 板级 `0x22` 的 D4 后果链 + 复核轮
#   (`_proj_10g/notes/p9_uram_20261013/{REPORT,REVIEW,FIX_REPORT}.md`)。
#   BID 面 = stage ⑧ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑧/⑦ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩);
#     · 生成方式 = ⑧ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x24/gen_edits24.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
sub1("""# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     HDR + BLOCK + """
# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     "③ ⑮ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑨ 指针 ----
sub1("""     **BID-only**, 几何同 ④⑤）/ ⑦ `0x22`（**P9 XDMA MM→AXIS** / **BID-only**, 几何同 ④⑤⑥）/
     ⑧ `0x23`（**P9 D4 clr 口径修正** / **BID-only**, 几何同 ④⑤⑥⑦）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     **BID-only**, 几何同 ④⑤）/ ⑦ `0x22`（**P9 XDMA MM→AXIS** / **BID-only**, 几何同 ④⑤⑥）/
     ⑧ `0x23`（**P9 D4 clr 口径修正** / **BID-only**, 几何同 ④⑤⑥⑦）/
     ⑨ `0x24`（**P9 URAM 板内缓冲 (修正收口)** / **BID-only**, 几何同 ④⑤⑥⑦⑧）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑨ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 预扫 + 逐件核, 见 REPORT) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x23/",""",
     """    (r"^_proj_10g/notes/p9_bench_restore_20261013/",
     "旧位流读法: 台架恢复/见证轮现场 (2026-10-13; `03_burn_pcie_id.sh` 的 "
     "`WANT=066a3923…3126`(= **0x23** 位流 sha)/`EXPECT_BID=0x00000023` 与 `04_ready_witness.sh` 的同值 "
     "都是**那一代的真值**, 由 WANT 钉死; 改它反而毁掉该轮取证 —— 登记为 2026-10-13 阶段 ⑨ (0x24) 的新命中)"),
    (r"^_proj_10g/notes/p9_board_0x23_20261011/",
     "旧位流读法: P9 板级首测 0x23 现场 (烧的是 **0x23** 归档位流 + **0x21 MM 对照臂**) ⇒ "
     "`burn_0x23.sh` 的 `WANT=066a3923…3126`/`EXPBID=0x00000023`、`burn_0x21_ab.sh` 的 "
     "`WANT=fbb6fca8…892c`/`EXPBID=0x00000021`、`_tools/run_arm.sh` 的 `BID=${BID:-0x00000023}`、"
     "`_tools/run_arm_mm.sh` 的 `0x00000021`、`_tools/final_state.sh` 的 `EXPECT_BID=0x00000023` "
     "都是**那一代的真值**, 由 WANT sha 钉死; 改它反而毁掉该轮取证)"),
    (r"^_proj_10g/notes/p9_final_board_20261012/",
     "旧位流读法: 收尾板级轮现场 (2026-10-12; `_tools/{step0,final_state,aux_udp_probe2,t1_remote_step,"
     "t2_remote_step}.sh` 的 `EXPECT_BID=0x00000023` / NW=71 都是**那一代的真值** — 该轮烧的即 0x23)"),
    (r"^_proj_10g/notes/p9_hostread_20261013/",
     "旧位流读法: 宿主读取轮现场 (2026-10-13; `_tools/run_win_hw.sh` 的 "
     "`EXPECT_BID=${EXPECT_BID:-0x00000023}` 与 `--bid $EXPECT_BID` 用的都是**那一代的真值**)"),
    (r"^_proj_10g/notes/p9_rate_20261013/",
     "旧位流读法: 速率轮现场 (2026-10-13; `_tools/{run_win,run_multi}.sh` 的 "
     "`EXPECT_BID=${EXPECT_BID:-0x00000023}` / `final_state_rt.sh` 的同值 = **那一代的真值**)"),
    (r"^_proj_10g/notes/p9_uram_20261013/diag_p9b3d/tb_p6e_pcie_wrapper\\.v$",
     "诊断副本: URAM 修正轮的 `P9-B-3d` 诊断件 (注入 700→20000; 内含当时的 `BUILD_ID=0x23` 期望) —— "
     "一次性证据副本, 编过就丢 (证据 = 同目录 `DIAG_stdout.txt`), ⛔ 改它 = 伪造那轮诊断 ⇒ 只登记不动"),
    (r"^_proj_10g/notes/p9_uram_20261013/",
     "现役: 上一轮 (URAM 实施+修正) 的工作目录 (报告/复核/门读数; 含各代 BID 字符串)"),
    (r"^_proj_10g/notes/p9_build_0x24/",
     "现役: 本轮 (阶段 ⑨ = 0x24) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_build_0x23/",""", "⑤ ALLOW 追加 9 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
