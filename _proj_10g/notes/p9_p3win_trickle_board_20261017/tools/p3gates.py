#!/usr/bin/env python3
"""p3gates.py -- compute the P-3 arm precondition gates (G1/G2/G3) + expectation gate.

Design doc: _proj_10g/notes/p9_p3win_design_20261016/DESIGN.md sec.4
  G1  d(W72+W74) > 0                 (0x28 arms only; 0x24 has no E12 -> "not measurable here")
  G2  mean W51 rate >= 1 Gbps        (W51 = app_pattern TX payload bytes)
  G3  three-state identity closed    dW71 == dW73 + dW74   (measured form; equiv dW71 == d(apply)+dW72+dW74)
  EXPECTATION GATE  d(W72+W74) * P(H) >= 3,  P(H) = W51_rate_Bps / (1460 * 156.25e6)

Usage:
  python p3gates.py --pre <pre.txt> --post <post.txt> [--ring <snap.log>] [--dt SECONDS]
  python p3gates.py --armstdout <arm_stdout.txt> [--dt SECONDS]

This tool REPORTS numbers; it issues NO PASS/FAIL verdict (criteria owner's call).
"""
import argparse
import re
import sys


def parse_snap_block(text):
    """-> (epoch, {word: value}) from the LAST SNAP_BEGIN..SNAP_END block in text."""
    t = None
    cur = {}
    for line in text.splitlines():
        line = line.strip()
        m = re.match(r"SNAP_T\s+([\d.]+)", line)
        if m:
            t = float(m.group(1)); cur = {}
        m = re.match(r"W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
        if m:
            cur[int(m.group(1))] = int(m.group(2), 16)
    return t, cur


def extract_blocks(armstdout):
    """Pull the SNAP_PRE / SNAP_POST blocks out of an arm stdout transcript."""
    txt = open(armstdout, errors="replace").read()
    pre = re.search(r"--- SNAP_PRE.*?\n(.*?)PRE_RC=", txt, re.S)
    post = re.search(r"--- SNAP_POST.*?\n(.*?)POST_RC=", txt, re.S)
    return (pre.group(1) if pre else ""), (post.group(1) if post else "")


P_WORD = 1460
CLK = 156.25e6


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pre", default=None)
    ap.add_argument("--post", default=None)
    ap.add_argument("--armstdout", default=None)
    ap.add_argument("--ring", default=None)
    ap.add_argument("--dt", type=float, default=None, help="run seconds (for W51 mean rate)")
    ap.add_argument("--gen", default=None, help="0x28 | 0x24 (informational)")
    a = ap.parse_args()

    if a.armstdout:
        pre_txt, post_txt = extract_blocks(a.armstdout)
        if not pre_txt or not post_txt:
            print("NO_PRE_POST_BLOCKS_IN %s" % a.armstdout); return
    else:
        pre_txt = open(a.pre, errors="replace").read()
        post_txt = open(a.post, errors="replace").read()

    tpre, pre = parse_snap_block(pre_txt)
    tpost, post = parse_snap_block(post_txt)
    dt = a.dt if a.dt is not None else (tpost - tpre if (tpre and tpost) else None)

    need = [71, 72, 73, 74, 51, 20, 43, 5]
    have = [w for w in need if w in pre and w in post]
    missing = [w for w in need if w not in have]
    if missing:
        print("MISSING_WORDS %s  (0x24 has no E12: 71..74 are MIR words there)" % missing)

    def d(w):
        if w in pre and w in post:
            return (post[w] - pre[w]) & 0xFFFFFFFF
        return None

    print("=== P-3 ARM GATE INPUTS ===")
    print("t_pre=%.3f t_post=%.3f dt=%.3f s" % (tpre or 0, tpost or 0, dt or 0))
    for w in need:
        if w in have:
            print("  W%-3d pre=%-12d post=%-12d dW=%-12d" % (w, pre[w], post[w], d(w)))

    if a.ring:
        sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
        import snap_series
        samples, n_abort = snap_series.parse(a.ring)
        if samples:
            print("\n=== ring (independent read of the same window) ===")
            print("  samples=%d aborted=%d span=%.3f" % (len(samples), n_abort, samples[-1][0] - samples[0][0]))
            for w in need:
                v = [(t, dd[w]) for (t, g, dd) in samples if w in dd]
                if len(v) >= 2:
                    print("  W%-3d ring_delta=%-12d  (samples=%d)" % (w, (v[-1][1] - v[0][1]) & 0xFFFFFFFF, len(v)))

    print("\n=== GATES (numbers only; no verdict) ===")
    dw72, dw74, dw71, dw73, dw51 = d(72), d(74), d(71), d(73), d(51)
    if dw72 is None or dw74 is None:
        print("G1  NOT MEASURABLE (no E12 words 71..74 in this generation)")
    else:
        print("G1  d(W72+W74) = %d + %d = %d   [>0 required; 0 => arm has NO discriminating power]" % (dw72, dw74, dw72 + dw74))
    if dw51 is not None and dt:
        rate_bps = dw51 * 8.0 / dt
        print("G2  W51 mean rate = %d B / %.3f s = %.6f Gbps  [>= 1 Gbps required]" % (dw51, dt, rate_bps / 1e9))
        print("    read together with W63/W64 (app stall cycles) - a mean hides stall structure")
        P = (dw51 / dt) / (P_WORD * CLK)
        print("    P(hit per event) = (W51_Bps)/(1460*156.25e6) = %.3e  (frame period ~%.1f cycles)" % (P, 1.0 / P) if P > 0 else "")
        if dw72 is not None and dw74 is not None:
            ev = dw72 + dw74
            print("EXPECTATION GATE: (%d) * %.3e = %.4f   [>= 3 required for 'must-reveal if H1 holds']" % (ev, P, ev * P))
    else:
        print("G2  NOT COMPUTABLE (needs W51 + dt)")
    if dw71 is not None and dw73 is not None and dw74 is not None:
        lhs, rhs = dw71, dw73 + dw74
        print("G3  dW71 = %-8d  dW73+dW74 = %-8d  -> %s" % (lhs, rhs, "CLOSED" if lhs == rhs else "NOT CLOSED (delta=%+d)" % (lhs - rhs)))
        print("    measured form note: d(apply-on-the-fly) = dW73 - dW72 = %d" % (dw73 - dw72))
    else:
        print("G3  NOT MEASURABLE")


if __name__ == "__main__":
    main()
