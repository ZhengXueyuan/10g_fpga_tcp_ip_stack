@echo off
REM p9_mdio_board_20261015 / run_build_mdio.bat -- rebuild the VIO-driven MDIO probe.
REM NOTE: build_mdio.tcl does create_project -force, which wipes pj_mdio/ (archive is in notes).
cd /d D:\repo\XCKU5PMini\_proj_mdio
call C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source build_mdio.tcl -nojournal -nolog
exit /b %errorlevel%
