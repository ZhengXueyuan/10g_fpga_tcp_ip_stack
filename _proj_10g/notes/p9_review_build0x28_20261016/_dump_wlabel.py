import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g"
p = base + r"\_proj_pcie\p6e_snap_check.sh"
txt = open(p, encoding="utf-8", errors="replace").read()
idx = txt.find("WLABEL=")
seg = txt[idx:idx+6000]
# print raw with line numbers to see ending
for i, line in enumerate(seg.splitlines()[:80]):
    print("%3d|%s" % (i, line[:120]))
