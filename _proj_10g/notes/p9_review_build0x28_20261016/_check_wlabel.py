import sys, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
p = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_pcie\p6e_snap_check.sh"
txt = open(p, encoding="utf-8", errors="replace").read()
idx = txt.find("WLABEL")
print("first WLABEL at char", idx)
print(txt[idx:idx+300])
print("----")
# find the table assignment; count array entries by lines with leading ordinal or 'W'
m = re.search(r"WLABEL=\(([\s\S]*?)\n\)", txt)
if m:
    body = m.group(1)
    # count non-empty, non-comment lines
    n = 0
    for line in body.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        n += 1
    print("WLABEL non-comment lines:", n)
else:
    print("regex2 no match")
