#!/usr/bin/env python3
"""G-P3-1 负控: 生成 win_pool_mgr 变异件 (每次只改一处).

⚠️ 2026-10-19 (0x2F 时序修复): manager 已从"单大组合块"改为
   "事件 FIFO + 串行三拍事件机"。变异点随之迁移到事件机的
   S_LOAD/S_CALC/S_COMMIT 语句 (语义不变).

mutants (P3 修复轮扩展):
  c18      : ev_up 不把该槽旧配额先回池 (C18 原子归还失效) -> 不变量必红
  pcap     : 去掉 port_cap 夹紧 -> port_win <= port_cap 必红
  dup      : 去掉 rel 时 winq==0 的 stat_rel_dup 计数 -> 重复释放必红
  c18owner : 旧配额属主恒为 port1 (不走 grant_port) -> 跨口臂不变量必红 (H-1)
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

# C18: S_CALC 的 pool+q 前级去掉 +q
emit("c18",
     "    wire [16:0] w_pool_add_q   = s_pool + {1'b0, s_q};",
     "    wire [16:0] w_pool_add_q   = s_pool;")

# port_cap 夹紧去掉
emit("pcap",
     "        if (s_avail < c_g) c_g = s_avail;\n"
     "        if (s_room  < c_g) c_g = s_room;",
     "        if (s_avail < c_g) c_g = s_avail;")

# 重复 rel 计数去掉
emit("dup",
     "                            stat_rel_dup <= stat_rel_dup + 32'd1;",
     "                            ;")

# H-1: C18 old 归属错 (恒 port1)
emit("c18owner",
     "                        s_owner<= (evq_head[3:0] < 4'd8) ? grant_port[evq_head[3:0]]\n"
     "                                                         : 1'b0;",
     "                        s_owner<= 1'b1;")

# H-1: rel 不检查属主 => 接受跨口迟到释放
emit("stale",
     "                        if (s_owner != e_port) begin\n"
     "                            // 非属主口的迟到 rel: 忽略 (H-1)\n"
     "                            stat_rel_stale_port <= stat_rel_stale_port + 32'd1;",
     "                        if (1'b0) begin\n"
     "                            stat_rel_stale_port <= stat_rel_stale_port + 32'd1;")

# M-5: 单读口化 (port0 事件口 = 扫描口)
emit("m5single",
     "    assign winq_rd0b = (winq_rd_id0b < 4'd8) ? winq[winq_rd_id0b] : 16'd0;",
     "    assign winq_rd0b = (winq_rd_id0  < 4'd8) ? winq[winq_rd_id0]  : 16'd0;")
