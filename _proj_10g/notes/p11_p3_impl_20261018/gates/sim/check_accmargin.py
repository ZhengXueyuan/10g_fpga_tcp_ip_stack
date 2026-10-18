#!/usr/bin/env python3
"""H-3 (P3 修复轮): ACC_MARGIN 分口静态判据.

判据 (wrapper_p4.v):
  1. u_tcp_rx  (port0)  .ACC_MARGIN(acc_margin_eff)   <- app_estab_cnt
  2. u_tcp_rx2 (port1)  .ACC_MARGIN(acc_margin_eff1)  <- a2_estab_cnt (本口)
  3. acc_margin_eff1 <= acc_margin_of(acc_margin_n1)
  4. acc_margin_n1 由 a2_estab_cnt 派生
  5. 128KB 预算注释在位 (131072 / 26934) 且 8+0 余量 (310 B) 有记录
  6. wrapper 内含 P11_ACC_MARGIN_SELFCHK (仿真期 n=8 => 3328 断言)
负控: 把 port1 改回 acc_margin_eff => 本检查必须失败。
"""
import argparse
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def block(text, header):
    """从例化头取到顶格缩进的结束行 `    );` (注释里也有 ");", 不能用它截断)."""
    i = text.find(header)
    if i < 0:
        return ""
    j = text.find("\n    );", i)
    return text[i:j if j >= 0 else i + 6000]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wrapper", required=True)
    ap.add_argument("--tag", default="wrapper")
    a = ap.parse_args()
    text = open(a.wrapper, "r", encoding="utf-8", errors="replace").read()

    rules = []
    b0 = block(text, "tcp_rx u_tcp_rx (")
    b1 = block(text, "tcp_rx u_tcp_rx2 (")
    rules.append(("port0 ACC_MARGIN(acc_margin_eff)",
                  ".ACC_MARGIN     (acc_margin_eff)" in b0))
    rules.append(("port1 ACC_MARGIN(acc_margin_eff1)",
                  ".ACC_MARGIN     (acc_margin_eff1)" in b1))
    rules.append(("acc_margin_eff1 uses port1 ESTAB count",
                  "acc_margin_eff1 <= acc_margin_of(acc_margin_n1)" in text))
    rules.append(("acc_margin_n1 derives from a2_estab_cnt",
                  "acc_margin_n1  = (a2_estab_cnt[4:0] == 5'd0)" in text))
    rules.append(("128KB budget documented (131072)",
                  "131072" in text and "98304" in text))
    rules.append(("8+0 residual 26934/310B documented",
                  "26934" in text and "310 B" in text))
    rules.append(("runtime self-check present",
                  "P11_ACC_MARGIN_SELFCHK" in text))

    bad = 0
    for name, ok in rules:
        print("P11_ACC_MARGIN_RULE %-45s %s" % (name, "OK" if ok else "FAIL"))
        if not ok:
            bad += 1
    print("P11_ACC_MARGIN_GATE %s rules=%d fail=%d"
          % (a.tag, len(rules), bad))
    if bad:
        print("P11_ACC_MARGIN_GATE FAIL")
        return 1
    print("P11_ACC_MARGIN_GATE PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
