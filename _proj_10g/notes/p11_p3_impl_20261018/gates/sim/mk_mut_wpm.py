#!/usr/bin/env python3
"""G-P3-1 负控: 生成 win_pool_mgr 变异件 (每次只改一处).

mutants (P3 修复轮扩展):
  c18      : 去掉 port0 ev_up 的旧配额回池 (C18 原子归还) -> 不变量必红
  pcap     : 去掉 port_cap 夹紧 -> port_win <= port_cap 必红
  dup      : 去掉 rel 时 winq==0 的 stat_rel_dup 计数 -> 重复释放必红
  c18owner : port1 ev_up 的 C18 old 仍按**事件端口**扣 (不走 grant_port)
             -> 跨口臂不变量必红 (H-1)
  stale    : rel 不检查属主口 (接受迟到/跨口 rel) -> 新配额被吞/下溢必红 (H-1)
  m5single : port0 的事件读口别名到扫描读口 (单读口化) -> churn 的 M-5 断言必红
"""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]  # repo root
src = (root / "rtl" / "win_pool_mgr.v").read_text(encoding="utf-8")
outdir = pathlib.Path(__file__).resolve().parent / "mut"
outdir.mkdir(exist_ok=True)

def emit(name, old, new, count=1):
    if src.count(old) < count:
        raise SystemExit(f"[MUT FAIL] {name}: pattern not found ({src.count(old)})")
    dst = src.replace(old, new, count) if count else src.replace(old, new)
    p = outdir / f"win_pool_mgr_{name}.v"
    p.write_text(dst, encoding="utf-8", newline="\n")
    print(f"MUT {name} -> {p}")

emit("c18",
     "            if (old_q != 16'd0) begin\n"
     "                pool_n = pool_n + {1'b0, old_q};\n"
     "                if (old_owner != 1'b0) begin",
     "            if (old_q != 16'd0) begin\n"
     "                if (old_owner != 1'b0) begin")

emit("pcap",
     "            if (avail < g) g = avail;\n"
     "            if (room  < g) g = room;\n"
     "            winq_n[ev_up_slot0[2:0]] = g[15:0];",
     "            if (avail < g) g = avail;\n"
     "            winq_n[ev_up_slot0[2:0]] = g[15:0];")

emit("dup",
     "                end else begin\n"
     "                    dup0_c = 1'b1;\n"
     "                end",
     "                end else begin\n"
     "                end")

# H-1: C18 old 归属错 (port1 用事件端口 = 永远 pw1)
emit("c18owner",
     "            old_owner = gp_n[ev_up_slot1[2:0]];",
     "            old_owner = 1'b1;")

# H-1: rel 不检查属主 => 接受跨口迟到释放
emit("stale",
     "            if (gp_n[rel_slot0[2:0]] != 1'b0) begin\n"
     "                stale0_c = 1'b1;\n"
     "            end else begin",
     "            if (1'b0) begin\n"
     "                stale0_c = 1'b1;\n"
     "            end else begin")

# M-5: 单读口化 (port0 事件口 = 扫描口)
emit("m5single",
     "    assign winq_rd0b = (winq_rd_id0b < 4'd8) ? winq[winq_rd_id0b] : 16'd0;",
     "    assign winq_rd0b = (winq_rd_id0  < 4'd8) ? winq[winq_rd_id0]  : 16'd0;")
