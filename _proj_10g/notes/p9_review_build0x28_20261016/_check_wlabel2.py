import sys, re
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g"
for p, label in [(r"_proj_pcie\p6e_snap_check.sh", "WLABEL(p6e_snap_check)"),
                 (r"_proj_pcie\p7b_gate4_negctrl.sh", "V=(negctrl)")]:
    txt = open(base + "\\" + p, encoding="utf-8", errors="replace").read()
    if label.startswith("WLABEL"):
        m = re.search(r"WLABEL=\(([\s\S]*?)\r?\n\)", txt)
        if not m:
            print(label, "no match"); continue
        body = m.group(1)
        q = body.count('"')
        print(label, "quote-count:", q, "=> entries:", q // 2)
        # show first/last entries
        ents = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
        print("  first:", ents[0][:60])
        print("  idx70:", ents[70][:70] if len(ents) > 70 else None)
        print("  last:", ents[-1][:80])
        print("  total:", len(ents))
    else:
        # p7b_gate4_negctrl.sh: V=( a b c ...) possibly multi-line; count tokens
        m = re.search(r"\n\s*V=\(([\s\S]*?)\r?\n\)", txt)
        if not m:
            print(label, "no match"); continue
        toks = m.group(1).split()
        print(label, "tokens:", len(toks), "| line preview:", m.group(1).strip()[:200])
