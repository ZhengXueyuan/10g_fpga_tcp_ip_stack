#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P11 build 0x2D retry: collect build artifacts/readings into retry/build.
Read-only w.r.t. the source tree; writes only inside retry/."""
import glob
import hashlib
import io
import os
import re
import shutil
import sys
import datetime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))          # <round>/retry/build
RETRY = os.path.dirname(HERE)
R = os.path.normpath(os.path.join(RETRY, "..", "..", "..", ".."))
IMPL = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "impl_1")
SYN = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "synth_1")
BRD = os.path.join(HERE, "board_rpt")
os.makedirs(BRD, exist_ok=True)

IMPL_FILES = ["wrapper_p4_timing_summary_routed.rpt", "wrapper_p4_utilization_placed.rpt",
              "wrapper_p4_clock_utilization_routed.rpt", "wrapper_p4_control_sets_placed.rpt",
              "wrapper_p4_drc_routed.rpt", "wrapper_p4_power_routed.rpt",
              "wrapper_p4_route_status.rpt", "wrapper_p4_methodology_drc_routed.rpt",
              "runme.log"]
SYN_FILES = ["wrapper_p4_utilization_synth.rpt", "wrapper_p4.dcp"]
BOARD_FILES = ["p7b_ku5p_stdout.txt", "p7b_ku5p_timing.rpt", "p7b_ku5p_util.rpt",
               "p7b_ku5p_drc.rpt", "p7b_ku5p_clkinteract.rpt"]

for f in IMPL_FILES:
    s = os.path.join(IMPL, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f if f != "runme.log" else "runme_impl_1.log"))
for f in SYN_FILES:
    s = os.path.join(SYN, f)
    if os.path.exists(s):
        dst = os.path.join(BRD, f if f != "wrapper_p4.dcp" else "wrapper_p4_synth.dcp")
        if os.path.getsize(s) < 200 * 1024 * 1024:
            shutil.copy2(s, dst)
for f in BOARD_FILES:
    s = os.path.join(R, "board", f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))

bit = os.path.join(IMPL, "wrapper_p4.bit")
dcp = os.path.join(IMPL, "wrapper_p4_routed.dcp")
if os.path.exists(bit):
    shutil.copy2(bit, os.path.join(HERE, "wrapper_p4.bit"))
    bh = open(bit, "rb").read()
    h = hashlib.sha256(bh).hexdigest()
    sz = len(bh)
    m = re.search(rb"SW_CRC=([0-9a-fA-F]+)", bh[:400])
    swcrc = m.group(1).decode() if m else "?"
    io.open(os.path.join(HERE, "BIT_SHA256_BID2D.txt"), "w", encoding="ascii", newline="\n").write(
        "%s  wrapper_p4.bit\nsize = %d\nSW_CRC=%s\n" % (h, sz, swcrc))
    print("P11BUILD0x2D bit sha256 = %s  size = %d  SW_CRC=%s" % (h, sz, swcrc))
else:
    print("NO BITSTREAM at %s" % bit)
    h, sz, swcrc = "MISSING", 0, "?"
if os.path.exists(dcp):
    shutil.copy2(dcp, os.path.join(HERE, "wrapper_p4_routed.dcp"))

def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else ""

stdout_p = os.path.join(R, "board", "p7b_ku5p_stdout.txt")
console_p = os.path.join(RETRY, "BUILD_CONSOLE.txt")
so = read(stdout_p)
co = read(console_p)
tsum = read(os.path.join(IMPL, "wrapper_p4_timing_summary_routed.rpt"))
drc = read(os.path.join(IMPL, "wrapper_p4_drc_routed.rpt"))
mdr = read(os.path.join(IMPL, "wrapper_p4_methodology_drc_routed.rpt"))
rts = read(os.path.join(IMPL, "wrapper_p4_route_status.rpt"))
util = read(os.path.join(IMPL, "wrapper_p4_utilization_placed.rpt"))
uutil = read(os.path.join(SYN, "wrapper_p4_utilization_synth.rpt"))
clk = read(os.path.join(R, "board", "p7b_ku5p_clkinteract.rpt"))
syn_log = read(os.path.join(SYN, "runme.log"))
impl_log = read(os.path.join(IMPL, "runme.log"))

out = []
out.append("# P11 build 0x2D retry readings (collected %s)" %
           datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
out.append("# --- build exit / status ---")
for ln in co.splitlines():
    if ln.startswith(("ARCHIVE_", "BUILD_EXIT", "BITSTREAM-OK", "NO-BITSTREAM", "BUILD-GATE-FAIL",
                      "P7B-VERDICT", "DROPPED-CONSTRAINT-FAIL", "IMPLICIT-NET-FAIL",
                      "DRC-KEY-FAIL", "P7B-MODULE", "P7B-SNAP-TOP5")):
        out.append("console: " + ln)
out.append("impl_1 files = %d" % (len(os.listdir(IMPL)) if os.path.isdir(IMPL) else 0))
for ln in impl_log.splitlines():
    if "write_bitstream completed successfully" in ln or "Exiting Vivado" in ln:
        out.append("impl: " + ln.strip())
out.append("# --- stdout keys ---")
for ln in so.splitlines():
    if ln.startswith(("P7B_VERILOG_DEFINE", "HLS_SRC_HASH", "HLS_NET_HASH",
                      "P7B_BLACKBOX_LOG_HITS", "P7B_MODULE_RESOLVED", "P7B_BLACKBOX_COUNT",
                      "P7B_WNS", "P7B_WHS", "P7B_WPWS", "P7B_BIT_EXISTS",
                      "P7B_VERDICT", "P7B_CONVERGED_AT_ROUND", "P7B_IS_LOCKED_POSTGEN",
                      "P7B_NFILES", "P7B DONE", "P7B_SNAP_TOP5_SLOT",
                      "P7B_SNAP_TOP5_FANOUT", "P7B_SNAP_TOP5_SLOTS_OK")):
        out.append(ln)
out.append("# --- hard gate hits (synth_1/runme.log) ---")
for key in ("12-4739", "Synth 8-11241", "undeclared symbol",
            "VRFC 10-3091] actual bit length 1 differs from formal bit length",
            "VRFC 10-2989", "implicitly declared", "black box", "8-3491"):
    n = syn_log.lower().count(key.lower()) if key in ("black box", "implicitly declared") else syn_log.count(key)
    out.append("%s = %d" % (key, n))
out.append("# --- Design Timing Summary (setup/hold/PW) ---")
tsl = tsum.splitlines()
for i, ln in enumerate(tsl):
    if ln.strip().startswith("WNS(ns)") and "TNS(ns)" in ln:
        out.extend(l.rstrip() for l in tsl[i:i + 3])
        break
out.append("timing_constraints_met_line = " +
           ("PRESENT(unmet)" if "Timing constraints are not met." in tsum else "no 'not met' line"))
out.append("Slack (VIOLATED) paths in report = %d" % sum(1 for l in tsl if "Slack (VIOLATED)" in l))
out.append("# --- per-clock-group failing rows (nonzero only) ---")
in_clock_table = False
for ln in tsl:
    if ln.strip().startswith("Clock") and "WNS(ns)" in ln:
        in_clock_table = True
        continue
    if in_clock_table:
        if ln.strip() == "":
            break
        if re.match(r"^\s*\S", ln) and re.search(r"\s-\d+\.\d+\s", ln):
            out.append("clock_row: " + ln.rstrip())
out.append("# --- worst violating setup path ---")
for i, ln in enumerate(tsl):
    if ln.startswith("Slack (VIOLATED)"):
        out.extend(l.rstrip() for l in tsl[i:i + 22])
        break
out.append("# --- DRC ---")
for ln in drc.splitlines():
    if "Checks found" in ln or "DRC Complete" in ln:
        out.append(ln.strip())
out.append("DRC Error rows = %d / Critical rows = %d / Warning rows = %d" % (
    len(re.findall(r"\|\s+Error\s+\|", drc)),
    len(re.findall(r"\|\s+Critical\s+\|", drc)),
    len(re.findall(r"\|\s+Warning\s+\|", drc))))
out.append("methodology_drc Error rows = %d" % len(re.findall(r"\|\s+Error\s+\|", mdr)))
out.append("# --- route ---")
for ln in rts.splitlines():
    if "routing errors" in ln or "fully routed" in ln or "Route Status" in ln:
        out.append(ln.strip())
out.append("# --- resources (placed / synth) ---")
for src, tag in ((util, "placed"), (uutil, "synth")):
    for ln in src.splitlines():
        if re.search(r"CLB LUTs|CLB Registers|Block RAM Tile|URAM|DSP|GTYE4|Bonded IOB", ln) and "|" in ln:
            out.append("%s: %s" % (tag, ln.strip()))
out.append("# --- clock interaction: summary lines ---")
for ln in clk.splitlines():
    if re.search(r"^\s*\d+\s*$|Total|Inter Clock|Async", ln):
        out.append("clk: " + ln.strip())
out.append("# --- F-21 post-synth gate readings ---")
for ln in so.splitlines():
    if ln.startswith("P7B_SNAP_TOP5_"):
        out.append(ln)
out.append("# --- bitstream ---")
out.append("%s  wrapper_p4.bit" % h)
out.append("size = %d" % sz)
out.append("SW_CRC=%s" % swcrc)
io.open(os.path.join(HERE, "READINGS_BID2D.txt"), "w", encoding="utf-8", newline="\n").write(
    "\n".join(out) + "\n")
print("READINGS_BID2D.txt written (%d lines)" % len(out))
