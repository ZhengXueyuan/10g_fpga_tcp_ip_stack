#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P11 build 0x2D: collect build artifacts/readings into the round dir.
Reads build outputs + copies reports; writes only inside the round dir.
Adapted from _proj_10g/notes/p11_build_0x2C_20261018/build/_collect_build_0x2C.py
(adds the F-21 P7B_SNAP_TOP5_ positive-reading lines)."""
import glob
import hashlib
import io
import os
import re
import shutil
import sys
import datetime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))          # <round>/build
ROUND = os.path.dirname(HERE)
R = os.path.normpath(os.path.join(ROUND, "..", "..", ".."))
IMPL = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "impl_1")
SYN = os.path.join(R, "vivado_prj", "p7b_ku5p_prj.runs", "synth_1")
BRD = os.path.join(HERE, "board_rpt")
os.makedirs(BRD, exist_ok=True)

IMPL_FILES = ["wrapper_p4_timing_summary_routed.rpt", "wrapper_p4_utilization_placed.rpt",
              "wrapper_p4_clock_utilization_routed.rpt", "wrapper_p4_control_sets_placed.rpt",
              "wrapper_p4_drc_routed.rpt", "wrapper_p4_power_routed.rpt",
              "wrapper_p4_route_status.rpt", "runme.log"]
SYN_FILES = ["wrapper_p4_utilization_synth.rpt"]
BOARD_FILES = ["p7b_ku5p_stdout.txt", "p7b_ku5p_xdma_cfg_post_gen.txt"]
# These four are written ONLY after implementation. This build stopped at the
# post-synth gate => the files on disk are still the 0x2C build's (mtime 12:50).
# Copy them under a STALE_ prefix so nobody reads them as 0x2D readings.
STALE_IF_OLD = ["p7b_ku5p_timing.rpt", "p7b_ku5p_util.rpt", "p7b_ku5p_drc.rpt",
                "p7b_ku5p_clkinteract.rpt"]
BUILD_START = datetime.datetime(2026, 10, 18, 16, 2, 0)

for f in IMPL_FILES:
    s = os.path.join(IMPL, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f if f != "runme.log" else "runme_impl_1.log"))
for f in SYN_FILES:
    s = os.path.join(SYN, f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))
stale_note = []
for f in BOARD_FILES:
    s = os.path.join(R, "board", f)
    if os.path.exists(s):
        shutil.copy2(s, os.path.join(BRD, f))
for f in STALE_IF_OLD:
    s = os.path.join(R, "board", f)
    if not os.path.exists(s):
        continue
    mt = datetime.datetime.fromtimestamp(os.path.getmtime(s))
    if mt < BUILD_START:
        shutil.copy2(s, os.path.join(BRD, "STALE_0x2C_" + f))
        stale_note.append("%s mtime=%s -> STALE_0x2C_%s (NOT a 0x2D reading)" % (f, mt, f))
    else:
        shutil.copy2(s, os.path.join(BRD, f))
print("board_rpt files = %d" % len(os.listdir(BRD)))
for ln in stale_note:
    print("STALE: " + ln)

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

stdout_p = os.path.join(R, "board", "p7b_ku5p_stdout.txt")
console_p = os.path.join(HERE, "BUILD_CONSOLE.txt")
so = io.open(stdout_p, encoding="utf-8", errors="replace").read() if os.path.exists(stdout_p) else ""
co = io.open(console_p, encoding="utf-8", errors="replace").read() if os.path.exists(console_p) else ""
tsum_p = os.path.join(IMPL, "wrapper_p4_timing_summary_routed.rpt")
tsum = io.open(tsum_p, encoding="utf-8", errors="replace").read() if os.path.exists(tsum_p) else ""
drc_p = os.path.join(IMPL, "wrapper_p4_drc_routed.rpt")
drc = io.open(drc_p, encoding="utf-8", errors="replace").read() if os.path.exists(drc_p) else ""
rts_p = os.path.join(IMPL, "wrapper_p4_route_status.rpt")
rts = io.open(rts_p, encoding="utf-8", errors="replace").read() if os.path.exists(rts_p) else ""
util_p = os.path.join(IMPL, "wrapper_p4_utilization_placed.rpt")
util = io.open(util_p, encoding="utf-8", errors="replace").read() if os.path.exists(util_p) else ""
uutil_p = os.path.join(SYN, "wrapper_p4_utilization_synth.rpt")
uutil = io.open(uutil_p, encoding="utf-8", errors="replace").read() if os.path.exists(uutil_p) else ""
clk_p = os.path.join(R, "board", "p7b_ku5p_clkinteract.rpt")
if os.path.exists(clk_p) and datetime.datetime.fromtimestamp(os.path.getmtime(clk_p)) >= BUILD_START:
    clk = io.open(clk_p, encoding="utf-8", errors="replace").read()
else:
    clk = ""  # file on disk is the 0x2C build's; impl never ran in 0x2D

out = []
out.append("# P11 build 0x2D readings (collected %s)" %
           datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
out.append("# --- IMPL STATUS ---")
if os.path.isdir(IMPL):
    impl_files = sorted(os.listdir(IMPL))
else:
    impl_files = []
out.append("impl_1 files = %d" % len(impl_files))
out.append("build stopped at P7B_SNAP_TOP5_CDC gate (post-synth) => implementation never launched")
for ln in stale_note:
    out.append("STALE: " + ln)
out.append("# --- console ---")
for ln in co.splitlines():
    if ln.startswith(("ARCHIVE_", "BUILD_EXIT", "BITSTREAM-OK", "NO-BITSTREAM", "BUILD-GATE-FAIL",
                      "P7B-VERDICT", "DROPPED-CONSTRAINT-FAIL", "IMPLICIT-NET-FAIL",
                      "DRC-KEY-FAIL", "P7B-MODULE", "P7B-SNAP-TOP5")):
        out.append(ln)
out.append("# --- stdout keys ---")
for ln in so.splitlines():
    if ln.startswith(("P7B_VERILOG_DEFINE", "HLS_SRC_HASH", "HLS_NET_HASH",
                      "P7B_BLACKBOX_LOG_HITS", "P7B_MODULE_RESOLVED", "P7B_BLACKBOX_COUNT",
                      "P7B_WNS", "P7B_WHS", "P7B_WPWS", "P7B_BIT_EXISTS",
                      "P7B_VERDICT", "P7B_CONVERGED_AT_ROUND", "P7B_IS_LOCKED_POSTGEN",
                      "P7B_XDMA_VERDICT", "P7B_NFILES", "P7B DONE",
                      "P7B_SNAP_TOP5_SLOT", "P7B_SNAP_TOP5_FANOUT",
                      "P7B_SNAP_TOP5_SLOTS_OK")):
        out.append(ln)
# --- hard gate hits ---------------------------------------------------------
# Scan ONLY the synth log; if unavailable, board stdout minus '#' source echoes.
syn_log_p = os.path.join(SYN, "runme.log")
if os.path.exists(syn_log_p):
    hg_text = io.open(syn_log_p, encoding="utf-8", errors="replace").read()
    hg_src = "synth_1/runme.log"
else:
    hg_text = "\n".join(ln for ln in so.splitlines() if not ln.lstrip().startswith("#"))
    hg_src = "board stdout (lines starting with '#' excluded = source echo excluded)"
out.append("# --- hard gate hits (%s) ---" % hg_src)
for key in ("12-4739", "Synth 8-11241", "undeclared symbol",
            "VRFC 10-3091] actual bit length 1 differs from formal bit length",
            "VRFC 10-2989", "implicitly declared", "black box", "8-3491"):
    out.append("%s = %d" % (key, hg_text.lower().count(key.lower()) if key in ("black box",) else hg_text.count(key)))
out.append("# --- three failure endpoint classes (timing summary tail) ---")
if not tsum:
    out.append("NO IMPL TIMING SUMMARY (impl_1 never launched)")
tsl = tsum.splitlines()
for i, ln in enumerate(tsl):
    if "WNS(ns)" in ln:
        out.extend(tsl[i:i + 8])
        break
out.append("# --- Slack (VIOLATED) ---")
out.append("Slack (VIOLATED) lines = %d" % sum(1 for l in tsum.splitlines() if "Slack (VIOLATED)" in l))
out.append("All constraints met line = %s" % ("YES" if "All user specified timing constraints are met." in tsum else "NO"))
out.append("# --- DRC ---")
if not drc:
    out.append("NO IMPL DRC REPORT (impl_1 never launched)")
for ln in drc.splitlines():
    if "Checks found" in ln:
        out.append(ln.strip())
out.append("DRC Error rows = %d / Critical rows = %d"
           % (len(re.findall(r"\|\s+Error\s+\|", drc)), len(re.findall(r"\|\s+Critical\s+\|", drc))))
out.append("# --- route ---")
for ln in rts.splitlines():
    if "routing errors" in ln or "fully routed" in ln:
        out.append(ln.strip())
out.append("# --- resources (placed / synth) ---")
for src, tag in ((util, "placed"), (uutil, "synth")):
    for ln in src.splitlines():
        if re.search(r"CLB LUTs|CLB Registers|Block RAM Tile|URAM|DSP|GTYE4", ln) and "|" in ln:
            out.append("%s: %s" % (tag, ln.strip()))
out.append("# --- clock interaction: rx_clk_out / gtrefclk / async ---")
seen = 0
for ln in clk.splitlines():
    if re.search(r"rx_clk_out|gtrefclk|gtwiz|Asynchronous|Timed|Untimed", ln):
        out.append(ln.rstrip())
        seen += 1
        if seen >= 50:
            out.append("...(truncated)")
            break
out.append("# --- F-21 post-place gate positive readings ---")
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
