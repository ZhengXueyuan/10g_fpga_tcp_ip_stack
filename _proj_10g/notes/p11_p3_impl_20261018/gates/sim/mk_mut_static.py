#!/usr/bin/env python3
"""M-9 negative control: slow_merge2 reset back to reset_n (soft reset)."""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]
src = (root / "board" / "wrapper_p4.v").read_text(encoding="utf-8")
old = ("u_slow_merge (\n"
       "        .clk(dp_clk), .rst_n(dp_rst_n),")
new = ("u_slow_merge (\n"
       "        .clk(dp_clk), .rst_n(reset_n),")
if src.count(old) != 1:
    raise SystemExit("[MUT FAIL] slow_merge reset anchor not found")
out = pathlib.Path(__file__).resolve().parent / "mut" / "wrapper_slowmerge_reset_bad.v"
out.parent.mkdir(exist_ok=True)
out.write_text(src.replace(old, new, 1), encoding="utf-8", newline="\n")
print("MUT slowmerge_reset -> %s" % out)
