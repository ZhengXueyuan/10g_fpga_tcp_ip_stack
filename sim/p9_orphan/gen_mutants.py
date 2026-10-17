#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""p9 orphan fix: 生成单元门变异体 (M2..M14; M1 = ORPHAN_LIM 泛型 0, 不需补丁).

每个补丁必须**恰好命中一次** (除 M12 为 2 次), 否则脚本非零退出 (防锚点漂移
后静默生成未变异文件). 输出 = sim/p9_orphan/mutants/mut_<id>.v (module 名不变).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "rtl", "app_ctrl.v")
OUT = os.path.join(HERE, "mutants")

PATCHES = {
    # M2: 删 accrueA 的 snd_wnd != 0
    "M2": [(
        "(rc_state == ST_ESTAB) && (rc_snd_wnd != 16'd0) &&",
        "(rc_state == ST_ESTAB) &&",
        1,
    )],
    # M3: 删 work 的 retx_active 覆盖
    "M3": [(
        "wire        orph_work      = (rc_snd_nxt != rc_snd_una) ||\n"
        "                                 (retx_active && (retx_id == scan_id));",
        "wire        orph_work      = (rc_snd_nxt != rc_snd_una) || (1'b0);",
        1,
    )],
    # M4': 第三因子强制 1 (win_closed || retx -> 1'b1)
    "M4": [(
        "(orph_win_closed || (retx_active && (retx_id == scan_id))) &&",
        "1'b1 &&",
        1,
    )],
    # M5: 删 abort_comb 中止支
    "M5": [(
        "if (orph_abort_comb && orph_active) begin",
        "if (1'b0 && orph_active) begin",
        1,
    )],
    # M6: 删 CAM 清
    "M6": [(
        "if (orph_cam_req && orph_state_done && !scfg_busy &&",
        "if (1'b0 && !scfg_busy &&",
        1,
    )],
    # M7: 通知早于 state gnt (ready 提前)
    "M7": [(
        "wire        orph_ready     = orph_notify_pend;",
        "wire        orph_ready     = orph_cam_req || orph_notify_pend;",
        1,
    )],
    # M8: 删孤儿通知进事件块 (ev_down_i 只留真 ev_down)
    "M8": [(
        "wire        ev_down_i   = ev_down | orph_down_i;",
        "wire        ev_down_i   = ev_down;",
        1,
    )],
    # M9: 删 to_push 的 !orph_down_i 门
    "M9": [(
        "!to_pushed_r && !orph_down_i;",
        "!to_pushed_r;",
        1,
    )],
    # M10: 删 ack_obs 清零
    "M10": [(
        "if (ack_obs) orph_zw_cnt[ack_obs_id] <= 8'd0;",
        "if (1'b0) orph_zw_cnt[ack_obs_id] <= 8'd0;",
        1,
    )],
    # M11: CAM 清 issue 删 orph_state_done
    "M11": [(
        "if (orph_cam_req && orph_state_done && !scfg_busy &&",
        "if (orph_cam_req && !scfg_busy &&",
        1,
    )],
    # M12: 删 !orph_busy (fireA/fireB 两处)
    "M12": [(
        "!orph_busy;",
        "1'b1;",
        2,
    )],
    # M13: orph_down 改组合 (不再走寄存器; 严格 1 拍契约破坏)
    "M13": [(
        "wire        orph_down_i = ORPHAN_EN && orph_down_r;",
        "wire        orph_down_i = ORPHAN_EN && orph_notify_pend;",
        1,
    )],
    # M14: 交接拆两拍 (wait_cam 先清, 下一拍才置 notify_pend)
    "M14": [(
        "                    if (orph_cam_clr_done) begin\n"
        "                        orph_wait_cam    <= 1'b0;\n"
        "                        orph_notify_pend <= 1'b1;\n"
        "                    end",
        "                    if (orph_cam_clr_done) begin\n"
        "                        orph_wait_cam    <= 1'b0;\n"
        "                    end\n"
        "                    else if (!orph_wait_cam && !orph_notify_pend &&\n"
        "                             orph_state_done && !orph_cam_req) begin\n"
        "                        orph_notify_pend <= 1'b1;\n"
        "                    end",
        1,
    )],
}


def main():
    if not os.path.isfile(SRC):
        print("FATAL: source not found: %s" % SRC)
        return 2
    with open(SRC, "r", encoding="utf-8", newline="") as f:
        base = f.read()
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    rc = 0
    for mid in sorted(PATCHES):
        s = base
        for old, new, cnt in PATCHES[mid]:
            n = s.count(old)
            if n != cnt:
                print("FATAL: %s anchor count %d != %d for %r" % (mid, n, cnt, old[:60]))
                rc = 1
                continue
            s = s.replace(old, new)
        path = os.path.join(OUT, "mut_%s.v" % mid)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(s)
        print("WROTE %s (%d bytes)" % (path, len(s)))
    return rc


if __name__ == "__main__":
    sys.exit(main())
