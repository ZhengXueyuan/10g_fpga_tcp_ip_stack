#!/usr/bin/env python3
"""parse_snap_timeline.py -- 从快照环日志 (k0_<TAG>_snap.log) 解析 E12 事件时间线.

用法: python parse_snap_timeline.py <snap.log> [t0_epoch]
输出: 每次计数器变化一行 (+t / dEv / sw_req / apply / up_pend / cum / W51 / W20)
来源件: k0_arm_b4.sh / k0_arm_b4_multi.sh 的每 0.15 s 快照环 (KW 含 71 72 73 74 51 20)。
"""
import re, sys

def main():
    path = sys.argv[1]
    t0 = float(sys.argv[2]) if len(sys.argv) > 2 else None
    ev, cur, t = [], {}, None
    for line in open(path, errors="replace"):
        line = line.strip()
        m = re.match(r"SNAP_T ([\d.]+)", line)
        if m:
            t = float(m.group(1)); continue
        m = re.match(r"W(\d+)\s+\S+\s+(\S+)\s+(0x[0-9a-fA-F]+)", line)
        if m and t is not None:
            w = int(m.group(1)); v = int(m.group(3), 16)
            cur[w] = (t, v)
            if w == 74 and 71 in cur and 51 in cur and 20 in cur:
                ev.append((t, cur[71][1], cur[72][1], cur[73][1], cur[74][1], cur[51][1], cur[20][1]))
    if not ev:
        print("NO_SAMPLES"); return
    base = t0 if t0 is not None else ev[0][0]
    print(f"samples={len(ev)}  first={ev[0][1:5]}  last={ev[-1][1:5]}  span={ev[-1][0]-ev[0][0]:.1f}s")
    prev = None
    for (t, w71, w72, w73, w74, w51, w20) in ev:
        if prev is not None:
            d = (w71 - prev[0], w72 - prev[1], w73 - prev[2], w74 - prev[3])
            if any(d):
                print(f"t={t-base:9.2f}s dEv={d[0]:+d} sw_req={d[1]:+d} apply={d[2]:+d} up_pend={d[3]:+d}"
                      f" | cum=({w71},{w72},{w73},{w74}) | W51={w51:#x} W20={w20:#x}")
        prev = (w71, w72, w73, w74)

if __name__ == "__main__":
    main()
