import os, sys
sys.path.insert(0, r'D:\repo\XCKU5PMini\udp_hls_10g\tools')
import gen_stim_tcp_rx as G
simdir = sys.argv[1]
mode = sys.argv[2] if len(sys.argv) > 2 else 'nostall'
lines, stats, mstat, tcb = G.model(simdir, mode)
print('=== rf cfg2=%s arm=%s (SEQ_RFC=%s) ===' % (G.os.environ.get('SEQRFC_TAIL'), sys.argv[3] if len(sys.argv)>3 else '?', G.SEQ_RFC))
for i, l in enumerate(lines):
    if i >= 60:
        print('%3d: %s' % (i, l))
print('stats', stats)
print('conn0 tcb:', {k: '%08X' % tcb[0][k] if k != 'state' else tcb[0][k] for k in G.FIELDS})
