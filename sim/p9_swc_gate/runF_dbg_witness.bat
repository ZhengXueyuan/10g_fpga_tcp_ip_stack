@echo off
setlocal
REM runF_dbg_witness.bat -- R5 one-off P9_DBG trace run (F-family config), separate dir.
REM   Does NOT touch the frozen 8-run gate dirs; compiles the same frozen sources.
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
cd /d "%~dp0runF_dbg_witness"
if exist xsim.dir rmdir /s /q xsim.dir
echo RSRC=..\..\..\rtl\app_pattern.v DEFS=-d P9_SWC_ARM -d P9_EXP_FIXED -d P9_DBG > srcpath.log
call "%XV%\xvlog.bat" -work xil_defaultlib -d P9_SWC_ARM -d P9_EXP_FIXED -d P9_DBG "..\..\..\rtl\app_pattern.v" "..\tb_p9_swc.v" > xv_out.log 2>&1 || (type xv_out.log & exit /b 1)
call "%XV%\xelab.bat" -debug typical xil_defaultlib.tb_p9_swc -s tbswc -log xe.log > xe_out.log 2>&1 || (type xe_out.log & exit /b 1)
call "%XV%\xsim.bat" tbswc -runall -log xs.log > xs_out.log 2>&1
findstr /C:"TB_P9_SWC: OK" xs.log || (echo TB-NOT-OK & exit /b 1)
echo DBG-WITNESS-OK
exit /b 0
