#!/usr/bin/env python
# mk_mut_aplus.py -- negative-control (teeth) mutants for the mdio A+ arm gate.
#
# Round: _proj_10g/notes/p9_simfill_20261015.
# Input : ../mdio_vio_top.v  (the E7 working copy produced by mk_e7_top.py)
# Output: mut_zero.v / mut_swap.v  (same module name, one anchored edit each)
#
# The two mutants answer the two questions the A+ arm exists to settle:
#   mut_zero -- "bit present but constant 0" = exactly the board-side ambiguity
#               the design calls out (v2 §4.2-J-D / §7-R-b: on the production
#               bitstream the two new bits are indistinguishable from
#               unconnected). Both new probe bits are tied to 1'b0.
#   mut_swap -- the two new bits exchanged. Catches a packing-order regression
#               (E5 put them at the MSB end as {stat_start_lost, param_bad}).
#
# Discipline (same as sim/f3_resync/mut/mk_mut_f3.py): every anchor must appear
# EXACTLY once in the source; anything else is a hard stop.

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def replace_once(text, old, new, tag):
    n = text.count(old)
    if n != 1:
        raise SystemExit("ANCHOR-FAIL %s: found %d occurrences (need exactly 1)" % (tag, n))
    return text.replace(old, new, 1)


def main():
    src = os.path.join(HERE, "..", "mdio_vio_top.v")
    src = os.path.abspath(src)
    if not os.path.isfile(src):
        raise SystemExit("MISSING-SOURCE " + src + " (run mk_e7_top.py first)")
    with io.open(src, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    print("MUT-SRC      %s" % src)
    print("MUT-SRC-SHA256 %s" % sha256(src))

    anchor = "{stat_start_lost, param_bad, mdio_i,"
    if text.count(anchor) != 1:
        raise SystemExit("ANCHOR-FAIL concat: found %d (need exactly 1)" % text.count(anchor))

    zero = replace_once(text, anchor, "{1'b0, 1'b0, mdio_i,", "mut_zero")
    swap = replace_once(text, anchor, "{param_bad, stat_start_lost, mdio_i,", "mut_swap")

    for name, body in (("mut_zero.v", zero), ("mut_swap.v", swap)):
        out = os.path.join(HERE, name)
        with io.open(out, "w", encoding="utf-8", newline="") as f:
            f.write(body)
        print("MUT-OUT      %s" % out)
        print("MUT-OUT-SHA256 %s" % sha256(out))
    print("MK-MUT-APLUS: OK")


if __name__ == "__main__":
    main()
