#!/usr/bin/env python3
# patch_align_check2.py -- 生成 align_check2_fixed.py（唯一改动 = 断点后重对齐改【绝对锚】+ 窗口 257→65536）
#   依据 = `p9_fix_upok_design_20261014/DESIGN_v2.md` §5.3-②（M-6 采信版）逐字：
#     "修法 = 重对齐改绝对锚（或 `d` 扩到含 `−(K0+j)` 的绝对扫描）+ 把搜索窗口从 257 B 放宽"
#   纪律：每个锚点必须**恰命中 1 次**，否则**响亮失败**（不落盘半成品）。
#   用法: python3 patch_align_check2.py <orig.py> <out.py>
import hashlib
import io
import sys

BASE_SHA = "6e04d6b13a7d97ae79a9f75fa2c0bfaeee474a6b8c714d2e4b6df6ce72e94b6d"

try:  # GBK 控制台下 print 非 ASCII 会抛 UnicodeEncodeError（本工程坑 16）
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

# ---- 锚 A: 表头变更说明块（插在 "用法" 行与 import 之间） ----
A_OLD = "#   用法: python3 align_check2.py <pcap...> <sport>\nimport struct, sys\n"
A_NEW = """# 用法: python3 align_check2_fixed.py <pcap...> <sport>
#
# ==== 相对原版的唯一改动（依据 = DESIGN_v2.md §5.3-②，M-6 采信版） ====
#   原文逐字："真缺口 = 断点后的重对齐（:119-127: c = K0 + j ± d, d ∈ [0, 65536]，且只在
#   bp..bp+257 窗口内找）⇒ 结构性到不了'绝对相位 0'（S0A 的 UNALIGNED_REST 即此）
#   ⇒ 修法 = 重对齐改绝对锚（或 d 扩到含 −(K0+j) 的绝对扫描）+ 把搜索窗口从 257 B 放宽"
#   ★ 改动 1 = 断点后重对齐新增【绝对锚分支】：在图案绝对偏移 [0, 2^22] 内直扫 32 字节窗
#     （与首扫 head=gen_pattern(0,1<<22) 同界；= DESIGN.md(v1) §5.3 的"绝对偏移 0..2^22 扫描"）。
#   ★ 改动 2 = 重对齐搜索窗口 257 → 65536（与 d 同量级；设计件未给数值，取值登记在轮报告）。
#   ★ 改动 3 = 重对齐命中后的【基址更新】`K0 = newK` → `K0 = newK - j2`。
#     【本件实测发现（设计件未写）】原版在 j2>0 时结构性无法恢复验证：`align_ok(i,.,K)` 的口径是
#     "K = 流位置 0 处的相位"（首扫 K0=head.find(w0) 即此义），而重对齐命中 (j2, newK=c) 后置
#     `K0 = c` 后，下一轮比较的是 PAT[c + i] vs buf[i]，在 i=j2 处必失配 ⇒ 同拍再断、三连后停
#     （实测 case E：原版与"只加绝对锚"的中间版都停在 verified_prefix=1440 / breaks=3，且重复打印
#     同一个 newK）。正确基址 = c − j2 ⇒ 改动 3 才让"重对齐"在**可观测意义上**成立（能继续验证到流尾）。
#     ⇒ 三处改动 = 一个整体（绝对锚 + 窗口 + 基址）；若只认前两处，后两处的能力差异见轮报告"偏差"节。
#   ★ 改动 4 = 【图案生成长度】`K0 + n` → `ABS_HEAD + n + 2*REALIGN_WIN + 32`。
#     【本件实测发现（设计件未写）】改动 3 把基址挪到新相位后，图案必须覆盖"新相位 + 流长"；
#     原版按初相位生成 ⇒ 当重对齐落点的相位-at-0 > 初相位时（前向相位跳变 / 绝对锚落点），
#     流尾会撞上 PAT 越界 ⇒ **假断点**（实测 case E：BREAK @92873 = PAT 耗尽点、newK=None）。
#     新长度覆盖：abs 分支 c ≤ 2^22 ⇒ 基址 ≤ 2^22；rel 分支 c ≤ K0+j+65536 ≤ K0+W+65536
#     ⇒ 基址 + n ≤ ABS_HEAD + n + 2*REALIGN_WIN（K0 ≤ 2^22-32 恒成立，见首扫界）。
#   ★ 旧式相对候选（K0+j±d, d∈[0,65536]）原样保留为【兜底】：仅当绝对锚扫不到才走。
#   ⚠️ 首扫 K0 = head.find(w0) 未动（M-6 现核：它本来就是绝对的）；头上限 4 MB 未动（§5.3-③ 登记不修）。
#   ⚠️ 输出仅 newK 行追加一个诊断字段（abs/rel）；既有字段一个未改。
import struct, sys
"""
A_NEW = A_NEW.replace("±", "±").replace("∈", "∈").replace("⇒", "⇒").replace("→", "→")

