#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""线速档补测: 逐窗提取 (速率用 samples, 记账用 ACCT/ID*, 来源用 UDP_SUM)。只读日志, 不改任何东西。"""
import re, sys, glob, os

def num(s):
    return int(s, 0) if not s.startswith('0x') else int(s, 16)

def parse(path):
    txt = open(path, encoding='utf-8', errors='replace').read()
    wins = re.split(r'=== WIN ', txt)[1:]
    out = []
    for w in wins:
        tag = w.split()[0]
        rec = {'tag': tag, 'file': os.path.basename(path)}
        m = re.search(r'K=(\d+) NPROC=(\d+) PER=(\d+) MBPS=(\d+)', w)
        if m: rec['K'], rec['nproc'], rec['per'], rec['mbps'] = (int(x) for x in m.groups())
        m = re.search(r'MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) short=(\d+) ended_early=(\d+) read_error=(\d+) secs=([\d.]+)', w)
        if m:
            rec['pc'], rec['reads'], rec['partial'], rec['short'] = (int(m.group(i)) for i in (1,2,3,5))
            rec['ended_early'], rec['read_error'], rec['secs'] = int(m.group(6)), int(m.group(7)), float(m.group(8))
        m = re.search(r'MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+) w70a=(\d+) w70b=(\d+) words0=(\d+) words1=(\d+) dwords=(\d+) K=(\d+)', w)
        if m:
            rec['taken'], rec['dW70'], rec['w70a'], rec['w70b'] = (int(m.group(i)) for i in (2,3,4,5))
            rec['words1'], rec['dwords'] = int(m.group(7)), int(m.group(8))
        m = re.search(r'MIR_STREAM_IDA .*-> (-?\d+)  band=\[0,(\d+)\] closed_a=(\d)', w)
        if m: rec['resA'], rec['bandA'], rec['closedA'] = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m = re.search(r'MIR_STREAM_IDB .*-> (-?\d+)  band=\[0,(\d+)\] closed_b=(\d)', w)
        if m: rec['resB'], rec['bandB'], rec['closedB'] = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m = re.search(r'MIR_STREAM_QUIESCE level_end=(\d+) quiesced=(\d+) premise_level0=(\d+) waited_ms=([\d.]+)', w)
        if m: rec['level_end'], rec['quiesced'], rec['premise'] = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m = re.search(r'MIR_VERIFY rc=(\d+) first_mismatch=(-?\d+)', w)
        if m: rec['verify_rc'], rec['fmis'] = int(m.group(1)), int(m.group(2))
        ons = re.search(r'DATA_ONSET=(\S+) \(源起后 ([\d.]+|NONE)s\)', w)
        if ons: rec['onset'] = ons.group(2)
        # 采样序列
        ser = [(float(a), int(b), int(c)) for a, b, c in
               re.findall(r'MIR_STREAM_SAMPLE i=\d+ t=([\d.]+) pc=(\d+) drop=(\d+)', w)]
        if len(ser) >= 3:
            # 速率 = **逐区间瞬时速率的中位数** (避开尾部涓流: 源停后最后几个块只补涓流)
            rates = []
            for (ta, pca, _), (tb, pcb, _) in zip(ser, ser[1:]):
                if tb > ta and pcb > pca:
                    rates.append((pcb - pca) / (tb - ta) / 1e6)
            rates.sort()
            rec['rate_MBps'] = rates[len(rates)//2] if rates else None
            rec['rate_gbps'] = rec['rate_MBps'] * 8 / 1000 if rec.get('rate_MBps') else None
            i0 = next((i for i, s in enumerate(ser) if s[1] > 0), 0)
            rec['t_span'] = ser[-2][0] - ser[i0][0]
            rec['pc_span'] = ser[-2][1] - ser[i0][1]
            # 窗内丢字节 = 末-1 采样 drop - 起始 drop
            rec['drop_win'] = ser[-2][2] - ser[0][2]
        su = re.findall(r'UDP_SUM pkts=(\d+) pay_bytes=(\d+) dur_s=([\d.]+) pps=(\d+) pay_Mbps=([\d.]+) wire_Mbps=([\d.]+)', w)
        rec['src'] = [(int(a), float(c), float(e), float(f)) for a, b, c, d, e, f in su]
        pin = re.findall(r'PIN_CPU=([0-9a-z]+)', w)
        rec['pins'] = pin
        rd = re.search(r'READER_CPUS_ALLOWED=(\S+) READER_CPU=(\S+)', w)
        if rd: rec['reader'] = (rd.group(1), rd.group(2))
        out.append(rec)
    return out

def show(path):
    rs = parse(path)
    print(f"\n##### {os.path.basename(path)}  (windows={len(rs)})")
    print(f"{'win':10s} {'K(GiB)':7s} {'pc(MB)':8s} {'rate(MB/s)':10s} {'Gbps':6s} {'span(s)':7s} {'dW70(MB)':8s} {'d/K%':6s} {'resB':10s} {'resA':9s} {'vfy':4s} {'onset':6s} {'src_agg(pay Mbps)':18s}")
    tot_pc = tot_t = tot_drop = 0.0
    for r in rs:
        K = r.get('K', 0); pc = r.get('pc', 0); span = r.get('rate_MBps') and r.get('t_span') or 0
        agg = sum(x[2] for x in r.get('src', []))
        dK = 100.0 * r.get('dW70', 0) / K if K else 0
        v = ('rc=%d fm=%d' % (r['verify_rc'], r['fmis'])) if 'verify_rc' in r else '-'
        print(f"{r['tag']:10s} {K/2**30:7.2f} {pc/1e6:8.1f} {(r.get('rate_MBps') or 0):10.1f} {(r.get('rate_gbps') or 0):6.2f} "
              f"{r.get('t_span',0):7.3f} {r.get('dW70',0)/1e6:8.2f} {dK:6.2f} {r.get('resB','?'):10} {r.get('resA','?'):9} {v:14s} {r.get('onset','?'):6s} {agg:18.0f}")
        tot_pc += pc; tot_t += r.get('t_span', 0); tot_drop += r.get('drop_win', 0)
    if tot_t:
        print(f"合计: pc={tot_pc/1e9:.3f} GB / 采样跨度={tot_t:.2f} s ⇒ 聚合速率 {tot_pc/1e6/tot_t:.1f} MB/s = {tot_pc*8/tot_t/1e9:.3f} Gbps; 窗内丢合计={tot_drop/1e6:.1f} MB ({100*tot_drop/tot_pc:.2f}%)")
    return rs

if __name__ == '__main__':
    for p in sys.argv[1:]:
        for f in sorted(glob.glob(p)):
            show(f)
