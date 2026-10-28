#=============================================================================
# ku5p_p7b_app8_cdc.xdc -- P11 APP8 CDC 构建 (0x36/0x37) 的跨域约束
#=============================================================================
# 设计件 = _proj_10g/notes/p11_app8_cdc_20261029/DESIGN.md v5 §2.2。
#
# 只在该构建 (P11_APP8_CDC=1) 加入；构建脚本标 `used_in_synthesis false`。
# 不写 set_clock_groups：clk_app 是 sys_clk_100 的 generated clock，重组 group 会有
# "同一 clock 进两个 group" 的风险。这里只加双向 set_false_path（唯一承力切割）。
#
# ⚠️ 引脚名必须是**综合后的层次名**（2026-10-29 由 synth DCP 实测，见
#    sta/query_mmcm.tcl）：
#      u_appclkgen/g_real.u_mmcm/CLKOUT0   (app_clk_gen 的 generate g_real)
#      u_clkgen/g_hw.u_mmcm/CLKOUT0        (clk_gen_p6b 的 generate g_hw)
#    ⛔ 0x36 构建 #1 用 `u_*/u_mmcm/CLKOUT0`（漏了 generate 块）⇒ 12-508/12-4739，
#       false_path 被丢弃 ⇒ 该构建作废（build_fail1_0x36/）。
#    改这两行前先重跑 query_mmcm.tcl 取当次综合后的真实名。
#
# ⚠️ 实施后必须核：
#   ① 构建日志无 `Vivado 12-4739`（set_false_path 拿到空对象会静默丢弃）；
#   ② `report_timing -from [get_clocks ...] -to [get_clocks ...]` 为空（定向无路径）；
#   ③ `report_cdc -details` 的白名单与 DESIGN §3 边界表逐行对账。
#=============================================================================
set app_clk_c [get_clocks -of_objects [get_pins u_appclkgen/g_real.u_mmcm/CLKOUT0]]
set dp_clk_c  [get_clocks -of_objects [get_pins u_clkgen/g_hw.u_mmcm/CLKOUT0]]
set_false_path -from $app_clk_c -to $dp_clk_c
set_false_path -from $dp_clk_c  -to $app_clk_c
