import io, sys, hashlib, os
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
base = r"D:\repo\XCKU5PMini\udp_hls_10g" + "\\"

def read_hashes(path):
    d = {}
    for line in io.open(path, "r", encoding="ascii", errors="replace"):
        if not line.startswith("SHA256 "):
            continue
        p = line.split()
        if len(p) >= 4:
            d[p[2]] = p[1]
    return d

base_fp = base + r"sim\p4sim\P4_MATRIX_FINGERPRINT_20261015_083428_after.txt"
new_fp  = base + r"sim\p4sim\P4_MATRIX_FINGERPRINT_20261015_234333_after.txt"
r_before = base + r"_proj_10g\notes\p9_build_0x28\P4_MATRIX_FINGERPRINT_20261015_234333_before.txt"
r_after  = base + r"_proj_10g\notes\p9_build_0x28\P4_MATRIX_FINGERPRINT_20261015_234333_after.txt"

for p, label in [(base_fp, "baseline_0x27"), (new_fp, "sim_new_0x28"),
                 (r_before, "round_before"), (r_after, "round_after_cop")]:
    print(label, "exists:", os.path.exists(p), end="")
    if os.path.exists(p):
        h = hashlib.sha256(open(p, 'rb').read()).hexdigest()[:16]
        print("  sha256[:16]=%s  mtime=%s" % (h, os.path.getmtime(p)))
    else:
        print()

a = read_hashes(base_fp)
b = read_hashes(new_fp)
rb = read_hashes(r_before)
ra = read_hashes(r_after)
print("sizes: baseline=%d new=%d round_before=%d round_after=%d" % (len(a), len(b), len(rb), len(ra)))
print("round before == after (freeze):", rb == ra)
changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
added = sorted(set(b) - set(a))
gone = sorted(set(a) - set(b))
print("CONTENT-CHANGED (%d):" % len(changed))
for k in changed:
    print("  C", k)
print("ADDED (%d):" % len(added), added)
print("GONE (%d):" % len(gone), gone)
# also compare round_before vs baseline: should be identical? (0x27 rounds drift between 08:34 and 23:43?)
ch2 = sorted(k for k in set(a) & set(rb) if a[k] != rb[k])
print("baseline vs round_before changed (%d):" % len(ch2), ch2)
