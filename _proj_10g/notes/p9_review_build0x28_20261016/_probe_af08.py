import io, sys, hashlib
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g" + "\\"
fp = base + r"sim\p4sim\P4_MATRIX_FINGERPRINT_20261015_234333_after.txt"
recs = []
for line in io.open(fp, "r", encoding="ascii", errors="replace"):
    if line.startswith("SHA256 "):
        p = line.split()
        recs.append((p[2], p[1], int(p[3]), int(p[4])))

target = "af08f8eef8866a510152d5f1205bae6c62a7a49ccc3e8e15a30bb6a97838eb34"

def h(lines):
    d = hashlib.sha256()
    for ln in lines:
        d.update(ln.encode("ascii"))
    return d.hexdigest()

variants = {}
variants["sorted sha  rel \\n"] = h(sorted("%s  %s\n" % (s, r) for r, s, z, m in recs))
variants["insertion sha  rel \\n"] = h(["%s  %s\n" % (s, r) for r, s, z, m in recs])
variants["sorted rel  sha \\n"] = h(sorted("%s  %s\n" % (r, s) for r, s, z, m in recs))
variants["sorted sha rel no-nl"] = h(["%s  %s" % (s, r) for r, s, z, m in sorted(recs)])
variants["sorted full rec \\n"] = h(sorted("%s  %s  %d  %d\n" % (s, r, z, m) for r, s, z, m in recs))
variants["sorted sha  rel  size \\n"] = h(sorted("%s  %s  %d\n" % (s, r, z) for r, s, z, m in recs))
for k, v in variants.items():
    print("%-28s %s%s" % (k, v, "   <== TARGET" if v == target else ""))

# what about sha of p4gate.py at run time?
for r, s, z, m in recs:
    if r.endswith("p4gate.py"):
        print("fingerprint record for", r, "->", s)
cur = hashlib.sha256(open(base + r"sim\p4gates\p4gate.py", 'rb').read()).hexdigest()
print("current on-disk p4gate.py sha256:", cur)
