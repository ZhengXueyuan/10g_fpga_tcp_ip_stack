#!/usr/bin/env python3
"""G-P3-1b 负控: app_ctrl 统一释放表达式的变异件 (每次只改一处).

mutants:
  noevd  : 去掉 ev_down_i 释放项 (外部 DEL / 孤儿路径漏还)
  noto   : 去掉 to_fire 释放项 (关闭超时漏还)
  nost   : 去掉 st_req_now 释放项 (abort/宽限兜底漏还)
  dup    : 去掉 ev_down_i 的 winq!=0 门 (重复释放 -> stat_rel_dup)
"""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]
src = (root / "rtl" / "app_ctrl.v").read_text(encoding="utf-8")
outdir = pathlib.Path(__file__).resolve().parent / "mut"
outdir.mkdir(exist_ok=True)

BLK = """    assign o_quota_rel = EXT_QUOTA && !ev_up &&
                         ((ev_down_i  && (winq_q_evd  != 16'd0)) ||
                          (to_fire    && (winq_q_scan != 16'd0)) ||
                          (st_req_now && (winq_q_scan != 16'd0)));"""
assert src.count(BLK) == 1, "o_quota_rel block not found verbatim"

def emit(name, new):
    p = outdir / f"app_ctrl_{name}.v"
    p.write_text(src.replace(BLK, new, 1), encoding="utf-8", newline="\n")
    print(f"MUT {name} -> {p}")

HDR = "    assign o_quota_rel = EXT_QUOTA && !ev_up &&\n"

emit("noevd",
     HDR + """                         ((to_fire    && (winq_q_scan != 16'd0)) ||
                          (st_req_now && (winq_q_scan != 16'd0)));""")
emit("noto",
     HDR + """                         ((ev_down_i  && (winq_q_evd  != 16'd0)) ||
                          (st_req_now && (winq_q_scan != 16'd0)));""")
emit("nost",
     HDR + """                         ((ev_down_i  && (winq_q_evd  != 16'd0)) ||
                          (to_fire    && (winq_q_scan != 16'd0)));""")
emit("dup",
     HDR + """                         ((ev_down_i) ||
                          (to_fire    && (winq_q_scan != 16'd0)) ||
                          (st_req_now && (winq_q_scan != 16'd0)));""")
