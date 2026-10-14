@echo off
REM run_q - targeted timing query (0x26 round; ASCII + CRLF only)
REM   copied from p9_build_0x24\run_q.bat: -nojournal/-nolog MUST precede -source
REM   (tclargs greedily swallows trailing switches).
set VV=C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
call "%VV%" -mode batch -nojournal -nolog -source "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x26\q_0x26.tcl" -tclargs "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x25\wrapper_p4_routed.dcp" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x26\query_out_x25" > "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x26\q_stdout_x25.txt" 2>&1
echo QUERY_EXIT=%ERRORLEVEL%
