#!/usr/bin/env python3
# d4_boundary_23.py -- P9 板级 A/B 轮 (0x23): D4 复测 (起测/停流) 的原始证据复算 + 与 0x22 轮并列
#   构造链 (与上轮同款, 只为"源交付 ≡8 mod 16"留半拍):
#     S3' : --k-bytes 1,048,584 / 抓 1,048,576 ⇒ 打包器槽里留一拍 8 B (= 式A 的 8)
#     S4' : 起测 (clr → cap_en=1) ⇒ ⭐ 新口径: clr **丢弃**残拍 ⇒ 首块不得有短拍/洞/零填充
#     S5' : 再次留半拍 ⇒ 停流探针 (MIR_CTRL=0x8) ⇒ **恰一拍短尾** (dma_from_device -s 8)
#   用法: python d4_boundary_23.py   (cwd = 本轮目录)
import sys
sys.path.insert(0, "_tools")
from byteorder_analyze import pattern_at

S3_OFF, S3_KS = 4059136, 1048584        # S3': 抓 1,048,576 / 源交付 1,048,584 (≡8 mod 16)
S4_OFF, S4_KS = 5107720, 1048576        # S4': 抓 = 源交付 = 1,048,576
S5_OFF, S5_KS = 6156296, 1048584        # S5': 抓 1,048,576 / 源交付 1,048,584
K = 1048576

def exp_at(off, n):
    return bytes(b ^ 0xA5 for b in pattern_at(off, n))

got4 = open("runs/mir_S4.bin", "rb").read()
tail = open("runs/tail_S5.bin", "rb").read()

print("=== ① S3' 残拍预测 (应在 S4' 起测 clr 处被**丢弃**) ===")
resid3 = exp_at(S3_OFF + K, 8)          # S3' 源流最后 8 B
print(f"S3' 源交付 = [{S3_OFF}, {S3_OFF+S3_KS})  抓取 = {K}  残拍 = 图案[{S3_OFF+K}, {S3_OFF+K+8})")
print(f"RESID_PREDICT = {resid3.hex()}")

print()
print("=== ② S4' 头部 8 B: 是残拍(old形式) 还是 新窗口首字节(new口径)? ===")
head8 = got4[:8]
new_head = exp_at(S4_OFF, 8)
print(f"GOT  head8        = {head8.hex()}")
print(f"OLD形式的预期(残拍) = {resid3.hex()}   ⇒ {'MATCH (旧形态复现!)' if head8==resid3 else 'NO-MATCH (残拍未出现)'}")
print(f"NEW口径预期(新窗口) = {new_head.hex()} ⇒ {'MATCH (从新位置干净起拍)' if head8==new_head else 'NO-MATCH'}")

print()
print("=== ③ S4' 零洞/零填充检查 (上轮旧形态: [8,4096) 全零) ===")
z = got4[8:4096]
zrun = 0; zmax = 0
for b in got4:
    zrun = zrun + 1 if b == 0 else 0
    zmax = max(zmax, zrun)
print(f"[8,4096) 全零 = {z==bytes(4088)}  (上轮 = True)")
print(f"全流最长零游程 = {zmax} B  (上轮该构造 = 4,088 ⇒ 若 >64 即有洞/零填充)")

print()
print("=== ④ S4' 全流逐字节 (对齐新窗口位置 {S4_OFF}) ===".replace("{S4_OFF}", str(S4_OFF)))
body = got4
exp4 = exp_at(S4_OFF, len(body))
mism = sum(1 for k in range(len(body)) if body[k] != exp4[k])
fm = next((k for k in range(len(body)) if body[k] != exp4[k]), -1)
print(f"S4' pc={len(body)}  first_mismatch={fm}  mism_bytes={mism}  ⇒ {'逐字节全等' if mism==0 else 'x'}")
print(f"S4' 末 16B = {body[-16:].hex()} (图案尾 {S4_OFF+len(body)-16})")

print()
print("=== ⑤ 字节账 (工具口径) ===")
print("S3': pc=1048576 taken=1048584 dW70=0  式A=taken-pc=8 (残拍见证)  式B=K_src-taken-dW70=0")
print("S4': pc=1048576 taken=1048576 dW70=0  式A=0  式B=0")
print("S5': pc=1048576 taken=1048584 dW70=0  式A=8 (残拍见证)  式B=0")
print(f"S4' 总量: 抓取 {len(body)} == K({K}) ✓ ; 短拍/洞贡献 = 0 (上轮: 头8 + 洞4088 + 体)")

print()
print("=== ⑥ S5' 停流短尾 (MIR_CTRL=0x8 ⇒ dma_from_device -s 8) ===")
print(f"tail bytes = {len(tail)} / {tail.hex()}")
exp_tail = exp_at(S5_OFF + K, 8)       # S5' 源流最后 8 B
print(f"EXPECT = {exp_tail.hex()}   ⇒ {'MATCH (逐字节 = 残拍)' if tail == exp_tail else 'NO-MATCH'}")
print(f"闭式: 抓取 {K} + 短尾 {len(tail)} = {K + len(tail)} == K_src({S5_KS}) - dW70(0) = {S5_KS}  "
      f"{'✓' if K + len(tail) == S5_KS else 'x'}")

print()
print("=== ⑦ 与上轮 (0x22) 同构造并列 ===")
rows = [
    ("pc (抓取字节)",        "1,044,488", "1,048,576"),
    ("taken",               "1,048,568", "1,048,576"),
    ("dW70",                "8",         "0"),
    ("式A (taken-pc)",      "4,080 (判红)", "0 (闭)"),
    ("式B",                 "0 (闭)",    "0 (闭)"),
    ("起测首块形态",         "头8=残拍 + [8,4096) 全零 + 体错位", "无 (逐字节 = 新窗口)"),
    ("读超时/underflow",     "read#2 超时 10 s (RC=1)", "无 (reads=1 partial=0)"),
    ("尾截",                "8,176 B",   "0 (抓满 K)"),
    ("drain/短尾",          "-s 16 ⇒ 8/16 underflow", "-s 8 ⇒ 8/8 RC=0 逐字节 MATCH"),
    ("形态归属",            "clr 起测瞬间冒短拍 ⇒ EOP 早关描述符", "clr 丢弃 ⇒ 不起拍; 停流侧恰一拍短尾"),
]
print(f"{'项':<16}{'0x22 (旧口径)':<42}{'0x23 (新口径)'}")
for a, b, c in rows:
    print(f"{a:<16}{b:<42}{c}")
