#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 run_q_x27.bat / run_q_x28.bat (ASCII + CRLF only)。"""
import io
import os

H = os.path.dirname(os.path.abspath(__file__))
R = r"D:\repo\XCKU5PMini\udp_hls_10g"

TMPL = """@echo off
REM run_q_x{gen} - targeted timing query on the {which} generation ({gen} routed dcp); ASCII + CRLF only
REM   copied from p9_build_0x27\\run_q_x27.bat: -nojournal/-nolog MUST precede -source
REM   (tclargs greedily swallows trailing switches).
set VV=C:\\AMDDesignTools\\2025.2\\Vivado\\bin\\vivado.bat
call "%VV%" -mode batch -nojournal -nolog -source "{root}\\_proj_10g\\notes\\p9_build_0x28\\q_0x28.tcl" -tclargs "{root}\\_proj_10g\\notes\\{dcpdir}\\wrapper_p4_routed.dcp" "{root}\\_proj_10g\\notes\\p9_build_0x28\\query_out_x{gen}" > "{root}\\_proj_10g\\notes\\p9_build_0x28\\q_stdout_x{gen}.txt" 2>&1
echo QUERY_EXIT=%ERRORLEVEL%
"""

for gen, which, dcpdir in (("27", "PREVIOUS", "p9_build_0x27"), ("28", "THIS", "p9_build_0x28")):
    s = TMPL.format(gen=gen, which=which, root=R, dcpdir=dcpdir)
    p = os.path.join(H, "run_q_x%s.bat" % gen)
    io.open(p, "w", encoding="ascii", newline="\r\n").write(s)
    d = io.open(p, "rb").read()
    print("wrote run_q_x%s.bat  CRLF=%d bareLF=%d nonascii=%d"
          % (gen, d.count(b"\r\n"), d.count(b"\n") - d.count(b"\r\n"),
             sum(1 for b in d if b > 127)))
