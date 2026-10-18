#!/usr/bin/env python3
"""M-12: HLS source / netlist fingerprint archive.

Records (sha256):
  HLS_SRC_HASH  = combined over hls/src/*.cpp|*.h + hls/run_hls.tcl + hls/tb/*.cpp|*.h
  NET_HASH_C1 / P2 / P3 = combined over each archive's *.v + *.dat
  LIVE_VS_P3_MATCH = file-by-file compare of live solution1 vs P3 archive
Combined hash = sha256 of sorted "hash  relpath" lines (same spirit as build tcl).
"""
import hashlib
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
root = pathlib.Path(__file__).resolve().parents[4]  # notes/p11_p3_fix/gates -> repo
print("ROOT", root)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def combined(files):
    lines = ["%s  %s" % (sha(f), f.relative_to(root) if str(f).startswith(str(root)) else f)
             for f in sorted(files, key=lambda x: str(x))]
    return hashlib.sha256("\n".join(lines).encode()).hexdigest(), len(lines)


def globset(d, pats):
    out = []
    for pat in pats:
        out += list(d.glob(pat))
    return [f for f in out if f.is_file()]


src = globset(root / "hls" / "src", ["*.cpp", "*.h"])
src += [root / "hls" / "run_hls.tcl"]
src += globset(root / "hls" / "tb", ["*.cpp", "*.h"])
src = [f for f in src if f.exists()]
h_src, n_src = combined(src)
print("HLS_SRC_HASH = %s (n=%d)" % (h_src, n_src))

arch = {
    "C1": root / "_proj_10g/notes/p11_build_0x2C_20261018/hls_archive_single_ip",
    "P2": root / "_proj_10g/notes/p11_p3_build_20261019/hls_archive_p2_dual_ip_max3",
    "P3": root / "_proj_10g/notes/p11_p3_build_20261019/hls_archive_p3_dual_ip_max8",
}
hashes = {}
for k, d in arch.items():
    fs = globset(d, ["*.v", "*.dat"])
    h, n = combined(fs)
    hashes[k] = h
    print("NET_HASH_%s = %s (n=%d)" % (k, h, n))

# live vs P3
live = root / "hls/slowstack_prj/solution1/syn/verilog"
same = miss = diff = 0
for f in sorted(live.glob("*.v")):
    g = arch["P3"] / f.name
    if not g.exists():
        miss += 1
    elif sha(f) == sha(g):
        same += 1
    else:
        diff += 1
print("LIVE_VS_P3 same=%d diff=%d missing_in_P3=%d" % (same, diff, miss))
