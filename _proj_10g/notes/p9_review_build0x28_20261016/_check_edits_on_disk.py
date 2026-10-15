# Independent check of EDITS_28_BLOCK.txt vs disk (read-only)
import ast, os

base = r"D:\repo\XCKU5PMini\udp_hls_10g"
blk = os.path.join(base, r"_proj_10g\notes\p9_build_0x28\EDITS_28_BLOCK.txt")
text = open(blk, encoding="utf-8").read()

# split top-level E13(...) entries: each begins at column 0
import re
parts = re.split(r"(?m)^E13\(", text)
entries = ["E13(" + p for p in parts[1:]]
print("entries parsed:", len(entries))

per_file = {}
new_missing = []
old_class = {"replacement_old_gone": 0, "insert_old_retained": 0, "other": []}
for e in entries:
    try:
        call = ast.parse(e, mode="eval").body
        rel = ast.literal_eval(call.args[0])
        old = ast.literal_eval(call.args[1])
        new = ast.literal_eval(call.args[2])
        n = ast.literal_eval(call.args[3]) if len(call.args) > 3 else 1
    except Exception as ex:
        print("PARSE FAIL:", e[:80], ex)
        continue
    per_file[rel] = per_file.get(rel, 0) + 1
    p = os.path.join(base, rel.replace("/", os.sep))
    content = open(p, encoding="utf-8", errors="replace").read()
    if new.count("\x00"):
        pass
    n_new = content.count(new)
    n_old = content.count(old)
    if n_new < 1:
        new_missing.append((rel, e[:120].replace("\n", "\\n")))
    if new == old:
        old_class["other"].append(("NOOP", rel))
    elif old in new:
        old_class["insert_old_retained"] += 1
    else:
        old_class["replacement_old_gone"] += 1
        if n_old != 0:
            old_class["other"].append(("old residue %d" % n_old, rel, old[:60]))

print("files:", len(per_file), "edits:", sum(per_file.values()))
print("new-text MISSING on disk:", len(new_missing))
for m in new_missing:
    print("  MISSING:", m[0], "|", m[1])
print("classify:", old_class["replacement_old_gone"], "replacement;",
      old_class["insert_old_retained"], "insert(retained)")
print("other anomalies:", len(old_class["other"]))
for o in old_class["other"][:20]:
    print("  ", o)
