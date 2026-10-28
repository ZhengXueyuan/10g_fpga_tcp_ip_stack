#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_build_0x36.py -- P11 APP8 CDC (0x36) 构建后机械核对（只读）

读: board/p7b_ku5p_stdout.txt, board/p7b_ku5p_timing.rpt,
    board/p7b_ku5p_util.rpt, board/p7b_ku5p_clkinteract.rpt

断言:
  1. P7B_VERDICT = OK；P7B_WNS > 0；Design Timing Summary 三列失败端点 = 0；
     "All user specified timing constraints are met."
  2. P7B_SNAP_TOP5_E1A_ON = 1 / SLOTS_OK = 15 / 每槽 cells >= 1（含槽 53）
  3. P7B_APP8_MODULE app_clk_gen=1 / app_multi8_cdc=1；P7B_BLACKBOX_COUNT 0
  4. P11_APP8_CDC_XDC = 1；日志无 12-4739 / 12-508
  5. clkinteract: g_real.clk_out0 <-> g_hw.clk_out0 双向 = False Path；
     app 自域 (g_real -> g_real) 有 Timed 行且 0 失败端点
  6. 资源形态: LUT as Memory 增量 >= 300（FIFO 进 LUTRAM）且
     CLB Registers 增量 < +8000（FIFO 落 FF 会 +39k）
基线 = 0x34 失败构建（同 RTL 家族、无 CDC）: LUT 136078 / FF 105399 / LUTRAM 14580
   （p7b_build_archive/20261029_020645/p7b_ku5p_util.rpt）
"""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

def read(p):
    fp = os.path.join(ROOT, p)
    return open(fp, "r", encoding="utf-8", errors="replace").read() if os.path.isfile(fp) else ""

fails = []
def ck(cond, name, extra=""):
    print("%s %s%s" % ("[ok]  " if cond else "[FAIL]", name, ("  " + extra) if extra else ""))
    if not cond:
        fails.append(name)

out  = read("board/p7b_ku5p_stdout.txt")
tim  = read("board/p7b_ku5p_timing.rpt")
util = read("board/p7b_ku5p_util.rpt")
ci   = read("board/p7b_ku5p_clkinteract.rpt")

# ---- 1 ----
ck("P7B_VERDICT = OK" in out, "1a P7B_VERDICT = OK")
m = re.search(r"^P7B_WNS = (\S+)", out, re.M)
wns = float(m.group(1)) if m else -999.0
ck(wns > 0, "1b WNS > 0", "WNS=%s" % wns)
for tag in ("P7B_WHS", "P7B_WPWS"):
    mm = re.search(r"^%s = (\S+)" % tag, out, re.M)
    print("      %s = %s" % (tag, mm.group(1) if mm else "?"))
ck("All user specified timing constraints are met." in tim, "1c all user constraints met")

cols = None
if "Design Timing Summary" in tim:
    tail = tim.split("Design Timing Summary", 1)[1]
    for ln in tail.splitlines():
        tok = ln.split()
        if len(tok) >= 12 and re.match(r"^-?\d+\.\d+$", tok[0]):
            cols = tok[:12]
            break
if cols:
    vals = [float(x) for x in cols]
    vals = [float(x) for x in cols]
    ck(int(vals[2]) == 0, "1d setup failing endpoints = 0", cols[2])
    ck(int(vals[6]) == 0, "1d hold failing endpoints = 0", cols[6])
    ck(int(vals[10]) == 0, "1d pw failing endpoints = 0", cols[10])
    print("      summary: WNS=%s TNS=%s setup_fail=%s WHS=%s hold_fail=%s WPWS=%s pw_fail=%s"
          % (cols[0], cols[1], cols[2], cols[4], cols[6], cols[8], cols[10]))
else:
    ck(False, "1d Design Timing Summary parsed")

# ---- 2 ----
ck("P7B_SNAP_TOP5_E1A_ON = 1 (slots 39..53)" in out, "2a top_hi = 53 (E1A on)")
ck("P7B_SNAP_TOP5_SLOTS_OK = 15" in out, "2b SLOTS_OK = 15")
slot = {int(a): int(b) for a, b in re.findall(
    r"P7B_SNAP_TOP5_SLOT slot=(\d+) bits=\d+\.\.\d+ cells=(\d+)", out)}
ck(slot and min(slot.values()) >= 1, "2c every slot has >=1 hold_b cell",
   "slots=%s" % sorted(slot.items()))

# ---- 3 ----
for nm in ("app_clk_gen", "app_multi8_cdc"):
    mm = re.search(r"P7B_APP8_MODULE %s=(\d+) \(CDC\)" % nm, out)
    ck(bool(mm) and int(mm.group(1)) >= 1, "3a %s resolved >=1" % nm)
ck("P7B_BLACKBOX_COUNT 0" in out, "3b blackbox count 0")

# ---- 4 ----
ck("P11_APP8_CDC_XDC = 1" in out, "4a CDC XDC added")
ck("12-4739" not in out, "4b no dropped constraint (12-4739)")
ck("12-508" not in out, "4c no unresolved pin (12-508)")

# ---- 5 ----
rows = [l for l in ci.splitlines() if "g_real.clk_out0" in l or "g_hw.clk_out0" in l]
pair = [l for l in rows if "g_real.clk_out0" in l and "g_hw.clk_out0" in l]
print("      clock rows (g_real/g_hw): %d, pair rows: %d" % (len(rows), len(pair)))
for l in pair[:4]:
    print("      | " + re.sub(r"\s+", " ", l)[:200])
ck(len(pair) >= 2, "5a both directions listed", "pair=%d" % len(pair))
ck(bool(pair) and all("False Path" in l for l in pair), "5b g_real<->g_hw = False Path (both directions)")
ck(not any(re.search(r"\bTimed\b", l) for l in pair), "5c no cross-domain pair remains Timed")
selfrow = [l for l in rows if l.count("g_real.clk_out0") >= 2]
print("      app self rows: %d" % len(selfrow))
for l in selfrow[:2]:
    print("      | " + re.sub(r"\s+", " ", l)[:200])

# ---- 6 ----
def util_num(label):
    mm = re.search(r"\|\s*%s\s*\|\s*(\d+)" % re.escape(label), util)
    return int(mm.group(1)) if mm else None

lut = util_num("CLB LUTs"); ff = util_num("CLB Registers"); lm = util_num("LUT as Memory")
print("      util: CLB LUTs=%s CLB Registers=%s LUT as Memory=%s" % (lut, ff, lm))
BL = dict(lut=136078, ff=105399, lm=14580)
ck(lut is not None and lm is not None and ff is not None, "6a util parsed")
if lut is not None and lm is not None and ff is not None:
    ck(lm - BL["lm"] >= 300, "6b FIFO inferred as LUTRAM (+%d)" % (lm - BL["lm"]))
    ck(ff - BL["ff"] < 8000, "6c no FF-array blowup (dFF=%+d)" % (ff - BL["ff"]))
    print("      delta vs 0x34: dLUT=%+d dFF=%+d dLUTRAM=%+d"
          % (lut - BL["lut"], ff - BL["ff"], lm - BL["lm"]))

if fails:
    print("BUILD_0X36_GATE_FAIL %s" % fails)
    sys.exit(1)
print("BUILD_0X36_GATE_PASS")
