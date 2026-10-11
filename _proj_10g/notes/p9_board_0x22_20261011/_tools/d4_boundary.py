#!/usr/bin/env python3
# d4_boundary.py -- P9 板级首测: 起测/停流边界 (D4 形态) 的原始证据逐个复算
#   观测链 (S3 -> S4 -> drain):
#     S3: 源交付 1,048,584 (≡8 mod 16) ⇒ 打包器槽里留一拍 8 B (式 A = 8 见证)
#     S4: 起测瞬间 (clr / cap_en=0→1) 该残拍以**短拍(tlast=1)**冒出 ⇒ 头 8 B 是 S3 的尾巴
#     S4: 该 EOP 关掉第 1 个描述符 ⇒ 该页剩余 4,088 B 是**零洞** (从未被 DMA 写)
#     S4: 体 [4096..) 对齐到图案 3602440, **0 失配** (内容无损, 只是布局有洞 + 尾截)
#     drain: 显式 stop (MIR_CTRL=0x8) ⇒ 打包器再吐一拍 8 B = S4 源流**最后** 8 B (唯一命中 4651008)
#   用法: python d4_boundary.py
import sys
sys.path.insert(0, "_tools")
from byteorder_analyze import pattern_at

S3_OFF, S3_K = 2553856, 1048584          # S3: 抓 1,048,576 / 源交付 1,048,584
S4_OFF, S4_K = 3602440, 1048576          # S4: 抓 = 源交付 = 1,048,576
got4 = open("runs/mir_S4.bin", "rb").read()
N4 = len(got4)
drain = open("runs/drain_S4leftover.bin", "rb").read()

def exp_at(off, n):
    return bytes(b ^ 0xA5 for b in pattern_at(off, n))

print("=== D4 边界链 原始证据 (P9 / 0x22 / 2026-10-11) ===")
print(f"S3: OFF={S3_OFF} 抓取=1,048,576 源交付={S3_K}  ⇒ 残拍预测 = 图案[{S3_OFF+S3_K-8}, {S3_OFF+S3_K})")
print()
print("--- ① S4 抓取流的头 8 B vs S3 残拍预测 ---")
head = got4[:8]
want = exp_at(S3_OFF + S3_K - 8, 8)
print(f"GOT  head8      = {head.hex()}")
print(f"EXP  S3残拍     = {want.hex()}   ⇒ {'MATCH' if head==want else 'NO-MATCH'}")
print()
print("--- ② S4 头之后的零洞 (第 1 个描述符页剩余) ---")
z = got4[8:4096]
print(f"[8,4096) 全零 = {z==bytes(4088)}  (长度 {len(z)} = 4096-8)")
print()
print("--- ③ S4 体 [4096..N) 对齐到图案 {S4_OFF} ---".replace("{S4_OFF}", str(S4_OFF)))
body = got4[4096:]
exp = exp_at(S4_OFF, len(body))
mism = sum(1 for k in range(len(body)) if body[k] != exp[k])
fm = next((k for k in range(len(body)) if body[k] != exp[k]), -1)
print(f"BODY 长度={len(body)}  first_mismatch={fm}  mism_bytes={mism}  ⇒ {'逐字节全等' if mism==0 else 'x'}")
print(f"BODY 末 16B = {body[-16:].hex()} (图案尾 {S4_OFF+len(body)-16})")
print()
print("--- ④ 字节账 (S4 工具口径) ---")
print("pc=1044488  taken=1048568  dW70=8  K=1048576")
print(f"  式B: K - taken - dW70 = {1048576-1048568-8}  (∈[0,24] ✓)")
print(f"  式A: taken - pc = {1048568-1044488}  (∉[0,32] ⇒ 工具正确判红)")
print(f"  头8 + 零洞4088 + 体{len(body)} = {8+4088+len(body)} == pc({N4})")
print(f"  已交付(体) = {len(body)} ; 源流可用 = K-8(丢8) = {1048576-8} ⇒ 尾截 = {1048576-8-len(body)} B")
print()
print("--- ⑤ drain (显式 stop=MIR_CTRL:0x8) 捕到的 8 B ---")
print(f"drain bytes = {len(drain)} / {drain.hex()}")
A, B = 4650000, 4651100
pat = exp_at(A, B - A)
hits = [A + k for k in range(len(pat) - 8) if drain == pat[k:k + 8]]
print(f"唯一命中图案偏移 = {hits}  (S4 源流末字节 off_end={S4_OFF+S4_K})")
print(f"⇒ drain 捕到 = S4 源流最后 8 B = 图案[{S4_OFF+S4_K-8}, {S4_OFF+S4_K})  "
      f"{'MATCH' if hits==[S4_OFF+S4_K-8] else 'NO-MATCH'}")
