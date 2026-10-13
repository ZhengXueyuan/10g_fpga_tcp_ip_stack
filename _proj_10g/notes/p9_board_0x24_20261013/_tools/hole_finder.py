#!/usr/bin/env python3
# hole_finder.py (v2, 2026-10-13 修正版) -- 0x24 内容臂: 在探针切片内定位洞 (起点/长度), 逐个走完
#   ⛔ v1 自伤登记: v1 的 L 搜索把 buf 索引当成 L 直接扫 (未加 j+LH_MAX 偏移) ⇒ 在无洞流里
#      会命中 idx=S+j+16 = "无洞解" ⇒ 报出假"16 B 洞"。v2 修正: 期望 buf 索引 = S + j + LH_MAX + L。
#   模型: 只在 got[i] == buf[S+i] (i<j) / == buf[(S+L)+i] (i>=j) 的单删除形态内走; 不吻合则响亮报出。
#   usage: python hole_finder.py --off OFF --p P --file runs/xxx.bin [--smax 1500000] [--lhmax 131072]
import argparse
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pattern_jump import pattern_at, self_test


def ex(off, n):
    return bytes(b ^ 0xA5 for b in pattern_at(off, n))


def first_mismatch_blocked(got, buf, S):
    """在 got[i] vs buf[S+i] 下找首个失配 (块 4096 -> 逐字节细化); 无失配返回 -1"""
    n = len(got)
    blk = 4096
    j = -1
    for k in range(0, n, blk):
        m = min(blk, n - k)
        if got[k:k + m] != buf[S + k:S + k + m]:
            j = k
            break
    if j < 0:
        return -1
    # ⛔ v2.1 自伤登记: 首版细化写成 `while j>0 and got[j-1]==buf[S+j-1]: j-=1` (向左走) ——
    #    起点 j 是"块首"且块首之前全等 ⇒ 会一路退到 0 (假洞@片首)。正确方向 = 从块首向右走。
    while j < n and got[j] == buf[S + j]:
        j += 1
    return j


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--off", type=int, required=True)
    ap.add_argument("--p", type=int, required=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--smax", type=int, default=1500000)
    ap.add_argument("--lhmax", type=int, default=131072)
    a = ap.parse_args()
    if not self_test():
        return 3
    got = open(a.file, "rb").read()
    need = a.smax + a.lhmax * 3 + len(got) + 64
    buf = ex(a.off + a.p, need)
    win = got[:16]
    c0 = [L for L in range(0, a.smax + 1) if buf[L:L + 16] == win]
    print(f"file={a.file} len={len(got)} P={a.p}")
    print(f"首段候选 S0={c0[:5]} (共 {len(c0)})")
    if not c0:
        print("S0 未找到")
        return 1
    S = c0[0]
    i0 = 0
    holes = []
    while True:
        j = first_mismatch_blocked(got[i0:], buf, S + i0)
        if j < 0:
            print(f"无更多失配 (S={S})")
            break
        j += i0
        # 洞长搜索: 期望 buf 索引 = S + j + LH_MAX + L,  L in [1, LH_MAX]
        if j + a.lhmax + 16 > len(got):
            print(f"⚠️ 洞在 {a.p+j} 但距片尾不足 LH_MAX, 无法定位 (剩余 {len(got)-j} B)")
            holes.append((a.p + j, None))
            break
        win1 = got[j + a.lhmax:j + a.lhmax + 16]
        base_idx = S + j + a.lhmax
        cands = [base_idx + L for L in range(1, a.lhmax + 1) if buf[base_idx + L:base_idx + L + 16] == win1]
        if len(cands) != 1:
            print(f"⚠️ 洞@{a.p+j} 的 L 候选不唯一: {cands[:6]} (共 {len(cands)})")
            holes.append((a.p + j, None))
            break
        L = cands[0] - base_idx
        # 验证: 洞点前后各 32 B 的位移边界
        pre32 = got[j - 32:j] if j >= 32 else got[:j]
        exp_pre = buf[S + j - len(pre32): S + j]
        post_ok = got[j + a.lhmax:j + a.lhmax + 64] == buf[base_idx + L: base_idx + L + 64]
        holes.append((a.p + j, L))
        print(f"洞: 绝对起点 {a.p + j} (片内 {j})  长 L={L}  前置对齐={'OK' if pre32 == exp_pre else 'BAD'}  后置窗口={'OK' if post_ok else 'BAD'}")
        S = S + L
        i0 = j  # 从洞点继续 (该点起已是新位移)
        if len(holes) > 50:
            print("超过 50 个洞, 提前停")
            break
    print(f"== 共定位 {len(holes)} 个洞 ==")
    for pos, L in holes:
        print(f"  pos={pos}  L={L}")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
