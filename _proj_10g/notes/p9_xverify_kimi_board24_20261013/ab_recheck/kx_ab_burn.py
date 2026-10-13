#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_ab_burn.py — ② 六次交替烧录逐对复核（自写解析器；不复用对方脚本）
import re, os, hashlib, glob, datetime

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "p9_uram_ab_20261014")
BURN = os.path.join(BASE, "burn")

logs = sorted(glob.glob(os.path.join(BURN, "BURN_0x*_S?_20261014_*.txt")))
logs = [l for l in logs if "stdout_copy" not in l]
assert len(logs) == 6, logs
def _epoch(p):
    t = open(p, "rb").read(400).decode("utf-8", errors="replace")
    m = re.search(r"BURN_BEGIN arm=0x\S+ seq=\d+ (\d+\.\d+)", t)
    return float(m.group(1))
logs.sort(key=_epoch)  # 严格按 BURN_BEGIN epoch 时序（= 真实烧录顺序）

EXPECT_SHA = {"0x23": "066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126",
              "0x24": "e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db"}

print("=" * 96)
print("② 烧录链 6/6 逐对复核（时序 = 文件名时间戳序）")
print("=" * 96)

# 独立实算两个位流副本 sha256
print("--- 本组 hashlib 独立实算 burn/ 位流 ---")
for arm in ("0x23", "0x24"):
    p = os.path.join(BURN, f"wrapper_p4_{arm}.bit")
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    print(f"{arm}: {h}  == 期望 {EXPECT_SHA[arm]}: {h == EXPECT_SHA[arm]}")
print()

prev_post = None
allok = True
for i, lg in enumerate(logs, 1):
    t = open(lg, "rb").read().decode("utf-8", errors="replace").replace("\r", "")
    name = os.path.basename(lg)
    arm = re.search(r"arm=(0x\d+)", t).group(1)
    seq = re.search(r"seq=(\d+)", t).group(1)
    pre = re.search(r"^PREBURN_BID_0x04=.*: (0x[0-9a-f]{8})$", t, re.M).group(1)
    post = re.search(r"^BID_0x04=.*: (0x[0-9a-f]{8})$", t, re.M).group(1)
    want = re.search(r"SHA_WANT=([0-9a-f]{64})", t).group(1)
    sumlines = re.findall(r"^([0-9a-f]{64}) \*(\S+\.bit)$", t, re.M)
    bit_mtime = int(re.search(r"TCPREG_BIT_MTIME = (\d+)", t).group(1))
    so = re.search(r"BURN_STDOUT=\S+ mtime=(\d+) T0=(\d+) age=(\d+)s", t)
    high = "End of startup status: HIGH" in t
    done = re.search(r"^TCPREG_PROG_DONE", t, re.M) is not None
    noabort = re.search(r"^TCPREG-ABORT", t, re.M) is None
    lnksta = "Width x4" in t
    bars2 = "identify_bars: 2 BARs: config 1, user 0" in t
    nff0 = "WINDOW_SCAN_NFF=0" in t
    carrier = re.search(r"^CARRIER=(\d)", t, re.M).group(1)
    pathok = (f"wrapper_p4_{arm}.bit" in t) and ("p9_uram_ab_20261014" in t)
    mt = datetime.datetime.fromtimestamp(bit_mtime, datetime.timezone(datetime.timedelta(hours=8)))
    chain_ok = (pre == prev_post) if prev_post else (pre == "0x00000024")  # 首轮烧前 = 板遗留 0x24
    sha_ok = (want == EXPECT_SHA[arm]) and all(h == want for h, _ in sumlines) and len(sumlines) == 2
    five = high and done and pathok and (int(so.group(3)) >= 0) and noabort
    ok = chain_ok and sha_ok and five and int(post, 16) == int(arm, 16) and lnksta and bars2 and nff0 and carrier == "1"
    allok &= ok
    print(f"#{i} {arm} S{seq} [{name}]")
    print(f"    烧前 0x04={pre} (链接续 {'首期望0x24' if prev_post is None else '==上烧后 '+prev_post}: {chain_ok})  烧后 0x04={post}")
    print(f"    sha: WANT==实算==两条sha256sum行 {sha_ok} | 五判据(HIGH/DONE/路径/age={so.group(3)}s/无ABORT)={five} | x4={lnksta} 2BARs={bars2} NFF=0={nff0} carrier={carrier}")
    print(f"    TCPREG_BIT_MTIME={bit_mtime} = {mt.isoformat()} 新鲜={mt.day == 14}")
    prev_post = post
print(f"\n6/6 烧录链逐对 + sha + 五判据 + PCIe: {allok}")
