#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Research-only: simulate the P3 HLS udp_echo netlist and measure frame latency.

No product RTL is changed.  The HLS netlist is the exact archive used by the
0x32 build (p3_dual_max8); the TB feeds a single frame at 1 byte/cycle on a
6.4 ns clock and records rx/tx frame timestamps.  This measures HLS-only
latency (no slow adapters / tx_arb / MAC), so it is a lower bound for the
board path.

Cases:
  full = original hls_stim.memh (ARP frame + UDP frame)
  arp  = bytes 0..67 (68 B), TLAST only at byte 67
  udp  = bytes 68..141 (74 B), TLAST only at byte 141
"""
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
HLS = REPO / "_proj_10g" / "notes" / "p11_p3_build_20261019" / "hls_archive_p3_dual_ip_max8"
STIM = REPO / "sim" / "p4sim_hlsprobe"
VIV = Path(r"C:\AMDDesignTools\2025.2\Vivado\bin")
CLK_NS = 6.4
OUT = HERE / "READINGS.txt"


def run(cmd, log):
    with open(log, "w", encoding="utf-8", errors="replace") as f:
        p = subprocess.run(cmd, cwd=str(HERE), stdout=f, stderr=subprocess.STDOUT,
                           text=True, timeout=1800)
    return p.returncode


def read_memh(path):
    return [int(x, 16) for x in path.read_text(encoding="utf-8").split() if x.strip()]


def write_memh(path, vals):
    path.write_text("\n".join("%02x" % v for v in vals) + "\n", encoding="utf-8")


def make_cases():
    data = read_memh(STIM / "hls_stim.memh")
    last = [int(x, 16) for x in (STIM / "hls_stim_last.memh").read_text(encoding="utf-8").split() if x.strip()]
    n = len(data)
    assert n == len(last) == 142, (n, len(last))
    cases = {}
    cases["full"] = (data, last)
    arp_d = data[0:68]
    arp_l = [0] * 68
    arp_l[67] = 1
    cases["arp"] = (arp_d, arp_l)
    udp_d = data[68:142]
    udp_l = [0] * 74
    udp_l[73] = 1
    cases["udp"] = (udp_d, udp_l)
    # 1500B UDP echo (1472B payload) via the same generator used by the P4 probe.
    sys.path.insert(0, str(REPO / "tools"))
    import gen_stim_p4_chain as G
    pre = bytes([0x55] * 7) + b"\xd5"
    udp_fb, _fcs, _pl = G.mk_udp(n=1472)
    d1500 = list(pre + udp_fb)
    l1500 = [0] * len(d1500)
    l1500[-1] = 1
    cases["udp1500"] = (d1500, l1500)
    return cases


def parse(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    out = {"raw": text, "rx_rate": None, "rx": [], "tx": []}
    for line in text.splitlines():
        m = re.match(r"RX_TOTAL accepts=(\d+) valid_cycles=(\d+) wait_cycles=(\d+) cyc=(\d+)", line)
        if m:
            out["rx_rate"] = [int(x) for x in m.groups()]
        m = re.match(r"RX_FRAME idx=(\d+) first=(\d+) last=(\d+) dur=(\d+)", line)
        if m:
            out["rx"].append([int(x) for x in m.groups()])
        m = re.match(r"TX_FRAME idx=(\d+) first=(\d+) last=(\d+) dur=(\d+) bytes=(\d+)", line)
        if m:
            out["tx"].append([int(x) for x in m.groups()])
    return out


def main():
    if not (HLS / "udp_echo.v").exists():
        sys.exit("HLS archive missing: %s" % HLS)
    for p in HLS.glob("*.dat"):
        shutil.copy2(p, HERE / p.name)
    vs = sorted(HLS.glob("*.v"))
    (HERE / "hls_files.f").write_text("\n".join(str(p) for p in vs) + "\n", encoding="utf-8")
    print("HLS_FILES = %d" % len(vs))

    xvlog = str(VIV / "xvlog.bat")
    xelab = str(VIV / "xelab.bat")
    xsim = str(VIV / "xsim.bat")
    steps = [
        ("xvlog_hls", ["cmd", "/c", xvlog, "-work", "xil_defaultlib", "-f", "hls_files.f"]),
        ("xvlog_tb",  ["cmd", "/c", xvlog, "-work", "xil_defaultlib", "tb_hls_latency.v"]),
        ("xelab",     ["cmd", "/c", xelab, "-debug", "typical", "xil_defaultlib.tb_hls_latency",
                       "-s", "tb_hls_latency"]),
    ]
    for name, cmd in steps:
        rc = run(cmd, HERE / (name + ".log"))
        print("%s RC=%s" % (name, rc))
        if rc != 0:
            print("FAILED at %s; see %s.log" % (name, name))
            return 1

    cases = make_cases()
    results = {}
    for name, (data, last) in cases.items():
        write_memh(HERE / "hls_stim.memh", data)
        write_memh(HERE / "hls_stim_last.memh", last)
        old = HERE / "hls_latency_out.txt"
        if old.exists():
            old.unlink()
        rc = run(["cmd", "/c", xsim, "tb_hls_latency", "-runall"], HERE / ("xsim_%s.log" % name))
        print("xsim_%s RC=%s" % (name, rc))
        if rc != 0:
            print("FAILED at xsim_%s" % name)
            return 1
        dst = HERE / ("hls_latency_%s.txt" % name)
        shutil.copy2(HERE / "hls_latency_out.txt", dst)
        results[name] = parse(dst)

    lines = [
        "P11 HLS-ONLY LATENCY (P3 archive %s)" % HLS.name,
        "clock = %.1f ns (156.25 MHz); feed = held-valid, accepted on TREADY" % CLK_NS,
        "NOTE: HLS only (no slow_rx_adp/slow_tx_adp/tx_arb/MAC); lower bound for board path.",
        "1 B/cycle @156.25MHz = 156.25 MB/s = 1.25 Gbps.",
        "",
    ]
    for name in ("arp", "udp", "udp1500", "full"):
        r = results[name]
        lines.append("=== case %s ===" % name)
        if r["rx_rate"]:
            acc, valid, wait, cyc = r["rx_rate"]
            # Frame rate is in RX_FRAME dur/bytes; total accepts/cycles includes idle,
            # so do NOT derive a rate here (old bug: 1 B/cycle was mislabeled 1.5625 Gbps).
            lines.append("RX_TOTAL accepts=%d valid=%d wait=%d cyc=%d"
                         % (acc, valid, wait, cyc))
        for x in r["rx"]:
            idx, first, last, dur = x
            lines.append("RX_FRAME %d: first=%d last=%d dur=%d cyc (%.2f us)"
                         % (idx, first, last, dur, dur * CLK_NS / 1000.0))
        for x in r["tx"]:
            idx, first, last, dur, nbytes = x
            rate = (nbytes / dur * 156.25) if dur else 0.0
            lines.append("TX_FRAME %d: first=%d last=%d dur=%d cyc (%.2f us) bytes=%d => %.2f cyc/B, %.1f Mbps"
                         % (idx, first, last, dur, dur * CLK_NS / 1000.0, nbytes,
                            dur / nbytes if nbytes else 0, rate * 8))
        if r["rx"] and r["tx"]:
            rf, rl = r["rx"][0][1], r["rx"][0][2]
            tf, tl = r["tx"][0][1], r["tx"][0][2]
            lines.append("LAT first->first = %d cyc (%.2f us); last->last = %d cyc (%.2f us)"
                         % (tf - rf, (tf - rf) * CLK_NS / 1000.0,
                            tl - rl, (tl - rl) * CLK_NS / 1000.0))
        lines.append("")
        lines.append(r["raw"])
        lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines[:60]))
    print("READINGS = %s" % OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
