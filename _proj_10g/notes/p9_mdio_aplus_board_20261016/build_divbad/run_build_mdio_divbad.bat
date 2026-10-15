@echo off
REM p9_mdio_aplus_board_20261016 / E8 variant build (pj_mdio_divbad + synth generic DIV=65537).
cd /d D:\repo\XCKU5PMini\_proj_mdio
call C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source build_mdio_divbad.tcl -nojournal -nolog
exit /b %errorlevel%
