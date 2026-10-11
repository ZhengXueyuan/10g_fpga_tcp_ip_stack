@echo off
REM run_q.bat - 0x23 targeted timing query runner (ASCII + CRLF only)
set VV=C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
set D=D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x23
call "%VV%" -mode batch -nojournal -nolog -source "%D%\q_0x23.tcl" -tclargs "%D%\wrapper_p4_routed.dcp" "%D%\query_out" > "%D%\q_stdout.txt" 2>&1
echo QUERY_EXIT=%ERRORLEVEL%
