#!/usr/bin/env python3
"""tk_snap.py <snap.log> <t0_abs> <tag> -- parse snapshot ring, emit samples + rates."""
import sys, re
D={}
rows=[]
cur=None
for line in open(sys.argv[1], errors='replace'):
    m=re.match(r"SNAP_T (\S+)", line)
    if m: cur=float(m.group(1)); continue
    m=re.match(r"SNAP_BEGIN \S+ gen=(\d+)", line)
    if m: D={}; gen=int(m.group(1)); continue
    m=re.match(r"W(\d+)\s+0x[0-9A-Fa-f]+\s+(\S+)\s+(0x[0-9A-Fa-f]+)", line)
    if m and cur is not None:
        D[int(m.group(1))]=int(m.group(3),16); continue
    if line.startswith("SNAP_END") and D:
        rows.append((cur, D.get(5),D.get(20),D.get(43),D.get(51),D.get(52),D.get(14),D.get(15),D.get(55),D.get(57),D.get(58),D.get(71),D.get(72),D.get(73),D.get(74)))
        cur=None
t0=float(sys.argv[2]); tag=sys.argv[3]
print(f"# {tag}: samples={len(rows)} (W5 W20 W43 W51 W52 W14 W15 W55 W57 W58 W71 W72 W73 W74)")
prev=None
out=open(f"snap_parsed_{tag}.csv","w")
out.write("t_rel,W5,W20,W43,W51,W52,W14,W15,W55,W57,W58,W71,W72,W73,W74\n")
for r in rows:
    t=r[0]-t0
    out.write(("%.3f,"%t)+",".join(str(x) if x is not None else "" for x in r[1:])+"\n")
out.close()
# print E12 event transitions + a few rate windows
print("# E12 transitions (W71..74) and cumulative:")
events=[]
last=None
for r in rows:
    t=r[0]-t0; w71,w72,w73,w74=r[11],r[12],r[13],r[14]
    cur=(w71,w72,w73,w74)
    if last is not None and cur!=last and None not in cur and None not in last:
        events.append((t,last,cur))
    last=cur
for t,a,b in events:
    print(f"  ET t={t:8.3f} {a} -> {b}")
print("# samples every 20s (t, W20, W51, W55, W15, W5):")
i=0
import bisect
ts=[r[0]-t0 for r in rows]
for want in range(0, 460, 20):
    j=bisect.bisect_left(ts, want)
    if j<len(rows):
        r=rows[j]
        print(f"  t={ts[j]:8.2f} W20={r[2]} W51={r[4]} W52={r[5]} W15={r[7]} W55={r[8]} W57={r[9]} W58={r[10]}")
