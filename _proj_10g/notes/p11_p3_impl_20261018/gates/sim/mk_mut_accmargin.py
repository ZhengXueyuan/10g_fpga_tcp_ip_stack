#!/usr/bin/env python3
"""H-3 negative control: port1 ACC_MARGIN 改回共用的 acc_margin_eff."""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]
src = (root / "board" / "wrapper_p4.v").read_text(encoding="utf-8")
old = ("tcp_rx u_tcp_rx2 (\n"
       "        .ACC_MARGIN     (acc_margin_eff1)")
new = ("tcp_rx u_tcp_rx2 (\n"
       "        .ACC_MARGIN     (acc_margin_eff)")
if src.count(old) != 1:
    raise SystemExit("[MUT FAIL] accmargin anchor not unique/found")
out = pathlib.Path(__file__).resolve().parent / "mut" / "wrapper_accmargin_bad.v"
out.parent.mkdir(exist_ok=True)
out.write_text(src.replace(old, new, 1), encoding="utf-8", newline="\n")
print("MUT accmargin -> %s" % out)
