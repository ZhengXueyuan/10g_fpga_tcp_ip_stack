#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""输入哈希清单 (构建轮 0x26; 照 0x25 轮同名件的用途)。
用法: mk_input_hashes.py gates|build
  gates: 门相位前的完整性面 (rtl / board / sim/p6e_pcie / sim/f3_resync / sim/p4gates / _proj_pcie/rtl / 读侧工具)
  build: 构建相位前的完整性面 (rtl/*.v + board/* + hls verilog + _proj_pcie/rtl + _proj_10g/p7b_mac/rtl)
只读; 输出到 stdout (调用方重定向)。
"""
import glob, hashlib, os, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = r"D:\repo\XCKU5PMini\udp_hls_10g"
MODE = sys.argv[1] if len(sys.argv) > 1 else "gates"

GATES_GLOBS = [
    "rtl/*.v",
    "board/*",
    "sim/p6e_pcie/*",
    "sim/f3_resync/*", "sim/f3_resync/mut/*",
    "sim/p4gates/*.py", "sim/p4gates/*.bat", "sim/p4gates/*.f", "sim/p4gates/paths.txt",
    "_proj_pcie/rtl/*.v",
    "_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py",
]
BUILD_GLOBS = [
    "rtl/*.v",
    "board/*.v", "board/*.tcl", "board/*.xdc", "board/*.bat",
    "hls/slowstack_prj/solution1/syn/verilog/*.v",
    "_proj_pcie/rtl/*.v",
    "_proj_10g/p7b_mac/rtl/*.v",
]

globs = GATES_GLOBS if MODE == "gates" else BUILD_GLOBS
files = []
for g in globs:
    for p in sorted(glob.glob(os.path.join(REPO, g.replace("/", os.sep)))):
        if os.path.isfile(p) and p not in files:
            files.append(p)
print("MODE=%s FILES=%d" % (MODE, len(files)))
for p in files:
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    print("%s  %s" % (h, os.path.relpath(p, REPO).replace(os.sep, "/")))
