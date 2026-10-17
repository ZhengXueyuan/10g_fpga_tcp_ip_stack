import sys, os, hashlib
sys.path.insert(0, os.path.abspath('sim/p4gates'))
import p4gate

class A: pass
a = A()
a.root = os.path.abspath('.')
a.out = None
a.label = 'dbg'
k = p4gate.cfg()
runner = p4gate.resolve(a.root, k.get('RUNNER', 'sim/p4gates/run_matrix_p4dfix.bat'))
rows = p4gate.parse_gate_calls(runner)
print('rows', len(rows), [r[0] for r in rows])
mans = []
for r in rows:
    if r[2] not in mans:
        mans.append(r[2])
print('mans', mans)
cs = []
for mn in mans:
    res, _ = p4gate.read_manifest(a.root, os.path.join(p4gate.GATES_DIR, mn))
    for p in res:
        rp = os.path.normpath(p)
        if rp not in cs:
            cs.append(rp)
print('compile_set', len(cs))
hdir = os.path.join(a.root, k.get('HLS', ''))
import glob
hls = []
for ext in ('*.v', '*.dat'):
    hls.extend(sorted(glob.glob(os.path.join(hdir, ext))))
print('hls', len(hls), 'hdir', hdir)
# check overlap
print('overlap cs/hls', len(set(os.path.normpath(x) for x in cs) & set(os.path.normpath(x) for x in hls)))
# now read rows from fp_now
def rows_of(p):
    d = {}
    for ln in open(p, encoding='latin-1'):
        m = p4gate.re.match(r'SHA256 ([0-9a-f]{64})  (.+?)  (\d+)  (\d+)\s*$', ln)
        if m:
            d[os.path.normpath(m.group(2))] = m.group(1)
    return d
now = rows_of('_proj_10g/notes/p9_review_p1_impl_20261018/fp_now.txt')
csn = set(os.path.normpath(x) for x in cs)
hlsn = set(os.path.normpath(x) for x in hls)
lines = []
for p, h in now.items():
    if p in csn or p in hlsn:
        lines.append('%s  %s\n' % (h, p.replace('\\', '/')))
d = hashlib.sha256()
for l in sorted(lines):
    d.update(l.encode('ascii'))
print('digest_c(import cs)', d.hexdigest(), 'lines', len(lines))
# how many compile files are missing from fp_now
print('cs missing from now', len(csn - set(now)))
print('now not in cs/hls', len(set(now) - csn - hlsn))
for x in sorted(set(now) - csn - hlsn)[:5]:
    print('  extra', x)
