#!/usr/bin/env python3
# mk_sha256sums.py -- 本卷归档自核: 逐文件 sha256 -> SHA256SUMS.txt (排除 SHA256SUMS.txt 自身)
import hashlib, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = []
for dp, dns, fns in os.walk(ROOT):
    dns.sort(); 
    for fn in sorted(fns):
        fp = os.path.join(dp, fn)
        rel = os.path.relpath(fp, ROOT).replace("\\", "/")
        if rel == "SHA256SUMS.txt": continue
        h = hashlib.sha256()
        with open(fp, "rb") as f:
            for ch in iter(lambda: f.read(1 << 20), b""):
                h.update(ch)
        out.append(f"{h.hexdigest()}  {rel}  ({os.path.getsize(fp)} B)")
with open(os.path.join(ROOT, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print(f"WROTE SHA256SUMS.txt with {len(out)} entries")
