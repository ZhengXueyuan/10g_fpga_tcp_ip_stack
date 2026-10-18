#!/usr/bin/env python3
"""M-6: slow merge / demux / cfg demux 负控变异件.

  cfg_w2rev : ADD 按取反的 w2 判口 -> TB arm A 错口 (必红)
  cfg_delw2 : DEL 按 w2 判口 (不按 slot_port) -> TB arm C 错口 (必红)
  sm2_mix   : merge 的 tlast 拍数据取另一口 -> 帧原子断言必红
  sd2_nolock: demux 不锁帧首口 -> 帧内改口时跨口分裂 (TB arm C 必红)
"""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]
outdir = pathlib.Path(__file__).resolve().parent / "mut"
outdir.mkdir(exist_ok=True)

def mutate(fname, out, old, new):
    src = (root / "rtl" / fname).read_text(encoding="utf-8")
    if src.count(old) != 1:
        raise SystemExit("[MUT FAIL] %s: anchor count %d" % (out, src.count(old)))
    (outdir / out).write_text(src.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("MUT %s -> %s" % (out, outdir / out))

mutate("slow_cfg_demux.v", "slow_cfg_demux_w2rev.v",
       "                    end else if (is_add) begin\n"
       "                        dst_port <= ip_b_match;",
       "                    end else if (is_add) begin\n"
       "                        dst_port <= !ip_b_match;")

mutate("slow_cfg_demux.v", "slow_cfg_demux_delw2.v",
       "                    end else if (is_del) begin\n"
       "                        dst_port <= slot_port[slot];",
       "                    end else if (is_del) begin\n"
       "                        dst_port <= ip_b_match;")

mutate("slow_merge2.v", "slow_merge2_mix.v",
       "    assign m_tdata  = sel ? p1_tdata : p0_tdata;",
       "    assign m_tdata  = m_tlast ? (sel ? p0_tdata : p1_tdata) : (sel ? p1_tdata : p0_tdata);")

mutate("slow_demux2.v", "slow_demux2_nolock.v",
       "    wire port_sel = busy ? port_r : s_port;",
       "    wire port_sel = s_port;")
