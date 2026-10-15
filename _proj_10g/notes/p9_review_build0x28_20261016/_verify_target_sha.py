import hashlib, os, sys
base = r"D:\repo\XCKU5PMini\udp_hls_10g"
rdir = r"_proj_10g\notes\p9_build_0x28"
def rd(name):
    d = {}
    for line in open(os.path.join(base, rdir, name), encoding='utf-8'):
        line = line.strip()
        if not line:
            continue
        sha, rel = line.split(None, 1)
        d[rel.strip()] = sha
    return d
before = rd("TARGET_SHA_BEFORE_BID28.txt")
after = rd("TARGET_SHA_AFTER_BID28.txt")
print("n_before=%d n_after=%d" % (len(before), len(after)))
print("same_file_set:", set(before) == set(after))
changed = same = 0
mismatch = []
for rel in sorted(after):
    p = os.path.join(base, rel.replace('/', os.sep))
    if not os.path.exists(p):
        mismatch.append((rel, "MISSING"))
        continue
    h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    if before[rel] == after[rel]:
        same += 1
    else:
        changed += 1
    if h != after[rel]:
        mismatch.append((rel, "disk=%s after=%s before=%s" % (h, after[rel], before[rel])))
print("changed(before!=after)=%d same=%d" % (changed, same))
print("disk vs AFTER mismatches: %d" % len(mismatch))
for m in mismatch:
    print("  ", m)
