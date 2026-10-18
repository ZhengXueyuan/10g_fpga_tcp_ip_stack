#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P11 review-fix (2026-10-18): unified xsim error scan for G2/G3/G4/G6.

Purpose: every xsim log in these four gates must be free of simulator-level
errors.  A small, explicitly justified whitelist covers the known-benign
frame_fifo SDP same-address (bypass) collision, which is inherent to
rtl/frame_fifo.v by design and masked by bypass_r (see rtl/frame_fifo.v
header, "cycle semantics" bullet, and the review-fix report).

Modes
  none      : nothing is allowed (G2 rx_merge2, G3 tx_split).
  slowport  : allow ONLY "Memory Collision Error on RAMB36E1" whose instance
              is tb_slow_tx_port.u_dut.u_wf / u_small.u_wf (frame_fifo,
              .gen_mem[0].u_main.gen_sdp.gen_wide.INT_RAMB_SDP) AND whose
              continuation line is the read-port-A vs write-port-B
              same-address branch (the bypass case).  Anything else = fail.
  p11dual   : allow ONLY "Error: [Unisim RAMB36E2-11] Memory Collision" whose
              Instance line is tb_p11_dual.u_dut.u_slow_rx.u_ff.gen_mem[0].u_main
              AND whose continuation line is the simultaneous WRITE/B vs
              READ/A form.  Anything else = fail.
  c4wrap    : same as p11dual but the instance is
              tb_p11_c4_wrap.u_dut.u_slow_rx.u_ff.gen_mem[0].u_main
              (P3 C4 wrapper gate, M-1).

Exit codes: 0 = clean (or only whitelisted lines), 1 = violation / bad usage.
The verdict keywords printed here are the gate's own evidence lines; this
script does not decide PASS/FAIL for the design, only for the log scan.
"""
import argparse
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Tokens that mark simulator-level problems regardless of instance.
# Matching is case-insensitive (xsim prints "CRITICAL WARNING" in upper case).
HARD_TOKENS = ("error:", "critical", "memory collision", "address overlap", "unisim")

E1_RE = re.compile(
    r"^Memory Collision Error on RAMB36E1 : (?P<inst>\S+) at simulation time .*$")
E2_RE = re.compile(
    r"^Error: \[Unisim RAMB36E2-11\] Memory Collision at time .*$")

SLOWPORT_INSTANCES = (
    "tb_slow_tx_port.u_dut.u_wf",
    "tb_slow_tx_port.u_small.u_wf",
)
SLOWPORT_SUFFIX = ".gen_mem[0].u_main.gen_sdp.gen_wide.INT_RAMB_SDP.chk_for_col_msg"
E1_CONT_RE = re.compile(
    r"^A read was performed on address .* of port A while a write was requested "
    r"to the same address on port B\.")

P11DUAL_INSTANCE = "tb_p11_dual.u_dut.u_slow_rx.u_ff.gen_mem[0].u_main"
E2_CONT_RE = re.compile(
    r"^A simultaneous WRITE on port B .* and READ on port A .*$")
C4WRAP_INSTANCE = "tb_p11_c4_wrap.u_dut.u_slow_rx.u_ff.gen_mem[0].u_main"

ALLOWED = {"slowport": 0, "p11dual": 0, "c4wrap": 0}


def scan(log_path, mode, verbose=False):
    if not os.path.exists(log_path):
        print("XSIM_ERROR_SCAN FAIL missing-log %s" % log_path)
        return 1
    with open(log_path, "r", encoding="utf-8", errors="replace") as fh:
        lines = fh.read().splitlines()

    allowed = 0
    violations = []
    for i, line in enumerate(lines):
        low = line.lower()
        if not any(tok in low for tok in HARD_TOKENS):
            continue
        ok = False
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if mode == "slowport":
            m = E1_RE.match(line)
            if m:
                inst = m.group("inst")
                base = inst.split(".")[0] + "." + inst.split(".")[1] + "." + inst.split(".")[2]
                if (base in SLOWPORT_INSTANCES and inst.endswith(SLOWPORT_SUFFIX)
                        and E1_CONT_RE.match(nxt)):
                    ok = True
                    allowed += 1
                    if verbose:
                        print("XSIM_BENIGN_E1 %s" % inst)
        elif mode in ("p11dual", "c4wrap"):
            cont1 = nxt                                    # "A simultaneous WRITE ..."
            cont2 = lines[i + 2] if i + 2 < len(lines) else ""   # "Instance: ..."
            want = P11DUAL_INSTANCE if mode == "p11dual" else C4WRAP_INSTANCE
            if E2_RE.match(line) and E2_CONT_RE.match(cont1) and want in cont2:
                ok = True
                allowed += 1
                if verbose:
                    print("XSIM_BENIGN_E2 %s" % want)
        if not ok:
            violations.append((i + 1, line.rstrip()))

    print("XSIM_ERROR_SCAN log=%s mode=%s lines=%d allowed=%d violations=%d"
          % (os.path.basename(log_path), mode, len(lines), allowed, len(violations)))
    for ln, txt in violations[:50]:
        print("XSIM_ERROR_SCAN FAIL line=%d: %s" % (ln, txt))
    if violations:
        return 1
    if mode == "slowport" and allowed:
        print("XSIM_BENIGN_E1_RAMB36E1 count=%d -- frame_fifo SDP bypass same-address "
              "(rtl/frame_fifo.v; masked by bypass_r)" % allowed)
    if mode in ("p11dual", "c4wrap") and allowed:
        print("XSIM_BENIGN_E2_RAMB36E2 count=%d at u_slow_rx.u_ff -- documented "
              "bypass collision" % allowed)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True)
    ap.add_argument("--mode", required=True, choices=("none", "slowport", "p11dual", "c4wrap"))
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    return scan(a.log, a.mode, a.verbose)


if __name__ == "__main__":
    sys.exit(main())
