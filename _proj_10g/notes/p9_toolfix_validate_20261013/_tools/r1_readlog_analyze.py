#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""r1_readlog_analyze.py -- R1 window READLOG criteria analyzer (written BEFORE the run).

Implements CRITERIA_R1.md:
  R1-a  line-level uint32 wrap:  all rows dw70 < 2^31
  R1-b  t-sorted chain closure rate (expect 100%) + tail reconciliation:
          (w70[0]-w70a) & ~ == dw70[0];  (w70[k]-w70[k-1]) & ~ == dw70[k]
          (dma[0]-words0) & ~ == ddma[0]; (dma[k]-dma[k-1]) & ~ == ddma[k]
          err  = dW70   - sum(dw70) - ((w70b  - w70_last)  & M32)   expect 0
          err2 = dwords - sum(ddma) - ((words1 - dma_last) & M32)   expect 0
  R1-c  is a report-level juxtaposition (not computed here).

Usage: python r1_readlog_analyze.py <window_stdout.txt>
Prints raw-derived numbers only (no PASS/FAIL verdict).
"""
import re
import sys

M32 = 0xFFFFFFFF

ACCT_RE = re.compile(
    r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+) w70a=(\d+) w70b=(\d+) "
    r"words0=(\d+) words1=(\d+) dwords=(\d+) K=(\d+)")
ROW_RE = re.compile(
    r"^READLOG i=(\d+) t=([0-9.]+) gap_us=([0-9.]+) mmio_us=([0-9.]+) read_us=([0-9.]+) "
    r"got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)\s*$")
DONE_RE = re.compile(r"MIR_STREAM_DONE (.+)$")


def main():
    path = sys.argv[1]
    rows = []
    acct = None
    done = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for ln in f:
            m = ROW_RE.match(ln.strip())
            if m:
                g = m.groups()
                rows.append(dict(i=int(g[0]), t=float(g[1]), gap_us=float(g[2]),
                                 mmio_us=float(g[3]), read_us=float(g[4]),
                                 got=int(g[5]), pc=int(g[6]), w70=int(g[7]),
                                 dw70=int(g[8]), dma=int(g[9]), ddma=int(g[10])))
                continue
            m = ACCT_RE.search(ln)
            if m:
                acct = dict(pc=int(m.group(1)), taken=int(m.group(2)), dW70=int(m.group(3)),
                            w70a=int(m.group(4)), w70b=int(m.group(5)), words0=int(m.group(6)),
                            words1=int(m.group(7)), dwords=int(m.group(8)), K=int(m.group(9)))
            if "MIR_STREAM_DONE" in ln and done is None:
                done = ln.strip()

    print("== file:", path)
    print("== rows:", len(rows))
    if not rows or acct is None:
        print("MISSING rows or ACCT line; nothing to analyze")
        return 2
    print("== ACCT:", acct)
    print("== DONE:", done)

    # ---- R1-a: line-level wrap ----
    maxdw = max(r["dw70"] for r in rows)
    mindw = min(r["dw70"] for r in rows)
    n_wrap_cand = sum(1 for r in rows if r["dw70"] >= (1 << 31))
    print("\n[R1-a] line-level uint32 wrap")
    print("  rows=%d  dw70 min=%d max=%d  wrap_candidates(dw70>=2^31)=%d"
          % (len(rows), mindw, maxdw, n_wrap_cand))
    print("  max(dw70) >= 2^31 ? %s" % (maxdw >= (1 << 31)))

    # ---- R1-b: t-sorted chain closure ----
    rows_t = sorted(rows, key=lambda r: r["t"])
    dup_t = sum(1 for k in range(1, len(rows_t)) if rows_t[k]["t"] <= rows_t[k - 1]["t"])
    closes = 0
    fails = []
    # first row vs ACCT baselines
    if (rows_t[0]["w70"] - acct["w70a"]) & M32 == rows_t[0]["dw70"]:
        closes += 1
    else:
        fails.append(("row0", rows_t[0], acct["w70a"]))
    for k in range(1, len(rows_t)):
        if (rows_t[k]["w70"] - rows_t[k - 1]["w70"]) & M32 == rows_t[k]["dw70"]:
            closes += 1
        else:
            fails.append((k, rows_t[k], rows_t[k - 1]["w70"]))
    dcloses = 0
    dfails = []
    if (rows_t[0]["dma"] - acct["words0"]) & M32 == rows_t[0]["ddma"]:
        dcloses += 1
    else:
        dfails.append(("row0", rows_t[0], acct["words0"]))
    for k in range(1, len(rows_t)):
        if (rows_t[k]["dma"] - rows_t[k - 1]["dma"]) & M32 == rows_t[k]["ddma"]:
            dcloses += 1
        else:
            dfails.append((k, rows_t[k], rows_t[k - 1]["dma"]))
    n = len(rows_t)
    print("\n[R1-b] chain closure, t-sorted")
    print("  t-sorted; non-increasing t pairs (should be 0): %d" % dup_t)
    print("  w70-chain closures = %d / %d  (rate=%.4f%%)" % (closes, n, 100.0 * closes / n))
    print("  dma-chain closures = %d / %d  (rate=%.4f%%)" % (dcloses, n, 100.0 * dcloses / n))
    for f in fails[:8]:
        k, r, prev = f
        print("    FAIL row k=%s t=%.6f w70=%d dw70=%d prev_w70=%d delta=%d"
              % (k, r["t"], r["w70"], r["dw70"], prev, (r["w70"] - prev) & M32))
    for f in dfails[:8]:
        k, r, prev = f
        print("    DFAIL row k=%s t=%.6f dma=%d ddma=%d prev_dma=%d delta=%d"
              % (k, r["t"], r["dma"], r["ddma"], prev, (r["dma"] - prev) & M32))

    sum_dw = sum(r["dw70"] for r in rows)
    sum_dd = sum(r["ddma"] for r in rows)
    tail_w = (acct["w70b"] - rows_t[-1]["w70"]) & M32
    tail_d = (acct["words1"] - rows_t[-1]["dma"]) & M32
    err = acct["dW70"] - sum_dw - tail_w
    err2 = acct["dwords"] - sum_dd - tail_d
    print("\n[R1-b] tail reconciliation")
    print("  sum(dw70)=%d  ACCT dW70=%d  lastrow.w70=%d  ACCT w70b=%d  tail=(w70b-last)&M32=%d"
          % (sum_dw, acct["dW70"], rows_t[-1]["w70"], acct["w70b"], tail_w))
    print("  err = dW70 - sum(dw70) - tail = %d  (expect 0)" % err)
    print("  sum(ddma)=%d  ACCT dwords=%d  lastrow.dma=%d  ACCT words1=%d  tail_d=%d"
          % (sum_dd, acct["dwords"], rows_t[-1]["dma"], acct["words1"], tail_d))
    print("  err2 = dwords - sum(ddma) - tail_d = %d  (expect 0)" % err2)

    # ---- print-order morphology (calibration view; R3 says print order is NOT a time order) ----
    print("\n[calib] print-order morphology (NOT a criterion)")
    pcloses = 0
    for k in range(1, len(rows)):
        if (rows[k]["w70"] - rows[k - 1]["w70"]) & M32 == rows[k]["dw70"]:
            pcloses += 1
    print("  print-order adjacent w70-chain closures = %d / %d" % (pcloses, len(rows) - 1))
    # print-order delta distribution vs dw70==0 rows
    zero_rows = sum(1 for r in rows if r["dw70"] == 0)
    print("  rows with dw70==0: %d / %d" % (zero_rows, len(rows)))
    # first/last t and pc span
    print("  t range: %.6f .. %.6f ; pc range: %d .. %d"
          % (rows_t[0]["t"], rows_t[-1]["t"], rows_t[0]["pc"], rows_t[-1]["pc"]))
    print("  rows by thread (print order): thread0 rows = i ascending 0..? ; "
          "note i is print index, thread concat")
    return 0


if __name__ == "__main__":
    sys.exit(main())
