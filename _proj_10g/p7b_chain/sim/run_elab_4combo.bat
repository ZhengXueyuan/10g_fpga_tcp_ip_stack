@echo off
REM run_elab_4combo.bat -- P11/P1: FOUR-MACRO elaboration gate for wrapper_p4.
REM   Combos (P7B_10G x PCIE_OBS), with the board-constant macro set
REM   DEV_USP + APP_MODE + DP_156MHZ + P6B_SIM_CLKGEN + UDP_TX_OVL + TCP_TX_OVL:
REM     1) P7B_10G=1 PCIE_OBS=1   (board body; P7B_SIM_NOPCS stub)
REM     2) P7B_10G=0 PCIE_OBS=1
REM     3) P7B_10G=1 PCIE_OBS=0
REM     4) P7B_10G=0 PCIE_OBS=0   (default/single-domain path)
REM   Purpose: catch implicitly-declared nets / undeclared ch0 signals in the
REM   macro combinations that no standing gate compiles (FINDINGS mid-9).
REM   Each combo gets a private work dir (xsim.dir locks); xelab top = wrapper_p4.
setlocal
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
dir /b /s "%ROOT%\rtl\*.v" > elab_files.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> elab_files.f
echo %ROOT%\board\wrapper_p4.v >> elab_files.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v >> elab_files.f
echo %ROOT%\board\uart_dbg.v >> elab_files.f
echo %ROOT%\board\p7b_pcs_stub.v >> elab_files.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\crc32_64.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\mac_rx_10g.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\mac_tx_10g.v >> elab_files.f
echo %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v >> elab_files.f
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" > xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)

set "COMMON=-d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL"
set "FAILS=0"

call :one c1 1 1
call :one c2 0 1
call :one c3 1 0
call :one c4 0 0

echo ELAB_4COMBO_FAILS=%FAILS%
if not "%FAILS%"=="0" exit /b 1
echo ELAB_4COMBO_PASS
exit /b 0

:one
set "TAG=%~1"
set "P7B=%~2"
set "PCIE=%~3"
set "DEFS=%COMMON%"
if "%P7B%"=="1"  set "DEFS=%DEFS% -d P7B_10G -d P7B_SIM_NOPCS"
if "%PCIE%"=="1" set "DEFS=%DEFS% -d PCIE_OBS"
if exist "xsim_%TAG%" rmdir /s /q "xsim_%TAG%"
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% -i %ROOT%\rtl -i %ROOT%\board -f elab_files.f > xvlog_%TAG%.log 2>&1
if errorlevel 1 (echo [ELAB %TAG%] XVLOG_FAIL & type xvlog_%TAG%.log & set /a FAILS+=1 & exit /b 0)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_%TAG%.log >NUL && (echo [ELAB %TAG%] IMPLICIT-XVLOG & set /a FAILS+=1 & exit /b 0)
findstr /I /C:"ERROR" xvlog_%TAG%.log >NUL && (echo [ELAB %TAG%] XVLOG_ERROR & findstr /I /C:"ERROR" xvlog_%TAG%.log & set /a FAILS+=1 & exit /b 0)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s wrap_%TAG% -log xelab_%TAG%.log > NUL 2>&1
if errorlevel 1 (echo [ELAB %TAG%] XELAB_FAIL & type xelab_%TAG%.log & set /a FAILS+=1 & exit /b 0)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_%TAG%.log >NUL && (echo [ELAB %TAG%] IMPLICIT-XELAB & set /a FAILS+=1 & exit /b 0)
echo [ELAB %TAG%] P7B=%P7B% PCIE=%PCIE% OK
exit /b 0
