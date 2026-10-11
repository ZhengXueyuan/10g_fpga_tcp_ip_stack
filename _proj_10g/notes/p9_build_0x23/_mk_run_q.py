#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""写 run_q.bat (ASCII + CRLF; 反斜杠用 B=chr(92) 拼, 避开转义坑)。"""
import os
B = chr(92)
D = B.join(["D:", "repo", "XCKU5PMini", "udp_hls_10g", "_proj_10g", "notes", "p9_build_0x23"])
VV = B.join(["C:", "AMDDesignTools", "2025.2", "Vivado", "bin", "vivado.bat"])
lines = [
    "@echo off",
    "REM run_q.bat - 0x23 targeted timing query runner (ASCII + CRLF only)",
    "set VV=" + VV,
    "set D=" + D,
    'call "%VV%" -mode batch -nojournal -nolog -source "%D%' + B + 'q_0x23.tcl" '
    '-tclargs "%D%' + B + 'wrapper_p4_routed.dcp" "%D%' + B + 'query_out" > "%D%' + B + 'q_stdout.txt" 2>&1',
    "echo QUERY_EXIT=%ERRORLEVEL%",
]
p = os.path.join(D, "run_q.bat")
with open(p, "w", newline="\r\n") as f:
    f.write("\n".join(lines) + "\n")
print("WROTE", p, os.path.getsize(p), "B")
