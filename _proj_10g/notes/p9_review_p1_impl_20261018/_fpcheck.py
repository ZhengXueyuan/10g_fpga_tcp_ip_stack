import re, os, hashlib, glob

root = os.getcwd()
txt = open('sim/p4gates/run_matrix_p4dfix.bat', encoding='latin-1').read()
rows = []
for ln in txt.splitlines():
    m = re.match(r'\s*call :gate\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', ln, re.I)
    if m:
        rows.append(m.groups())
print('gates', len(rows))
mans = []
for r in rows:
    if r[2] not in mans:
        mans.append(r[2])
print('manifests', mans)
cs = set()
for mn in mans:
    p = os.path.join('sim/p4gates', mn)
    if not os.path.isfile(p):
        print('missing', p)
        continue
    for l in open(p, encoding='latin-1'):
        l = l.strip()
        if not l or l.startswith('#'):
            continue
        cs.add(os.path.normpath(l))
print('compile_set', len(cs))
hls = []
hd = 'hls/slowstack_prj/solution1/syn/verilog'
for ext in ('*.v', '*.dat'):
    hls += sorted(glob.glob(os.path.join(hd, ext)))
print('hls', len(hls))


def rows_of(p):
    d = {}
    for ln in open(p, encoding='latin-1'):
        m = re.match(r'SHA256 ([0-9a-f]{64})  (.+?)  (\d+)  (\d+)\s*$', ln)
        if m:
            d[m.group(2)] = m.group(1)
    return d


run = rows_of('sim/p4sim/P4_MATRIX_FINGERPRINT_20261018_014237_before.txt')
now = rows_of('_proj_10g/notes/p9_review_p1_impl_20261018/fp_now.txt')
print('run files', len(run), 'now files', len(now), 'same hashset', run == now)


def digest_c(files, cs, hls):
    hlsrel = set(os.path.normpath(x) for x in hls)
    lines = []
    for p in files:
        rp = os.path.normpath(p)
        if rp in cs or rp in hlsrel:
            lines.append('%s  %s\n' % (files[p], rp.replace('\\', '/')))
    d = hashlib.sha256()
    for l in sorted(lines):
        d.update(l.encode('ascii'))
    return d.hexdigest(), len(lines)


print('digest_c(current cs) =', digest_c(run, cs, hls))
print('cs not in run:', len(cs - set(run)))
for x in sorted(cs - set(run))[:20]:
    print('  ', x)
hlsrel = set(os.path.normpath(x) for x in hls)
extra = [k for k in run if os.path.normpath(k) not in cs and os.path.normpath(k) not in hlsrel]
print('run not in cs/hls:', len(extra))
print('\n'.join(extra[:60]))
