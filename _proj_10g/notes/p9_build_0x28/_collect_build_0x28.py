#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建 0x28 后: 把位流/报告/读数收进轮目录 (照 0x27 轮口径)。只读源 + 写轮目录。"""
import hashlib
import io
import os
import shutil
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
IMPL = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "impl_1")
SYN = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "synth_1")
BRD = os.path.join(HERE, "board_rpt")
os.makedirs(BRD, exist_ok=True)

IMPL_FILES = ["wrapper_p4_timing_summary_routed.rpt", "wrapper_p4_utilization_placed.rpt",
              "wrapper_p4_clock_utilization_routed.rpt", "wrapper_p4_control_sets_placed.rpt",
              "wrapper_p4_drc_routed.rpt", "wrapper_p4_power_routed.rpt",
              "wrapper_p4_route_status.rpt", "runme.log"]
SYN_FILES = ["wrapper_p4_utilization_synth.rpt"]
BOARD_FILES = ["p7b_ku5p_timing.rpt", "p7b_ku5p_util.rpt", "p7b_ku5p_drc.rpt",
               "p7b_ku5p_clkinteract.rpt", "p7b_ku5p_stdout.txt",
               "p7b_ku5p_xdma_cfg_post_gen.txt"]

n = 0
for f in IMPL_FILES:
    s = os.path.join(IMPL, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f if f != "runme.log" else "runme_impl_1.log"))
        n += 1
for f in SYN_FILES:
    s = os.path.join(SYN, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))
        n += 1
for f in BOARD_FILES:
    s = os.path.join(R, "board", f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))
        n += 1
print("board_rpt files = %d" % len(os.listdir(BRD)))

bit = os.path.join(IMPL, "wrapper_p4.bit")
dcp = os.path.join(IMPL, "wrapper_p4_routed.dcp")
shutil.copy2(bit, os.path.join(HERE, "wrapper_p4.bit"))
shutil.copy2(dcp, os.path.join(HERE, "wrapper_p4_routed.dcp"))
h = hashlib.sha256(open(bit, "rb").read()).hexdigest()
sz = os.path.getsize(bit)
io.open(os.path.join(HERE, "BIT_SHA256_BID28.txt"), "w", encoding="ascii", newline="\n").write(
    "%s  wrapper_p4.bit\nsize = %d\n" % (h, sz))
print("bit sha256 = %s  size = %d" % (h, sz))

# routed dcp 从归档副本拿 (impl_1 的 dcp 也拷了, 两者应一致)
arc = None
for d in sorted(os.listdir(os.path.join(R, "_proj_10g", "notes", "p7b_build_archive"))):
    p = os.path.join(R, "_proj_10g", "notes", "p7b_build_archive", d, "wrapper_p4_routed.dcp")
    if os.path.exists(p) and os.path.getmtime(p) > os.path.getmtime(os.path.join(HERE, "_collect_build_0x28.py")) - 86400:
        arc = p
print("archive dcp candidate = %s" % arc)
