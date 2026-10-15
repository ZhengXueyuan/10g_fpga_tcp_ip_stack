@echo off
REM run_q_x28 - targeted timing query on the THIS generation (28 routed dcp); ASCII + CRLF only
REM   copied from p9_build_0x27\run_q_x27.bat: -nojournal/-nolog MUST precede -source
REM   (tclargs greedily swallows trailing switches).
set VV=C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
call "%VV%" -mode batch -nojournal -nolog -source "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x28\q_0x28.tcl" -tclargs "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x28\wrapper_p4_routed.dcp" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x28\query_out_x28" > "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x28\q_stdout_x28.txt" 2>&1
echo QUERY_EXIT=%ERRORLEVEL%
