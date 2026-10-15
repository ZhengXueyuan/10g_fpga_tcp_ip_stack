#!/usr/bin/env python3
# selftest_align_fixed.py -- align_check2 修复件的合成自检（替代"旧 pcap 复算 S0C"门；旧 pcap 不在仓内）
#   依据 = DESIGN_v2.md §5.3 末条："工具修正属于本轮的'仪器'改动：改完先在旧 pcap 上复算 S-0 的
#          S0C（应重现 K0=37960）——复算不出 ⇒ 工具改动有误，判据作废。"
#   ⚠️ 偏差登记：旧 S0C 全帧 pcap（`ghost_S0C_full.pcap0..2`）**不在仓内**（当时在对端 /tmp/p7b_ghost/，
#      对端已重启 ⇒ 被清）⇒ 无法做该复算。本件用**合成 pcap** 做等价+更强的自检（含断点/绝对锚面——
#      那是原版 S0C 复算结构性覆盖不到的面）。
#   五个 case:
#     A) 相位 37960 干净流（= S0C 读数形态）            -> 两工具都应 K0=37960 / breaks=0 / 全流验完
#     B) 残差前缀(r=1440, 旧相位 M=2000000) + pattern[0..] -> orig: 寻不到(UNALIGNED_REST)
#                                                          fixed: newK=0 (abs) / breaks=1 / 全流验完
#     C) 残差前缀 + pattern[1000000..]（非 0 绝对相位）   -> orig: 寻不到；fixed: newK=1000000 (abs) / 全流验完
#     D) 非图案随机流（负对照）                          -> 两工具都应 K0=-1（无读数 = 判据不是恒真）
#     E) 相位变更 +10000 @1440（原版**候选可达**：c=60000 在 ±65536 内）
#        -> orig: 候选找到但**验证无法恢复**（break=3 / verified_prefix=1440 = 基址更新缺陷的直接读数）
#        -> fixed: newK=60000 (abs) / breaks=1 / 全流验完
#   用法: python3 selftest_align_fixed.py <orig.py> <fixed.py> [workdir]
import hashlib
import io
import os
import random
import struct
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SEED = 0x9E3779B97F4A7C15
M64 = (1 << 64) - 1


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


