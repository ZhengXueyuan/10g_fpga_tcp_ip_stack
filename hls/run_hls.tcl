#=============================================================================
# udp_hls_10g/hls/run_hls.tcl — 慢路径协议栈 (P4b 修改版) HLS 综合
# 与 udp_hls_eco/run_csynth_only.tcl 同模式 (vitis-run --mode hls --tcl);
# 只 csynth (老 tb 端口列表与新签名不匹配, 不进工程; 功能验证走 xsim 真 RTL)
#=============================================================================

open_project -reset slowstack_prj
# P11 P2-甲: 一个 canonical 网表 —— BOARD_IP_DUAL=1 (同时接受 IP_A/IP_B;
# 对 dst=IP_A 的回包行为与 DUAL=0 功能等价, 见 G8 csim 双二进制)。
# P11 P3 (2026-10-18): P3 网表 = MAX_TCP_CONN=8 + BOARD_IP_DUAL=1。
#   ⚠️ C1 (0x2A) / C3 (0x2D) 回归配置继续用**归档的旧网表** (MAX=3, 无 adv_wnd
#   端口) —— 本脚本产出的是 P3/C4 (0x2F) 用的新网表。旧网表在两处归档:
#   构建目录 hls_archive_single_ip/ (单 IP) 与 P2 构建目录 (双 IP)。
add_files src/udp_echo.cpp -cflags "-DBOARD_IP_DUAL=1 -DMAX_TCP_CONN=8"
set_top udp_echo

open_solution -reset solution1
set_part {xc7k325tffg676-2}
create_clock -period 8 -name default

# Reset: async, active low
config_rtl -reset all -reset_async -reset_level low

puts "\n===== C SYNTHESIS ====="
csynth_design

puts "\n===== CSYNTH DONE ====="
exit
