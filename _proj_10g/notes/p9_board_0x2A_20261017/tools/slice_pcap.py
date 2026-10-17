#!/usr/bin/env python3
# slice_pcap.py IN OUT T0 T1 -- keep records with T0 <= t <= T1 (same link type)
import struct, sys
inp, outp, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
f = open(inp, 'rb'); gh = f.read(24)
magic = gh[:4]
if magic == b'\xd4\xc3\xb2\xa1': endian = '<'; nano = False
elif magic == b'\xa1\xb2\xc3\xd4': endian = '>'; nano = False
elif magic == b'\x4d\x3c\xb2\xa1': endian = '<'; nano = True
elif magic == b'\xa1\xb2\x3c\x4d': endian = '>'; nano = True
else: print('BAD_MAGIC'); sys.exit(2)
o = open(outp, 'wb'); o.write(gh)
n = k = 0
while True:
    rh = f.read(16)
    if len(rh) < 16: break
    ts, tu, incl, orig = struct.unpack(endian + 'IIII', rh)
    data = f.read(incl)
    if len(data) < incl: break
    n += 1
    t = ts + tu / (1e9 if nano else 1e6)
    if t0 <= t <= t1:
        o.write(rh); o.write(data); k += 1
o.close()
print('SLICED in=%d out=%d' % (n, k))