def write_pcap_single_conn(path, stream, sport=8080, dport=54321):
    """把 stream 切成 1460B 段, 写成单连接 pcap (board->peer 方向; 极简 TCP/IP/Eth 头)"""
    base_seq = 0x12345678
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))  # pcap GBL
        for k in range(0, len(stream), 1460):
            pl = stream[k:k + 1460]
            seq = (base_seq + k) & 0xFFFFFFFF
            eth = bytes(12) + struct.pack(">H", 0x0800)
            tcp = struct.pack(">HHIIBBHHH", sport, dport, seq, 0x11223344, (5 << 4), 0x18, 65535, 0, 0) + pl
            tot = 20 + len(tcp)
            ip = struct.pack(">BBHHHBBH", 0x45, 0, tot, 0, 0, 64, 6, 0) + bytes((203, 0, 113, 2)) + bytes((192, 168, 100, 100))
            frame = eth + ip + tcp
            f.write(struct.pack("<IIII", 1600000000 + k // 1460, 0, len(frame), len(frame)) + frame)


def run_tool(tool, pcap, sport="8080"):
    r = subprocess.run([sys.executable, tool, pcap, sport], capture_output=True, text=True, timeout=3600)
    out = r.stdout
    d = {}
    for line in out.splitlines():
        if line.startswith("K0="):
            d["K0"] = int(line.split("=", 1)[1])
        elif line.startswith("BREAK @"):
            d.setdefault("breaks_lines", []).append(line.strip())
        elif line.startswith("  newK="):
            d.setdefault("newK_lines", []).append(line.strip())
        elif line.startswith("ALIGN2_DONE"):
            parts = dict(p.split("=") for p in line.split()[1:])
            d["done"] = {k: int(v) for k, v in parts.items()}
    d["rc"] = r.returncode
    d["stdout_tail"] = "\n".join(out.splitlines()[-3:])
    return d


def main():
    orig, fixed = sys.argv[1], sys.argv[2]
    wd = sys.argv[3] if len(sys.argv) > 3 else "."
    os.makedirs(wd, exist_ok=True)
    R = {}

    N_A = 200000
    print("== case A: 干净流 @phase 37960 (N=%d) ==" % N_A)
    pa = os.path.join(wd, "caseA_phase37960.pcap")
    write_pcap_single_conn(pa, gen_pattern(37960, N_A))
    R["A_orig"], R["A_fixed"] = run_tool(orig, pa), run_tool(fixed, pa)
    print("  orig :", R["A_orig"].get("K0"), R["A_orig"].get("done"))
    print("  fixed:", R["A_fixed"].get("K0"), R["A_fixed"].get("done"))

    M, RR, N_B = 2000000, 1440, 200000
    print("== case B: 残差前缀 r=%d (旧相位 M=%d) + pattern[0..] ==" % (RR, M))
    pb = os.path.join(wd, "caseB_resid_then_phase0.pcap")
    write_pcap_single_conn(pb, gen_pattern(M, RR) + gen_pattern(0, N_B))
    R["B_orig"], R["B_fixed"] = run_tool(orig, pb), run_tool(fixed, pb)
    print("  orig :", R["B_orig"].get("K0"), R["B_orig"].get("done"), R["B_orig"].get("newK_lines"))
    print("  fixed:", R["B_fixed"].get("K0"), R["B_fixed"].get("done"), R["B_fixed"].get("newK_lines"))

    C = 1000000
    print("== case C: 残差前缀 r=%d (旧相位 M=%d) + pattern[%d..] ==" % (RR, M, C))
    pc = os.path.join(wd, "caseC_resid_then_phaseC.pcap")
    write_pcap_single_conn(pc, gen_pattern(M, RR) + gen_pattern(C, N_B))
    R["C_orig"], R["C_fixed"] = run_tool(orig, pc), run_tool(fixed, pc)
    print("  orig :", R["C_orig"].get("K0"), R["C_orig"].get("done"), R["C_orig"].get("newK_lines"))
    print("  fixed:", R["C_fixed"].get("K0"), R["C_fixed"].get("done"), R["C_fixed"].get("newK_lines"))

    print("== case D: 随机流（负对照: 判据不是恒真/恒假） ==")
    rnd = random.Random(12345)
    pd = os.path.join(wd, "caseD_random.pcap")
    write_pcap_single_conn(pd, bytes(rnd.randrange(256) for _ in range(50000)))
    R["D_orig"], R["D_fixed"] = run_tool(orig, pd), run_tool(fixed, pd)
    print("  orig :", R["D_orig"].get("K0"), "  fixed:", R["D_fixed"].get("K0"))

    N_E = 100000
    print("== case E: 相位变更 +10000 @%d（原版候选**可达**） ==" % RR)
    pe = os.path.join(wd, "caseE_origfindable.pcap")
    write_pcap_single_conn(pe, gen_pattern(50000, RR) + gen_pattern(60000, N_E))
    R["E_orig"], R["E_fixed"] = run_tool(orig, pe), run_tool(fixed, pe)
    print("  orig :", R["E_orig"].get("K0"), R["E_orig"].get("done"), R["E_orig"].get("newK_lines"))
    print("  fixed:", R["E_fixed"].get("K0"), R["E_fixed"].get("done"), R["E_fixed"].get("newK_lines"))

    def expect(cond, msg):
        print(("  [ ok ] " if cond else "  [FAIL] ") + msg)
        return 0 if cond else 1

    fails = 0
    print("== 期望表 ==")
    # A: 干净流两工具同读数（对照: 旧工具在 S0C 形态上的能力; 修复不回归）
    fails += expect(R["A_orig"].get("K0") == 37960 and R["A_orig"]["done"] == {"verified_prefix": N_A, "n": N_A, "breaks": 0},
                    "A_orig : K0=37960 / breaks=0 / 全流验完（= 旧 pcap S0C 门在合成件上的等价复算）")
    fails += expect(R["A_fixed"].get("K0") == 37960 and R["A_fixed"]["done"] == {"verified_prefix": N_A, "n": N_A, "breaks": 0},
                    "A_fixed: 同上（修复不回归干净流路径）")
    # B/C: 绝对相位（0 与 1000000）
    fails += expect(R["B_orig"].get("newK_lines") and "None" in R["B_orig"]["newK_lines"][0]
                    and R["B_orig"]["done"]["verified_prefix"] <= RR + 8,
                    "B_orig : 断点后寻不到（UNALIGNED_REST; c=0 在相对候选范围外）")
    fails += expect(R["B_fixed"]["done"] == {"verified_prefix": RR + N_B, "n": RR + N_B, "breaks": 1}
                    and R["B_fixed"]["newK_lines"] == ["newK=0 new_pos=%d how=abs" % RR],
                    "B_fixed: newK=0 (abs) / breaks=1 / 全流验完（绝对锚+基址 = 能落到相位 0 并继续）")
    fails += expect(R["C_orig"].get("newK_lines") and "None" in R["C_orig"]["newK_lines"][0]
                    and R["C_orig"]["done"]["verified_prefix"] <= RR + 8,
                    "C_orig : 非 0 绝对相位同样寻不到")
    fails += expect(R["C_fixed"]["done"] == {"verified_prefix": RR + N_B, "n": RR + N_B, "breaks": 1}
                    and R["C_fixed"]["newK_lines"] == ["newK=%d new_pos=%d how=abs" % (C, RR)],
                    "C_fixed: newK=%d (abs) / breaks=1 / 全流验完" % C)
    # D: 负对照
    fails += expect(R["D_orig"].get("K0") == -1 and R["D_fixed"].get("K0") == -1,
                    "D: 随机流两工具都 K0=-1（判据不是恒真）")
    # E: 基址更新缺陷的直接读数（原版候选可达但停摆）
    fails += expect(R["E_orig"].get("newK_lines") and R["E_orig"]["newK_lines"][0] == "newK=60000 new_pos=%d" % RR
                    and R["E_orig"]["done"]["verified_prefix"] == RR and R["E_orig"]["done"]["breaks"] == 3,
                    "E_orig : 候选 newK=60000 找到过（±65536 内）但验证停在 %d、breaks=3 ⇒ 原版基址更新缺陷" % RR)
    fails += expect(R["E_fixed"]["done"] == {"verified_prefix": RR + N_E, "n": RR + N_E, "breaks": 1}
                    and R["E_fixed"]["newK_lines"] == ["newK=60000 new_pos=%d how=abs" % RR],
                    "E_fixed: 同激励下 breaks=1 / 全流验完 ⇒ 修复面（相对候选也可以，本件走 abs 分支）")
    print("SELFTEST_ALIGN_FAILS=%d" % fails)
    print("SELFTEST_ALIGN_%s" % ("PASS" if fails == 0 else "FAIL"))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
