import sys, os, io
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g" + "\\"
files = """_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh
_proj_10g/notes/p7b_affinity/j6_r6fix.sh
_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh
_proj_10g/notes/p7b_biz_win/check_window.py
_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat
_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat
_proj_10g/notes/p7b_biz_win/tb_biz_win.v
_proj_10g/notes/p7b_gate4_3/final_state.sh
_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py
_proj_10g/p7b_chain/sim/tb_p7b_chain.v
_proj_pcie/p6e_snap_check.sh
_proj_pcie/p6e_snap_selftest_fix2.sh
_proj_pcie/p7b_biz/p7b_snap.sh
_proj_pcie/p7b_gate4_accept.sh
_proj_pcie/p7b_gate4_livefake.sh
_proj_pcie/p7b_gate4_negctrl.sh
_proj_pcie/p7b_gate4_selftest.sh
sim/p5wu_p1p2/run_xvlog_wrapper63.bat
sim/p6e_pcie/tb_p6e_pcie_counters.v
sim/p6e_pcie/tb_p6e_pcie_wrapper.v""".split("\n")

active_total = 0
for rel in files:
    p = base + rel.replace("/", os.sep)
    for i, line in enumerate(io.open(p, encoding="utf-8", errors="replace"), 1):
        if "00000027" not in line and "0x00000027" not in line:
            continue
        idx = line.find("0x00000027")
        if idx < 0:
            idx = line.find("00000027")
        # comment detection: nearest preceding comment token
        pre = line[:idx]
        is_comment = False
        for tok in ("#", "//", "REM "):
            j = pre.find(tok)
            if j >= 0 and (tok != "#" or "{" not in pre[j:]):
                # crude: treat as comment if comment token appears before the value
                is_comment = True
        s = line.strip()
        if s.startswith("#") or s.startswith("//") or s.upper().startswith("REM"):
            is_comment = True
        if not is_comment:
            active_total += 1
            print("ACTIVE? %s:%d | %s" % (rel, i, s[:160]))
print("active-looking lines with 0x00000027:", active_total)
