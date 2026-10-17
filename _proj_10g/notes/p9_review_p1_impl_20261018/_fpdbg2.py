import sys, os, hashlib, glob
sys.path.insert(0, os.path.abspath('sim/p4gates'))
import p4gate

root = os.path.abspath('.')
k = p4gate.cfg()
runner = p4gate.resolve(root, k.get('RUNNER', 'sim/p4gates/run_matrix_p4dfix.bat'))
rows = p4gate.parse_gate_calls(runner)
mans = []
for r in rows:
    if r[2] not in mans:
        mans.append(r[2])
compile_set = []
for mn in mans:
    res, _ = p4gate.read_manifest(root, os.path.join(p4gate.GATES_DIR, mn))
    for p in res:
        rp = os.path.normpath(p)
        if rp not in compile_set:
            compile_set.append(rp)
print('sample cs', compile_set[:3])
hls_dir = os.path.join(root, k.get('HLS', ''))
hls = []
for ext in ('*.v', '*.dat'):
    hls.extend(sorted(glob.glob(os.path.join(hls_dir, ext))))
extra = []
for g in p4gate.split_list(k.get('FINGERPRINT_GLOBS')):
    for p in sorted(glob.glob(os.path.join(root, g))):
        if os.path.isfile(p):
            extra.append(p)
allset = []
for p in compile_set + hls + extra:
    rp = os.path.normpath(p)
    if rp not in allset:
        allset.append(rp)
print('compile', len(compile_set), 'hls', len(hls), 'extra', len(extra), 'all', len(allset))
cset = set(compile_set)
hset = set(hls)
lines_c = []
lines_a = []
for p in allset:
    h = p4gate.sha256(p)
    rec = (os.path.relpath(p, root).replace('\\', '/'), h)
    ln = '%s  %s\n' % (h, rec[0])
    lines_a.append(ln)
    if p in cset or p in hset:
        lines_c.append(ln)
d = hashlib.sha256()
for l in sorted(lines_c):
    d.update(l.encode('ascii'))
print('digest_c exact', d.hexdigest(), len(lines_c))
d2 = hashlib.sha256()
for l in sorted(lines_a):
    d2.update(l.encode('ascii'))
print('digest_a exact', d2.hexdigest(), len(lines_a))
