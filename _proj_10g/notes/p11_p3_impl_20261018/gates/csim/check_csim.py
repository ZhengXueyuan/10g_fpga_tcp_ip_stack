#!/usr/bin/env python3
"""M-2: HLS csim 机器判据 — 失败集合必须等于 P2 前基线三条.

基线 (与 P2 轮 gates/base_out.txt 同一集合; 既有, 本轮未修):
  1. TCP SYN -> SYN-ACK (handshake)      : "FAIL: got SYN-ACK"
  2. TCP echo multi-MSS                  : "FAIL: all 2000 echo bytes received"
  3. TCP echo 536B segment               : "FAIL: got SYN-ACK"
⇒ FAIL 行的多重集 = {got SYN-ACK x2, all 2000 echo bytes received x1}, total 3.

退出码: 0 = 与基线一致 (含预期 XFAIL); 1 = unexpected 失败 / 数量不符 / 解析失败.
"""
import argparse
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASELINE = {
    "got SYN-ACK": 2,
    "all 2000 echo bytes received": 1,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    txt = open(a.out, "r", encoding="utf-8", errors="replace").read()
    m = re.search(r"P11_SUMMARY\s+passed=(\d+)\s+failed=(\d+)", txt)
    if not m:
        print("CSIM_BASELINE FAIL no-P11_SUMMARY")
        return 1
    passed, failed = int(m.group(1)), int(m.group(2))
    fails = [ln.strip()[len("FAIL:"):].strip()
             for ln in txt.splitlines() if ln.strip().startswith("FAIL:")]
    got = {}
    for f in fails:
        got[f] = got.get(f, 0) + 1
    print("CSIM_BASELINE out=%s passed=%d failed=%d fail_lines=%d"
          % (a.out, passed, failed, len(fails)))
    for k in sorted(set(list(got) + list(BASELINE))):
        print("CSIM_FAIL_ITEM %-40s got=%d baseline=%d"
              % (k, got.get(k, 0), BASELINE.get(k, 0)))
    ok = (failed == 3) and (passed >= 51) and (got == BASELINE)
    if ok:
        print("CSIM_BASELINE_OK (3/3 = P2 baseline XFAIL set)")
        return 0
    print("CSIM_BASELINE UNEXPECTED (failed set differs from baseline)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
