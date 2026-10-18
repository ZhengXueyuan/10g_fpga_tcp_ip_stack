# bizwinsrc.f -- DECLARED compile file list for the biz_win gate (#21, P11 P1 fix round).
#   gate bat : _proj_10g/notes/p7b_biz_win/run_gate_biz_win_check.bat
#   config   : none (unit gate: axi_regs + tb_biz_win only; no wrapper compile)
#
#   SCOPE OF THIS MANIFEST (read before quoting it):
#     * This gate has TWO halves:
#         A. check_window.py -- static text check of board/wrapper_p4.v's
#            `snap_dout_all` assembly. It does NOT compile; it reads the file as
#            text. Its own negative controls (--mutate drop|swap|declpatho) are
#            run inside the gate and must be red (RC=1).
#         B. run_tb_biz_win.bat -- xsim unit gate over _proj_pcie/rtl/axi_regs.v
#            with _proj_10g/notes/p7b_biz_win/tb_biz_win.v (NW=83).
#     * p4gate.py manifestcheck compares this list with the .v tokens appearing
#       LITERALLY on the gate bat's xvlog row. The two files below are that set.
#   Entries are repo-relative; manifestcheck asserts this list == the literal
#   list in the gate .bat.
_proj_pcie/rtl/axi_regs.v
_proj_10g/notes/p7b_biz_win/tb_biz_win.v
