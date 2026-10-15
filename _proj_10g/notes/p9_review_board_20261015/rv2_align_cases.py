#!/usr/bin/env python3
# RV2: 自造合成 case 攻 align_check2_fixed.py 的假阴性面（独立于被审件自带 5-case 自检）。
# 生成件写在 本目录/rv2_align_synth/ 下（可复现；同一脚本内联图案生成器，与被审件同公式）。
# 用法: python3 rv2_align_cases.py
import os, struct, subprocess, sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SEED = 0x9E3779B97F4A7C15
M64 = (1 << 64) - 1
WD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rv2_align_synth")
TOOLS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_0x27_k0_20261015", "_tools")
ORIG = os.path.abspath(os.path.join(TOOLS, "align_check2_orig.py"))
FIXED = os.path.abspath(os.path.join(TOOLS, "align_check2_fixed.py"))
SEG = 1460


def gen_pattern(start, n):
    s = SEED
    for _ in range(start):
        s ^= (s << 13) & M64
        s ^= s >> 7
        s ^= (s << 17) & M64
        s &= M64
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s ^= (s << 13) & M64
        s ^= s >> 7
        s ^= (s << 17) & M64
        s &= M64
    return bytes(out)


def write_pcap(path, stream, base_seq=0x12345678, sport=8080, dport=54321, missing_ranges=()):
    """把 stream 按 1460B 切段写 pcap; missing_ranges = [(off, len)] 的字节区间【整段不写】(= 洞)。"""
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        k = 0
        while k < len(stream):
            pl = stream[k:k + SEG]
            skip = any(a <= k and k < a + ln for a, ln in missing_ranges)
            if not skip:
                seq = (base_seq + k) & 0xFFFFFFFF
                eth = bytes(12) + struct.pack(">H", 0x0800)
                tcp = struct.pack(">HHIIBBHHH", sport, dport, seq, 0x11223344, (5 << 4), 0x18, 65535, 0, 0) + pl
                tot = 20 + len(tcp)
                ip = struct.pack(">BBHHHBBH", 0x45, 0, tot, 0, 0, 64, 6, 0) + bytes((203, 0, 113, 2)) + bytes((192, 168, 100, 100))
                frame = eth + ip + tcp
                f.write(struct.pack("<IIII", 1600000000 + k // SEG, 0, len(frame), len(frame)) + frame)
            k += SEG


def run(tool, pcap, timeout=3600):
    r = subprocess.run([sys.executable, tool, pcap, "8080"], capture_output=True, text=True, timeout=timeout)
    lines = [l for l in r.stdout.splitlines() if l and not l.startswith("  ... verified")]
    tail = [l for l in r.stdout.splitlines() if l.startswith("ALIGN2_DONE")]
    return r.returncode, lines[:12] + tail


def show(name, tool_tag, rc, lines):
    print("  [%s] rc=%d" % (tool_tag, rc))
    for l in lines:
        print("      " + l)


def main():
    os.makedirs(WD, exist_ok=True)
    print("== RV2-A: wire 层洞（中段缺失 1 整段, 内容=连续 pattern）==")
    pa = os.path.join(WD, "caseA_hole1seg.pcap")
    write_pcap(pa, gen_pattern(0, 200000), missing_ranges=((50000, SEG),))
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("A", tag, *run(tool, pa))

    print("== RV2-B: 内容丢字 8B（真断点: 线上 = pattern[0:73000]+pattern[73008..], seq 连续）==")
    pb = os.path.join(WD, "caseB_lost8B.pcap")
    write_pcap(pb, gen_pattern(0, 73000) + gen_pattern(73008, 127000))
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("B", tag, *run(tool, pb))

    print("== RV2-C: 真相位跳 @100000 (+23456)（掩蔽候选: 初始 K0 列看不出）==")
    pc = os.path.join(WD, "caseC_phasejump.pcap")
    write_pcap(pc, gen_pattern(0, 100000) + gen_pattern(123456, 100000))
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("C", tag, *run(tool, pc))

    print("== RV2-D: 相位跳 > ABS_HEAD(4MB)（abs 面外; 应响亮'验不完'而非静默通过）==")
    pd = os.path.join(WD, "caseD_jump5MB.pcap")
    write_pcap(pd, gen_pattern(0, 100000) + gen_pattern(5000000, 60000))
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("D", tag, *run(tool, pd))

    print("== RV2-E: 首段缺失（捕获漏头）—— K0 应 ≠0（灵敏度 = arming 门为何承重）==")
    pe = os.path.join(WD, "caseE_misshead.pcap")
    write_pcap(pe, gen_pattern(0, 100000), missing_ranges=((0, SEG),))
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("E", tag, *run(tool, pe))

    print("== RV2-F: 尾段缺失（流短一截）—— 工具能否察觉？==")
    pf = os.path.join(WD, "caseF_shorttail.pcap")
    write_pcap(pf, gen_pattern(0, 100000 - SEG))   # 末尾少一整段, 无任何不连续
    for tag, tool in (("orig", ORIG), ("fixed", FIXED)):
        show("F", tag, *run(tool, pf))


if __name__ == "__main__":
    main()
