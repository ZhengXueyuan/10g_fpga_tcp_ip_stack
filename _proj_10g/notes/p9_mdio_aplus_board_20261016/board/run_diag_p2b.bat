@echo off
REM p9_mdio_aplus_board_20261016 / clean frame-duration sample (P2b), busy-first idiom.
REM -tclargs goes LAST (greedy: it would swallow -nojournal/-nolog otherwise).
cd /d D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_aplus_board_20261016\board
call C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat -mode batch -source diag_p2b.tcl -nojournal -nolog -tclargs D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_aplus_board_20261016\burn\mdio_vio_top_divbad.bit
exit /b %errorlevel%
