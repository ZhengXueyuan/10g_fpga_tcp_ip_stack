#!/usr/bin/env python3
"""P3 fix-round static wiring gate (H-2 / M-9 / M-10).

Rules:
  1. retx_pool_shared owner input is `grant_port` (no `slot_port` port).
  2. wrapper connects win_pool_mgr.o_grant_port -> retx_pool_shared.grant_port.
  3. wrapper's slow_merge2 reset is dp_rst_n (upstream-consistent; M-9).
  4. P11_DUAL has five independent REQUIRES hard gates (M-10).
  5. retx non-owner reads are gated (r_data = ok ? mux : 0).
  6. win_pool_mgr has grant_port / stale / underflow instrumentation.
"""
import argparse
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--wrapper", default="")
    a = ap.parse_args()
    root = pathlib.Path(a.root)
    wpath = pathlib.Path(a.wrapper) if a.wrapper else (root / "board/wrapper_p4.v")
    w = wpath.read_text(encoding="utf-8")
    rp = (root / "rtl/retx_pool_shared.v").read_text(encoding="utf-8")
    wp = (root / "rtl/win_pool_mgr.v").read_text(encoding="utf-8")

    def inst_block(head, endmark="\n    );"):
        i = w.find(head)
        if i < 0:
            return ""
        j = w.find(endmark, i)
        return w[i:j if j >= 0 else i + 4000]

    sm = inst_block("u_slow_merge (")
    rules = [
        ("retx owner port is grant_port",
         "input  wire [7:0]  grant_port," in rp and "input  wire [7:0]  slot_port" not in rp),
        ("wrapper wires o_grant_port -> grant_port",
         ".o_grant_port(wp_grant_port)" in w and ".grant_port(wp_grant_port)" in w),
        ("slow_merge2 reset = dp_rst_n (M-9)",
         ".rst_n(dp_rst_n)" in sm and ".rst_n(reset_n)" not in sm),
        ("P11_DUAL requires DUAL_SFP_A", "P11_DUAL_REQUIRES_DUAL_SFP_A" in w),
        ("P11_DUAL requires P7B_10G", "P11_DUAL_REQUIRES_P7B_10G" in w),
        ("P11_DUAL requires DP_156MHZ", "P11_DUAL_REQUIRES_DP_156MHZ" in w),
        ("P11_DUAL requires APP_MODE", "P11_DUAL_REQUIRES_APP_MODE" in w),
        ("P11_DUAL requires SFP2_MODE_A", "P11_DUAL_REQUIRES_SFP2_MODE_A" in w),
        ("retx non-owner read returns 0",
         "rd0_ok_d2 ? rd0_mux : 64'd0" in rp and "rd1_ok_d2 ? rd1_mux : 64'd0" in rp),
        ("wpm grant_port ownership", "grant_port <= gp_n;" in wp),
        ("wpm stale rel instrumentation", "stat_rel_stale_port" in wp),
        ("wpm underflow instrumentation", "stat_port_win_underflow" in wp),
    ]
    bad = 0
    for name, ok in rules:
        print("P11_P3FIX_RULE %-42s %s" % (name, "OK" if ok else "FAIL"))
        if not ok:
            bad += 1
    if bad:
        print("P11_P3FIX_STATIC FAIL fails=%d" % bad)
        return 1
    print("P11_P3FIX_STATIC PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
