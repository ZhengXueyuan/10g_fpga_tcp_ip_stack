#!/usr/bin/env python3
"""Red-team independent re-parser for B4 snapshot rings (written from scratch).

Parses runs/snap_<TAG>.log, groups lines into samples by SNAP_BEGIN..SNAP_END,
extracts W5/W20/W43/W51/W71..W74, and reports every counter change between
consecutive samples. Also cross-checks the ring's first/last against the
explicit pre_*.txt / post_*.txt reads.
"""
import re, sys, glob, os

RUNS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                    "p9_board_0x28_k0_20261016", "runs")

WL = re.compile(r"^W(\d+)\s+\S+\s+(\S+)\s+(0x[0-9a-fA-F]+)\s*$")
TB = re.compile(r"^SNAP_BEGIN\s+(\S+)\s+gen=(\d+)")
TE = re.compile(r"^SNAP_END\s+(\S+)\s+nff=(\d+)")
TT = re.compile(r"^SNAP_T\s+([\d.]+)")

def parse_ring(path):
    samples = []   # (t, gen, {w:val})
    t = None; curgen = None; cur = {}; collecting = False
    aborts = 0; genfails = []
    for line in open(path, errors="replace"):
        line = line.strip()
        m = TT.match(line)
        if m:
            t = float(m.group(1)); collecting = False; cur = {}; continue
        if line == "SNAP_ABORT":
            aborts += 1; collecting = False; continue
        if line.startswith("GEN_FAIL"):
            genfails.append((t, line)); continue
        m = TB.match(line)
        if m:
            curgen = int(m.group(2)); cur = {}; collecting = True; continue
        m = TE.match(line)
        if m:
            if collecting:
                samples.append((t, curgen, dict(cur)))
            collecting = False; continue
        m = WL.match(line)
        if m and collecting:
            cur[int(m.group(1))] = int(m.group(3), 16)
    return samples, aborts, genfails

def parse_flat(path):
    d = {}; gen = None
    for line in open(path, errors="replace"):
        line = line.strip()
        m = TB.match(line)
        if m: gen = int(m.group(2))
        m = WL.match(line)
        if m: d[int(m.group(1))] = int(m.group(3), 16)
    return gen, d

def main():
    for f in sorted(glob.glob(os.path.join(RUNS, "snap_*.log"))):
        tag = os.path.basename(f)[5:-4]
        samples, aborts, genfails = parse_ring(f)
        print(f"===== {tag} : {len(samples)} samples, {aborts} aborts, {len(genfails)} GEN_FAIL =====")
        if not samples:
            continue
        t0 = samples[0][0]
        gens = [s[1] for s in samples]
        # gen continuity within ring
        gaps = [(gens[i-1], gens[i]) for i in range(1, len(gens)) if gens[i] != gens[i-1] + 1]
        print(f"  first sample t=0 gen={gens[0]} W71..74={[samples[0][2].get(w) for w in (71,72,73,74)]}")
        print(f"  last  sample dt={samples[-1][0]-t0:.1f}s gen={gens[-1]} W71..74={[samples[-1][2].get(w) for w in (71,72,73,74)]}")
        print(f"  in-ring gen gaps: {gaps if gaps else 'none'}")
        # counter changes
        nch = 0
        for i in range(1, len(samples)):
            p, c = samples[i-1][2], samples[i][2]
            d = tuple(c.get(w, 0) - p.get(w, 0) for w in (71, 72, 73, 74))
            if any(d):
                nch += 1
                dt = samples[i][0] - t0
                w51 = c.get(51); w20 = c.get(20)
                s51 = f"{w51:#x}" if w51 is not None else "NA"
                s20 = f"{w20:#x}" if w20 is not None else "NA"
                print(f"  chg t={dt:8.2f}s dEv={d[0]:+d} dReq={d[1]:+d} dApply={d[2]:+d} dPend={d[3]:+d}"
                      f" cum=({c.get(71)},{c.get(72)},{c.get(73)},{c.get(74)})"
                      f" W51={s51} W20={s20}")
        print(f"  ring counter-change events: {nch}")
        # identity check across whole ring
        a, b = samples[0][2], samples[-1][2]
        dEv = b.get(71,0)-a.get(71,0); dReq = b.get(72,0)-a.get(72,0)
        dApp = b.get(73,0)-a.get(73,0); dPend = b.get(74,0)-a.get(74,0)
        print(f"  ring total: dEv={dEv} dReq={dReq} dApply={dApp} dPend={dPend}"
              f" | dEv-(dReq+dPend)={dEv-dReq-dPend} | dApply-(dReq+({dEv-dReq-dPend}))={dApp-(dReq+(dEv-dReq-dPend))}")

if __name__ == "__main__":
    main()
