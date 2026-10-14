import re, sys, io
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
def parse(path):
    txt = io.open(path, encoding="utf-8", errors="replace").read()
    idx = [m.start() for m in re.finditer(r"(?m)^Slack \(", txt)]
    idx.append(len(txt))
    rows = []
    for k in range(len(idx) - 1):
        b = txt[idx[k]:idx[k+1]]
        m = re.search(r"Slack\s*\((\w+)\)\s*:\s*(-?[\d.]+)ns", b)
        sp = re.search(r"Source:\s*(\S+)", b)
        ep = re.search(r"Destination:\s*(\S+)", b)
        lvl = re.search(r"Logic Levels:\s*(\d+)", b)
        rows.append((float(m.group(2)), m.group(1), sp.group(1), ep.group(1), lvl.group(1) if lvl else "?", "u_tcp_rx" in b))
    return rows
for tag, path in (("0x25", r"query_out_x25/dp_top50.rpt"), ("0x26", r"query_out_x26/dp_top50.rpt")):
    rows = parse(path)
    print("==== %s: %d paths ====" % (tag, len(rows)))
    for i, (sl, st, sp, ep, lv, hasrx) in enumerate(rows, 1):
        mark = "  <== contains u_tcp_rx" if hasrx else ""
        print("#%02d slack=%.3f %s lvl=%s sp=%s ep=%s%s" % (i, sl, st, lv, sp, ep, mark))
