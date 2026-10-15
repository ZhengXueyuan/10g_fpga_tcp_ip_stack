@echo off
REM p9_mdio_board_20261015 / run_probe_mdio_v2.bat -- VIO arm driver (no programming here).
REM -tclargs goes LAST (greedy: it would swallow -nojournal/-nolog otherwise).
cd /d D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_board_20261015\board
call C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source probe_mdio_v2.tcl -nojournal -nolog -tclargs D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_board_20261015\board\artifacts\mdio_vio_top.bit
exit /b %errorlevel%
