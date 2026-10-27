# P11 APP8 0x34 TIMING_FAIL 实验 (2026-10-28) — 新输入，不是"重跑到过"
# 0x34 WNS = -0.337 ns / 6642 setup 端点；最差路径是**既存 DP 族**
#   u_tcp_tx2/u_fifo_b/rptr_reg[0]_replica/C -> u_tcb2/rcv_nxt_r_reg[9][11]/CE
#   (18 级, logic 1.690 ns, route 4.907 ns = 74.4%)。
# 0x33 (1 个 app) 同族 WNS +0.008；0x34 把 8×app_pattern (u_app, 15,328 LUT)
# 放进同一 DP 域后 route 拥塞 => -0.337。本 XDC = 把 u_app 组隔离到器件左下的
# 独立 pblock，让 DP 的 tcb2/ackq/slow_cfg2 路径不再与 8 个 app 实例争布线。
# 判据 = 全构建 P7B_TIMING_GATE (WNS>0 且 0/0/0)；失败则归档、不烧板。
create_pblock p_app8
resize_pblock [get_pblocks p_app8] -add {SLICE_X0Y0:SLICE_X49Y79}
add_cells_to_pblock [get_pblocks p_app8] [get_cells u_app]
