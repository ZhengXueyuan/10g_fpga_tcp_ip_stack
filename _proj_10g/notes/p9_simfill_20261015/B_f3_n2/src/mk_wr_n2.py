#!/usr/bin/env python
# mk_wr_n2.py -- build the two wrapper copies for the F-3 N-2 arm.
#
# Round: _proj_10g/notes/p9_simfill_20261015  (F-3 N-2, zero build).
# Basis: _proj_10g/notes/p9_fix_f3_design_20261014/DESIGN_v2r4.md (= v2r2+v2r3+v2r4)
#        S2 N-2 / N-3 + v2r3 S1-4 ("cheap falsification path", friction (a)).
#
# I5': "with the new gate default-OFF (RESYNC_EN=0) the counters gate's old
# stimulus must be bit-equivalent" -- structural proof exists, MEASUREMENT did not.
# The design's cheap falsification: feed the counters gate a wrapper copy whose
# VLAN_STRIP_RESYNC is forced to 1'b0 and rerun; functional readings must come
# back verbatim to the pre-F-3 baseline W26/W27/W30/W31 = 69/256/257/2056.
#
# Outputs (this directory):
#   wr_off/wrapper_p4_resync0.v  -- copy with VLAN_STRIP_RESYNC forced to 1'b0
#                                   (anchored, exactly-once; a second edit marker
#                                   comment is appended so arm identity is text-
#                                   checkable)
#   wr_on/wrapper_p4.v           -- byte-identical copy of the tree's wrapper,
#                                   used as the SAME-SESSION ON control arm
#
# NOTE on ownership: the original gate run_tb_p6e_pcie_counters.bat lives in
# sim/p6e_pcie/ (owned by another in-flight work stream and off-limits to this
# round). Its file table line 20 points at board/wrapper_p4.v; per design N-3 a
# copy arm must redirect that line -- this round does so in its OWN copy of the
# runner (run_n2_arm.bat) instead of editing the sealed gate.

import hashlib
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANCHOR = "localparam VLAN_STRIP_RESYNC = 1'b1;"
MARK = "localparam VLAN_STRIP_RESYNC = 1'b0; // N-2 arm FROZEN-OFF (p9_simfill_20261015)"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) > 1:
        root = os.path.abspath(sys.argv[1])
    else:
        root = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
    wsrc = os.path.join(root, "board", "wrapper_p4.v")
    if not os.path.isfile(wsrc):
        raise SystemExit("MISSING-SOURCE " + wsrc)
    with io.open(wsrc, "r", encoding="utf-8", newline="") as f:
        text = f.read()

    n1 = text.count(ANCHOR)
    n0 = text.count("localparam VLAN_STRIP_RESYNC = 1'b0;")
    print("WRAPPER-SRC    %s" % wsrc)
    print("WRAPPER-SRC-SHA256 %s" % sha256(wsrc))
    print("ANCHOR-1B1-COUNT %d" % n1)
    print("ANCHOR-1B0-COUNT %d" % n0)
    if n1 != 1:
        raise SystemExit("ANCHOR-FAIL: VLAN_STRIP_RESYNC = 1'b1 occurs %d times (need 1)" % n1)

    off = text.replace(ANCHOR, MARK, 1)
    wr_off = os.path.join(HERE, "wr_off", "wrapper_p4_resync0.v")
    if not os.path.isdir(os.path.dirname(wr_off)):
        os.makedirs(os.path.dirname(wr_off))
    with io.open(wr_off, "w", encoding="utf-8", newline="") as f:
        f.write(off)
    chk = io.open(wr_off, "r", encoding="utf-8", newline="").read()
    if chk.count("VLAN_STRIP_RESYNC = 1'b1") != 0:
        raise SystemExit("OFF-COPY-STILL-HAS-1B1")
    print("WR-OFF         %s" % wr_off)
    print("WR-OFF-SHA256  %s" % sha256(wr_off))

    wr_on = os.path.join(HERE, "wr_on", "wrapper_p4.v")
    if not os.path.isdir(os.path.dirname(wr_on)):
        os.makedirs(os.path.dirname(wr_on))
    with open(wsrc, "rb") as fi, open(wr_on, "wb") as fo:
        fo.write(fi.read())
    if sha256(wr_on) != sha256(wsrc):
        raise SystemExit("ON-COPY-MISMATCH")
    print("WR-ON          %s" % wr_on)
    print("WR-ON-SHA256   %s" % sha256(wr_on))
    print("MK-WR-N2: OK")


if __name__ == "__main__":
    main()
