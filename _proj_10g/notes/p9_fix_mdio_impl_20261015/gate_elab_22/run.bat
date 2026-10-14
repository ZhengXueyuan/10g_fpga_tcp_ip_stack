@echo off
REM ===========================================================================
REM gate_elab_22 / run.bat -- elaboration-only gate for the 22-bit VIO probe.
REM Placed 2026-10-15 as part of round p9_fix_mdio_impl_20261015. NOT yet run
REM (that round was forbidden from invoking any Xilinx tool).
REM
REM Skeleton = notes/p7b_tool_debt_20261010/task2/elab_wrapper/run.bat (same
REM xvlog / xelab command lines).
REM
REM ONE deliberate deviation vs the skeleton -- the compile ORDER:
REM   skeleton : ... vio_0.v  vio_0_sim_netlist.v  ...
REM   here     : ... vio_0_sim_netlist.v  dbg_hub_sim_netlist.v  glbl.v  vio_0.v
REM WHY: the skeleton's captured xvlog log shows
REM   WARNING: [VRFC 10-3609] overwriting previous definition of module 'vio_0'
REM   [...elab_wrapper\vio_0_sim_netlist.v:18]
REM i.e. the LATER definition wins, so the frozen 20-bit IP netlist -- not the
REM stub -- is what xelab elaborated (corroborated by the same run compiling
REM unisims LUT6 / FDRE_default / GND, which exist only inside that netlist).
REM Patching only the stub would never change the declared width, and the
REM 22-bit design would always trip VRFC 10-3091. Compiling the patched 22-bit
REM stub LAST makes the stub the effective definition. Full argument, expected
REM log lines and coverage boundaries: GATE_NOTES.md in this directory.
REM
REM Outputs: xvlog.stdout.txt / xelab.log / elab_rc.txt, then the hard verdict
REM from check_elab.bat (GATE_PASS / GATE_FAIL; its exit code is propagated).
REM ===========================================================================
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin

call "%XV%\xvlog.bat" -work work mdio_master.v mdio_vio_top.v vio_0_sim_netlist.v dbg_hub_sim_netlist.v C:/AMDDesignTools/2025.2/data/verilog/src/glbl.v vio_0.v > xvlog.stdout.txt 2>&1
if errorlevel 1 (echo XVLOG_FAIL & type xvlog.stdout.txt & exit /b 1)

call "%XV%\xelab.bat" -L unisims_ver work.mdio_vio_top work.glbl -s top_elab -log xelab.log > NUL 2>&1
set ELABRC=%errorlevel%
> elab_rc.txt echo %ELABRC%
echo XELAB_RC=%ELABRC%
type xelab.log

call "%~dp0check_elab.bat"
exit /b %errorlevel%
