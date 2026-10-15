@echo off
REM p9_mdio_aplus_board_20261016 / production build (E7 applied, default DIV=25).
REM NOTE: build_mdio.tcl does create_project -force, which wipes pj_mdio/ (archived in round).
cd /d D:\repo\XCKU5PMini\_proj_mdio
call C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source build_mdio.tcl -nojournal -nolog
exit /b %errorlevel%
