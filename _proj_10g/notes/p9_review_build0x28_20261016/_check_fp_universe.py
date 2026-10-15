import io, sys, hashlib, os, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g" + "\\"
fp = base + r"sim\p4sim\P4_MATRIX_FINGERPRINT_20261015_234333_after.txt"

records = []
for line in io.open(fp, "r", encoding="ascii", errors="replace"):
    if not line.startswith("SHA256 "):
        continue
    p = line.split()
    h, rel, sz, mt = p[1], p[2], int(p[3]), int(p[4])
    records.append((rel, h, sz, mt))
print("records:", len(records))

# digest content-v1 (all): sorted "<h>  <rel>\n"
lines_a = sorted("%s  %s\n" % (h, rel) for rel, h, sz, mt in records)
da = hashlib.sha256()
for ln in lines_a:
    da.update(ln.encode("ascii"))
print("content-v1 DIGEST_ALL =", da.hexdigest())
print("   claimed stored    = 92510c517db9f98e2750d7e5f482ea2841fce57ee95afece3a5a7dcd8d8663df")
print("   claimed content   = af08f8eef8866a510152d5f1205bae6c62a7a49ccc3e8e15a30bb6a97838eb34")

# pre-content-v1 variant guesses
for name, fmt in [("h rel sz mt", "%s  %s  %d  %d\n"),
                  ("h rel sz", "%s  %s  %d\n")]:
    s = sorted(fmt % (h, rel, sz, mt) if name.endswith("mt") else fmt % (h, rel, sz)
               for rel, h, sz, mt in records)
    d = hashlib.sha256()
    for ln in s:
        d.update(ln.encode("ascii"))
    print("variant[%s] = %s" % (name, d.hexdigest()))

# check the 20 read-side files and p6e TB membership
readside = """_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh
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
universe = set(rel for rel, h, sz, mt in records)
hits = [f for f in readside if f in universe]
print("read-side files IN fingerprint universe:", len(hits))
for f in hits:
    print("  IN:", f)
# any sim/p6e_pcie at all?
p6e = sorted(f for f in universe if f.startswith("sim/p6e_pcie/"))
print("sim/p6e_pcie/* in universe:", p6e)
# what sim/ entries exist?
sims = sorted(f for f in universe if f.startswith("sim/"))
print("sim/* count in universe:", len(sims))
for s in sims[:40]:
    print("  ", s)
