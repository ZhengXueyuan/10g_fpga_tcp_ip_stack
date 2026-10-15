import sys, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g" + "\\"

# 1) WLABEL in p6e_snap_check.sh
txt = open(base + r"_proj_pcie\p6e_snap_check.sh", encoding="utf-8", errors="replace").read()
i = txt.find("WLABEL=(")
j = txt.find(")\nfor (( i = 0", i)
if j < 0:
    j = txt.find(")\r\nfor (( i = 0", i)
body = txt[i + len("WLABEL=("):j]
q = body.count('"')
print("WLABEL region quotes:", q, "=> entries:", q // 2)

# 2) V table in p7b_gate4_negctrl.sh (fake board word table)
t2 = open(base + r"_proj_pcie\p7b_gate4_negctrl.sh", encoding="utf-8", errors="replace").read()
m = re.search(r"local -a V=\(([\s\S]*?)\r?\n\)", t2)
if not m:
    # try V=( directly
    i2 = t2.find("V=(")
    print("negctrl V=( at", i2)
    print(t2[i2:i2+500])
else:
    toks = m.group(1).split()
    print("negctrl V tokens:", len(toks))

# 3) check_window.py identity
t3 = open(base + r"_proj_10g\notes\p7b_biz_win\check_window.py", encoding="utf-8", errors="replace").read()
for name in ["nnew_top", "ntx", "nnew =", "nnew=", "NW-51", "NW - 51"]:
    for mm in re.finditer(re.escape(name), t3):
        s = t3.rfind("\n", 0, mm.start()) + 1
        e = t3.find("\n", mm.end())
        line = t3[s:e]
        print("%-10s | %s" % (name, line.strip()[:120]))
        break
