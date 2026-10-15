#!/usr/bin/env python
# mk_e7_top.py -- build the A+ variant-arm working copies for the mdio VIO top.
#
# Round: _proj_10g/notes/p9_simfill_20261015 (sim backfill round, 2026-10-15).
# Basis: _proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2r4.md (== v2r2+v2r3+v2r4)
#        §2.2 E7 ("mdio_vio_top.v 加顶层参数，插入型+替换型").
#
# WHAT IT DOES (read-only on the rest of the tree; writes ONLY into this directory):
#   1. copies _proj_mdio/rtl/mdio_vio_top.v (post-E1..E6 state)  -> mdio_vio_top.v
#   2. applies E7 to the copy: two ANCHORED, COUNTED replacements (each anchor must
#      appear EXACTLY once; anything else is a hard stop -- same discipline as
#      sim/f3_resync/mut/mk_mut_f3.py).
#   3. copies _proj_mdio/rtl/mdio_master.v  -> mdio_master.v  (byte-identical freeze)
#   4. prints sha256 of source and product for every file (arm-identity witness).
#
# E7 anchors (design doc, verbatim):
#   a) "module mdio_vio_top ("                          -> parameterized header
#   b) ".DIV (25)                       // 100MHz / 25 -> 2MHz MDC"
#                                                       -> ".DIV (DIV) ..."
# The default stays 25, so production elaboration is unchanged (design requirement).
#
# Usage:  python mk_e7_top.py [repo_root]
#         repo_root defaults to ..\.. of this script (self-locating).

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
    if len(sys.argv) > 1:
        root = os.path.abspath(sys.argv[1])
    else:
        root = os.path.abspath(os.path.join(HERE, "..", ".."))
    src_dir = os.path.join(os.path.dirname(root), "_proj_mdio", "rtl")
    top_src = os.path.join(src_dir, "mdio_vio_top.v")
    mst_src = os.path.join(src_dir, "mdio_master.v")
    for p in (top_src, mst_src):
        if not os.path.isfile(p):
            raise SystemExit("MISSING-SOURCE " + p)

    with io.open(top_src, "r", encoding="utf-8", newline="") as f:
        top = f.read()
    top_src_sha = sha256(top_src)

    a1_old = "module mdio_vio_top ("
    a1_new = (
        "module mdio_vio_top #(\n"
        "    parameter integer DIV = 25          // production 25; A+ arm overrides via build generic\n"
        ") ("
    )
    a2_old = ".DIV (25)                       // 100MHz / 25 -> 2MHz MDC"
    a2_new = ".DIV (DIV)                      // 100MHz / DIV -> 2MHz MDC at DIV=25"

    top = replace_once(top, a1_old, a1_new, "E7a")
    top = replace_once(top, a2_old, a2_new, "E7b")
    if "\r" in top:
        raise SystemExit("E7-OUTPUT-HAS-CR: unexpected (source is LF-only)")

    top_out = os.path.join(HERE, "mdio_vio_top.v")
    with io.open(top_out, "w", encoding="utf-8", newline="") as f:
        f.write(top)

    mst_out = os.path.join(HERE, "mdio_master.v")
    with open(mst_src, "rb") as fi, open(mst_out, "wb") as fo:
        fo.write(fi.read())

    print("E7-SOURCE     %s" % top_src)
    print("E7-SRC-SHA256 %s" % top_src_sha)
    print("E7-OUT        %s" % top_out)
    print("E7-OUT-SHA256 %s" % sha256(top_out))
    print("MST-SRC-SHA256 %s" % sha256(mst_src))
    print("MST-OUT-SHA256 %s" % sha256(mst_out))
    if sha256(mst_src) != sha256(mst_out):
        raise SystemExit("MASTER-COPY-MISMATCH")
    print("MK-E7-TOP: OK")


if __name__ == "__main__":
    main()
