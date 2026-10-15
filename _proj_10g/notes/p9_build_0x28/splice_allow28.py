#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 ⑬ 的 ALLOW 追加 5 条 (B 面搜索结果分类; 逐件现读核过 §PRESCAN_0x28.txt 的未登记清单)。
⛔ 幂等。锚点唯一命中。
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
s = io.open(P, encoding="utf-8", newline="").read()
if "p9_board_0x27_k0_20261015" in s:
    print("ALREADY SPLICED (ALLOW 28 已在文件里) => 不动")
    sys.exit(0)

ANCHOR = """    (r"^_proj_10g/notes/p9_build_0x28/",
"""
ADD = """    (r"^_proj_10g/notes/p9_board_0x27_k0_20261015/",
     "旧位流读法: K0 换流门板级轮现场 (2026-10-15; 负臂烧 **0x24** 归档位流 `WANT=e3b07957…f1db`、"
     "K0 臂烧 **0x27** 归档位流 `WANT=5c17b14f…3385` ⇒ `burn/*.sh` 的 `EXPBID`/`NW=71` 与 "
     "`k0_arm.sh`/`env/read_final_state.sh` 的 `EXPECT_BID=0x00000027` 都是**那一代的真值**, "
     "由 WANT sha 钉死; 改它反而毁掉该轮取证 —— 登记为 2026-10-15 阶段 ⑬ (0x28) 的新命中)"),
    (r"^_proj_10g/notes/p9_board_rfcseq_20261015/",
     "旧位流读法: RFC seq 注入 A/B 板级轮现场 (2026-10-15; 三臂 P27/N25/P26 = **0x27/0x25/0x26** "
     "归档位流, `EXPECT_BID` 逐臂由环境变量注入 ⇒ `rfcseq_arm.sh`/`burn_arm.sh`/`read_final_state.sh` "
     "里的 `0x00000025/26/27` 与 `NW=71` 都是**那三代的真值**, 由被烧的归档位流钉死)"),
    (r"^_proj_10g/notes/p9_mdio_board_20261015/",
     "旧位流读法: mdio 板级轮现场 (2026-10-15; 烧 **0x27** + mdio 位流 `4c74c219…` ⇒ "
     "`burn/burn_arm.sh` 与 `board/read_final_state.sh` 的 `EXPBID=0x00000027`/`NW=71` = "
     "**那一代的真值**, 由 WANT sha 钉死)"),
    (r"^_proj_10g/notes/p9_simfill_20261015/",
     "快照副本: sim 补测轮 (2026-10-15) 的 B_f3_n2 臂 —— `B_f3_n2/src/{wrapper_p4_resync0.v,"
     "tb_p6e_pcie_counters.FROZEN.v,tb_p6e_pcie_counters.NOSOP.v}` 由 `mk_wr_n2.py`/`mk_tb_nosop.py` "
     "**从 0x27 代现读生成**的冻结对照件 (其 `0x00000027`/`0x14C`/NW=71 = 生成时刻的真值); "
     "⛔ 改它 = 伪造那次对照 ⇒ 只登记不动"),
    (r"^sim/f3_resync/",
     "快照副本: F-3 N-2 臂的工作副本 (frozen/wr_on/wr_off 三目录; `wrapper_p4*.v` 与 TB 副本 = "
     "N2 臂生成/冻结件, 其身份/几何 = 生成时刻那一代; ⛔ 本仓纪律: `sim/f3_resync/**` 禁碰 ⇒ "
     "只登记不动) —— 登记为 2026-10-15 阶段 ⑬ (0x28) 的新命中"),
"""
assert s.count(ANCHOR) == 1, "锚点命中 %d" % s.count(ANCHOR)
s = s.replace(ANCHOR, ADD + ANCHOR)
io.open(P, "w", encoding="utf-8", newline="").write(s)
print("ALLOW 追加 5 条 DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