# ---- 锚 B: 新增两个常量 ----
B_OLD = "M64 = (1 << 64) - 1\nCH = 65536\n"
B_NEW = ("M64 = (1 << 64) - 1\nCH = 65536\n"
         "ABS_HEAD = (1 << 22) + 32   # 绝对锚扫描面 = 图案绝对偏移 [0, 2^22]（§5.3-② / 与首扫同界）\n"
         "REALIGN_WIN = 65536          # 断点后重对齐窗口（原版 = 257；本件按 §5.3-② 放宽）\n")

# ---- 锚 C: 重对齐块（原 :117-130） ----
C_OLD = """        newK = None
        j2 = None
        for j in range(bp, min(n - 32, bp + 257)):
            w = bytes(buf[j:j + 32])
            for d in range(0, 65537):
                for c in (K0 + j + d, K0 + j - d):
                    if 0 <= c <= len(PAT) - 32 and PAT[c:c + 32] == w:
                        newK = c
                        break
                if newK is not None:
                    break
            if newK is not None:
                j2 = j
                break
        print("  newK=%s new_pos=%s" % (newK, j2), flush=True)
"""
C_NEW = """        newK = None
        j2 = None
        how = None
        for j in range(bp, min(n - 32, bp + REALIGN_WIN)):
            w = bytes(buf[j:j + 32])
            # (1) 绝对锚分支（新增）: 图案绝对偏移 [0, 2^22] 直扫 —— 能落到绝对相位（含 0）
            c = PAT.find(w, 0, min(len(PAT), ABS_HEAD))
            if c >= 0:
                newK = c
                how = "abs"
            else:
                # (2) 原相对候选（兜底, 未改）: K0+j±d, d ∈ [0, 65536]
                for d in range(0, 65537):
                    for c in (K0 + j + d, K0 + j - d):
                        if 0 <= c <= len(PAT) - 32 and PAT[c:c + 32] == w:
                            newK = c
                            how = "rel"
                            break
                    if newK is not None:
                        break
            if newK is not None:
                j2 = j
                break
        print("  newK=%s new_pos=%s how=%s" % (newK, j2, how), flush=True)
"""


# ---- 锚 D: 重对齐命中后的基址更新（改动 3） ----
D_OLD = """        if newK is None or len(breaks) >= 3:
            break
        K0 = newK
        i = j2
"""
D_NEW = """        if newK is None or len(breaks) >= 3:
            break
        K0 = newK - j2   # 改动 3: 基址 = 流位置 0 处的新相位 (原版 = newK 本身 ⇒ j2>0 时结构性停摆)
        i = j2
"""

# ---- 锚 E: 图案生成长度（改动 4） ----
E_OLD = "    PAT = gen_pattern(0, K0 + n)\n"
E_NEW = "    PAT = gen_pattern(0, ABS_HEAD + n + 2 * REALIGN_WIN + 32)   # 改动 4: 覆盖'重对齐后基址 + 流长'\n"


def main():
    src, dst = sys.argv[1], sys.argv[2]
    raw = open(src, "rb").read()
    got = hashlib.sha256(raw).hexdigest()
    if got != BASE_SHA:
        print("ANCHOR-BASE-FAIL: base sha256 = %s != %s（基件不对, 拒绝）" % (got, BASE_SHA))
        return 1
    s = raw.decode("utf-8")
    n_new = 0
    for name, old, new in (("A", A_OLD, A_NEW), ("B", B_OLD, B_NEW), ("C", C_OLD, C_NEW),
                           ("D", D_OLD, D_NEW), ("E", E_OLD, E_NEW)):
        n = s.count(old)
        print("anchor %s hits=%d" % (name, n))
        if n != 1:
            print("ANCHOR-FAIL (%s): 命中 %d 次 != 1 ⇒ 拒绝落盘" % (name, n))
            return 1
        s = s.replace(old, new)
        n_new += 1
    out = s.encode("utf-8")
    open(dst, "wb").write(out)
    print("PATCH_OK hits=5/5 out=%s sha256=%s bytes=%d" % (dst, hashlib.sha256(out).hexdigest(), len(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
