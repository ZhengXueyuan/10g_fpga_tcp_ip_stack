#!/usr/bin/env python
# mk_tb_nosop.py -- build the "historical (SOP-less) stimulus" TB variant for N-2.
#
# Round: _proj_10g/notes/p9_simfill_20261015.
# Basis: v2r2 S1-3b I5' -- "with RESYNC_EN=0 the counters gate's OLD stimulus must be
#        bit-equivalent: fwd == 1 so vlan_strip behaves exactly as pre-F-3, hence NOT
#        dependent on 'SOP first'; the gate's historical readings (5 backup logs,
#        verbatim identical) must come back as-is."
#        The 5 backups were taken with a stimulus that never asserted tuser (SOP-less);
#        the H1 fix later prepended an opening SOP to make the ON arm pass again.
#        => the FAITHFUL arm for I5' is OFF x SOP-less.  This script rebuilds that
#        stimulus shape from the frozen TB with two anchored edits.
#
# Input : frozen/tb_p6e_pcie_counters.FROZEN.v
# Output: frozen/tb_p6e_pcie_counters.NOSOP.v
#
# Edits (anchored, exactly-once):
#   1. the H-section opening force: tuser = 1'b1 -> 1'b0   (never assert SOP)
#   2. the H0 witness condition:    === 1'b1  -> === 1'b0  (keep the probe honest)
# Everything else -- streams, counts, criteria -- is untouched, so a PASS here is
# directly comparable with both the frozen ON arm and the 5 on-disk backups.

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
    src = os.path.join(HERE, "frozen", "tb_p6e_pcie_counters.FROZEN.v")
    if not os.path.isfile(src):
        raise SystemExit("MISSING-SOURCE " + src)
    with io.open(src, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    print("NOSOP-SRC      %s" % src)
    print("NOSOP-SRC-SHA256 %s" % sha256(src))

    text = replace_once(
        text,
        "force u_dut.rxsrc_tuser  = 1'b1;",
        "force u_dut.rxsrc_tuser  = 1'b0;  // N-2 arm: historical SOP-less stimulus",
        "nosop-force")
    text = replace_once(
        text,
        "if (u_dut.rxsrc_tvalid === 1'b1 && u_dut.vs_tready === 1'b0\n            && u_dut.rxsrc_tuser === 1'b1)",
        "if (u_dut.rxsrc_tvalid === 1'b1 && u_dut.vs_tready === 1'b0\n            && u_dut.rxsrc_tuser === 1'b0)",
        "nosop-h0")

    out = os.path.join(HERE, "frozen", "tb_p6e_pcie_counters.NOSOP.v")
    with io.open(out, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print("NOSOP-OUT      %s" % out)
    print("NOSOP-OUT-SHA256 %s" % sha256(out))
    print("MK-TB-NOSOP: OK")


if __name__ == "__main__":
    main()
