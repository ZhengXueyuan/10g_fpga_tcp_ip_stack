#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建 0x29 后: 位流/报告/读数收进轮目录 (照 0x28 轮 _collect_build_0x28.py 口径, 只读源+写轮目录)。"""
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))                 # .../p9_dissect_0x29_20261017/build
ROUND = os.path.dirname(HERE)
R = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
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

for f in IMPL_FILES:
    s = os.path.join(IMPL, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f if f != "runme.log" else "runme_impl_1.log"))
for f in SYN_FILES:
    s = os.path.join(SYN, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))
for f in BOARD_FILES:
    s = os.path.join(R, "board", f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))

bit = os.path.join(IMPL, "wrapper_p4.bit")
dcp = os.path.join(IMPL, "wrapper_p4_routed.dcp")
shutil.copy2(bit, os.path.join(HERE, "wrapper_p4.bit"))
shutil.copy2(dcp, os.path.join(HERE, "wrapper_p4_routed.dcp"))
bb = open(bit, "rb").read()
h = hashlib.sha256(bb).hexdigest()
sz = len(bb)
io.open(os.path.join(HERE, "BIT_SHA256_BID29.txt"), "w", encoding="ascii", newline="\n").write(
    "%s  wrapper_p4.bit\nsize = %d\n" % (h, sz))
print("# (build 0x29) bit sha256 = %s  size = %d" % (h, sz))

# SW_CRC: .bit 头里的 'e' 记录 (照 0x28 轮口径, 从 .bit 头逐字读)
m = re.search(rb"e\x00+([0-9a-fA-F]{8})", bb[:3000])
print("SW_CRC raw-header candidate = %s" % (m.group(1).decode() if m else "NOT-FOUND"))

# ---- 三类失败端点 (routed timing summary) ----
ts = os.path.join(BRD, "wrapper_p4_timing_summary_routed.rpt")
txt = open(ts, encoding="utf-8", errors="replace").read() if os.path.exists(ts) else ""
print("--- 三类失败端点 (routed timing summary) ---")
for key, pat in (("setup", r"Number of Failing Endpoints\s*:\s*(\d+)"),
                 ("hold", r"Number of Failing Endpoints\s*:\s*(\d+)")):
    pass
# 汇总表: 每个检查类别的 'Number of Failing Endpoints: N : total'
secs = re.findall(r"([A-Za-z0-9_ ]+)\n\s*WNS.*?\n\s*TNS.*?\n.*?Number of Failing Endpoints\s*:\s*(\d+)\s*:\s*(\d+)", txt)
if not secs:
    secs = [(k, a, b) for k, a, b in re.findall(
        r"^\s*(Setup|Hold|Pulse Width|Recovery|Removal|Max Delay|Min Delay)\b[\s\S]{0,400}?Number of Failing Endpoints\s*:\s*(\d+)\s*:\s*(\d+)",
        txt, re.M)]
for k, a, b in secs[:10]:
    print("  %-14s failing=%s / total=%s" % (k.strip(), a, b))
vio = txt.count("Slack (VIOLATED)")
print("  'Slack (VIOLATED)' 行数 = %d" % vio)
met = "All user specified timing constraints are met." in txt
print("  'All user specified timing constraints are met.' in file = %s" % met)

# ---- DRC / route ----
drc = os.path.join(BRD, "wrapper_p4_drc_routed.rpt")
dtxt = open(drc, encoding="utf-8", errors="replace").read() if os.path.exists(drc) else ""
print("--- DRC ---")
for line in dtxt.splitlines():
    if "Checks found" in line or "Error" == line.strip()[:5]:
        print("  " + line.strip()[:120])
rs = os.path.join(BRD, "wrapper_p4_route_status.rpt")
rtxt = open(rs, encoding="utf-8", errors="replace").read() if os.path.exists(rs) else ""
for line in rtxt.splitlines():
    if "routing errors" in line or "Nets with" in line:
        print("  ROUTE: " + line.strip())

# ---- 资源 ----
util = os.path.join(BRD, "wrapper_p4_utilization_placed.rpt")
utxt = open(util, encoding="utf-8", errors="replace").read() if os.path.exists(util) else ""
print("--- 资源 (placed) ---")
for line in utxt.splitlines():
    if re.match(r"\|\s*(CLB LUTs|CLB Registers|Block RAM Tile|URAM|DSPs|Bonded IOB|GTYE4_CHANNEL)", line):
        print("  " + re.sub(r"\s+", " ", line).strip())

# ---- XDMA 断言组 ----
bs = os.path.join(R, "board", "p7b_ku5p_stdout.txt")
btxt = open(bs, encoding="utf-8", errors="replace").read() if os.path.exists(bs) else ""
print("--- XDMA 断言组 (board stdout) ---")
for line in btxt.splitlines():
    if re.search(r"P7B_XDMA|P7B_VERDICT", line):
        print("  " + line.strip()[:160])

# ---- 构建输入哈希 (build 面) + 与 0x28 轮对照 ----
before28 = os.path.join(R, "_proj_10g", "notes", "p9_build_0x28", "BUILD_INPUT_HASHES.txt")
out29 = os.path.join(HERE, "BUILD_INPUT_HASHES_0x29.txt")
with open(out29, "w", encoding="utf-8", newline="\n") as fh:
    p = subprocess.run([sys.executable, os.path.join(HERE, "mk_input_hashes.py"), "build"],
                       stdout=fh, stderr=subprocess.STDOUT)
print("--- 构建输入哈希 (MODE=build) -> %s (rc=%d) ---" % (out29, p.returncode))
if os.path.exists(before28):
    a = dict(l.split("  ")[::-1] for l in open(before28, encoding="utf-8").read().splitlines() if "  " in l and not l.startswith("MODE="))
    b = dict(l.split("  ")[::-1] for l in open(out29, encoding="utf-8").read().splitlines() if "  " in l and not l.startswith("MODE="))
    diff = sorted(set(a) ^ set(b)) + sorted(k for k in set(a) & set(b) if a[k] != b[k])
    print("  vs 0x28 轮清单: 变化件数 = %d" % len(diff))
    for k in diff:
        print("    %s : %s -> %s" % (k, a.get(k, "-")[:16], b.get(k, "-")[:16]))
