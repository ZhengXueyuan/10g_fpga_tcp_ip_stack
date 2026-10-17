# -*- coding: utf-8 -*-
# Tier B link reachability check (HUMAN_LAYER §2-④): relative links in the two Tier B files.
import io, os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
FILES = [
    '_proj_10g/notes/P7B_OPEN_ITEMS.md',
    '_proj_10g/notes/P7B_TL_LEDGER_20261010.md',
]
pat = re.compile(r'\]\(([^)\s]+)\)')
dead = []
total = 0
for rel in FILES:
    path = os.path.join(ROOT, rel)
    s = io.open(path, encoding='utf-8', errors='replace').read()
    for m in pat.finditer(s):
        t = m.group(1)
        if t.startswith(('http://', 'https://', 'mailto:', '#')):
            continue
        t = t.split('#', 1)[0].split('?', 1)[0]
        if not t:
            continue
        total += 1
        cands = [os.path.normpath(os.path.join(ROOT, t)),
                 os.path.normpath(os.path.join(os.path.dirname(path), t))]
        if not any(os.path.exists(c) for c in cands):
            dead.append((rel, t))
print('TIERB_LINKS_TOTAL=%d DEAD=%d' % (total, len(dead)))
for rel, t in dead[:20]:
    print('DEAD %s -> %s' % (rel, t))
sys.exit(0 if not dead else 1)
