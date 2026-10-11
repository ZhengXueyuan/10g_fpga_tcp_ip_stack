@echo off
REM run_synth.bat -- P9 (AXIS) synthesis checkpoint (synth-only; no impl; no bitstream)
REM   usage: run_synth.bat p9axis
REM   -tclargs must be the LAST vivado argument (it greedily eats later flags).
REM   gate: stdout must contain P9SYNTH_DONE + P9SYNTH_WNS + P9SYNTH_XDMA_VERDICT = OK
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
cd /d %~dp0
set ARM=%1
if "%ARM%"=="" set ARM=p9axis
call %XV%\vivado.bat -mode batch -source synth_only_ku5p.tcl -nojournal -nolog -tclargs %ARM% > synth_stdout_%ARM%.txt 2>&1
findstr /C:"P9SYNTH_DONE" synth_stdout_%ARM%.txt >NUL || (echo P9SYNTH-FAIL & exit /b 1)
findstr /C:"P9SYNTH_WNS" synth_stdout_%ARM%.txt >NUL || (echo P9SYNTH-NO-WNS & exit /b 1)
findstr /C:"P9SYNTH_XDMA_VERDICT = OK" synth_stdout_%ARM%.txt >NUL || (echo P9SYNTH-XDMA-CFG-FAIL & exit /b 1)
findstr /C:"P9SYNTH_WNS" /C:"P9SYNTH_WHS" /C:"P9SYNTH_XDMA_VERDICT" /C:"P9SYNTH_XDMA_RB_MISMATCH_N" /C:"P9SYNTH_XDMA_GEN_BAD_N" /C:"P9SYNTH_AXIS_PINS" /C:"P9SYNTH_MIR_PINS" /C:"P9SYNTH_NFILES" synth_stdout_%ARM%.txt
exit /b 0
