#!/usr/bin/env python3
# capd_analyze.py -- 0x24 内容臂 (CAPD 同款): 首洞定位 + 删除长度 L + 位移后逐字节对账 (独立 LFSR)
#   口径: 镜流 = 图案(off + 绝对位置) ^ 0xA5; 假设形态 = 单次连续删除 L (fm 之后整体位移 L)
#   用法: python capd_analyze.py --off OFF --pc PC --fm FM \
#            [--head f --head-at 0] [--slice f --slice-at S] [--tail f --tail-at T] [--lmax 262144]
import argparse
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pattern_jump import pattern_at, self_test


def ex(off, n):
    return bytes(b ^ 0xA5 for b in pattern_at(off, n))


def fm_and_count(got, exp):
    """返回 (first_mismatch, mism_bytes); 用大整数 XOR 走 C 路径."""
    if len(got) != len(exp):
        raise ValueError("len mismatch")
    x = int.from_bytes(got, "big") ^ int.from_bytes(exp, "big")
    if x == 0:
        return -1, 0
    fm = len(got) - (x.bit_length() + 7) // 8
    try:
        cnt = x.bit_count()
    except AttributeError:
        cnt = bin(x).count("1")
    return fm, cnt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--off", type=int, required=True)
    ap.add_argument("--pc", type=int, required=True)
    ap.add_argument("--fm", type=int, required=True)
    ap.add_argument("--head", default=None)
    ap.add_argument("--head-at", type=int, default=0)
    ap.add_argument("--slice", dest="sl", default=None)
    ap.add_argument("--slice-at", type=int, default=0)
    ap.add_argument("--tail", default=None)
    ap.add_argument("--tail-at", type=int, default=0)
    ap.add_argument("--lmax", type=int, default=262144)
    a = ap.parse_args()

    print("=== ① 图案自检 (p7b_pattern.h 两条向量 + 跳跃版对慢版) ===")
    if not self_test():
        print("FATAL: 自检不过 => 无资格对账")
        return 3
    print("SELFTEST OK (且 pattern_jump 已在 PATTERN_JUMP_SELFTEST.txt 与慢版 11 点对照)")
    print(f"参数: off={a.off} pc={a.pc} fm={a.fm}")

    if a.head:
        got = open(a.head, "rb").read()
        exp = ex(a.off + a.head_at, len(got))
        f, c = fm_and_count(got, exp)
        print(f"--- ② 头部 [{a.head_at}, +{len(got)}) 无位移对账: first_mismatch={f} mism={c}  (期望 0/-1: 洞在 {a.fm})")

    L_found = None
    if a.sl:
        got = open(a.sl, "rb").read()
        pos = a.fm - a.slice_at
        assert pos >= 0, "slice 未覆盖 fm"
        # 洞前区
        exp_pre = ex(a.off + a.slice_at, pos)
        f, c = fm_and_count(got[:pos], exp_pre)
        print(f"--- ③ 切片洞前区 [{a.slice_at}, {a.fm}) 无位移对账: first_mismatch={f} mism={c}  (期望 0/-1)")
        # L 搜索: buf[m] = 图案(off + fm + m) ^ A5
        rest = len(got) - pos
        buf = ex(a.off + a.fm, a.lmax + rest + 32)
        win = got[pos:pos + 16]
        cands = [L for L in range(0, a.lmax + 1) if buf[L:L + 16] == win]
        print(f"--- ④ L 搜索 (窗口 16B): 候选 {cands[:8]}{'...' if len(cands) > 8 else ''} (共 {len(cands)})")
        for L in cands:
            n = min(rest, 65536)
            if got[pos:pos + n] == buf[L:L + n]:
                L_found = L
                break
        if L_found is None and cands:
            L_found = cands[0]
            print("   ⚠️ 首候选 64 KiB 未全过 (可能是复合形态)")
        print(f"--- ⑤ 删除长度 L = {L_found} B  (0x23 基线 = 42,952 B)")
        # 洞后区全量对账 (位移 L)
        exp_post = buf[L_found:L_found + rest]
        got_post = got[pos:]
        f, c = fm_and_count(got_post, exp_post)
        print(f"--- ⑥ 切片洞后区 [{a.fm}, +{rest}) 位移 L 后对账: first_mismatch={f}(切片内) mism={c}  (期望 0/-1)")
        if f >= 0:
            print(f"   ⚠️ 位移后仍有差异 @绝对 {a.fm + f} (第二洞或形态不符)")
        print(f"--- ⑦ 洞边界 dump (绝对 {a.fm} 前后 16B; 左=无位移期望 右=抓取) ---")
        print(f"GOT[{a.fm-16}:{a.fm}] = {got[pos-16:pos].hex()}")
        print(f"EXP[{a.fm-16}:{a.fm}] = {ex(a.off + a.fm - 16, 16).hex()}")
        print(f"GOT[{a.fm}:{a.fm+16}] = {got[pos:pos+16].hex()}")
        print(f"EXP_noShift        = {ex(a.off + a.fm, 16).hex()}")
        print(f"EXP_shift{L_found}        = {buf[L_found:L_found+16].hex()}")

    if a.tail and L_found is not None:
        got = open(a.tail, "rb").read()
        exp = ex(a.off + a.tail_at + L_found, len(got))
        f, c = fm_and_count(got, exp)
        print(f"--- ⑧ 尾区 [{a.tail_at}, +{len(got)}) 位移 L 后对账: first_mismatch={f} mism={c}  (期望 0/-1)")

    print("--- ⑨ 账 ---")
    print(f"pc={a.pc}  fm={a.fm}  L={L_found}  fm+?  L-pc+K 关系交报告层; 本脚本只报形态")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
