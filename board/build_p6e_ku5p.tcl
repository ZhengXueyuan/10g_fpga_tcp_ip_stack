#=============================================================================
# ⚠️ **本档已被 P6b 取代** (2026-09-29): wrapper 的双域搬迁与全部 P6b 硬件都包在
#    `ifdef PCIE_OBS 内 ⇒ 本档 (PCIE_OBS=1) 现在**也会**得到 156.25MHz 数据面。
#    本文件里同步补进了 P6b 的三个新 RTL 与两个新 XDC —— 否则新增端口 (sys_clk_p/n)
#    会没有引脚约束 ⇒ 布局/DRC 直接失败。**新构建一律用 `build_p6b_ku5p.tcl`**
#    (它与本档除工程名/报告名外完全一致)。
#=============================================================================
# build_p6e_ku5p.tcl — P6e: **数据面 + 观测通道合体** (KU5P, xcku5p-ffvb676-1-e)
#   基线 = build_p6a_ku5p.tcl 的 t8p0 档 (同文件清单 / 同 APP_MODE / 同器件 / 同策略),
#   增量 = `PCIE_OBS=1` + XDMA IP + axi_regs.v + snap_cdc.v + ku5p_p6e_pcie.xdc。
#   ⇒ 产物 = **一个比特流里同时有 1G 数据面和 PCIe 寄存器窗口**。
# 产物: vivado_prj/p6e_ku5p_prj.runs/impl_1/wrapper_p4.bit
#       + p6e_ku5p_{timing,util,drc}.rpt (+ failing_endpoints.txt)
# ⚠️ 纪律:
#   ① **默认构建 (K7 各档) 与 P6a (无 PCIE_OBS) 的端口表/逻辑必须逐位不变** —— wrapper 里
#      所有 PCIe 内容都包在 `ifdef PCIE_OBS 内 (新增端口也在里面)。
#   ② XDMA IP 参数必须与 `_proj_pcie/build_pcie_min.tcl` **逐字一致** (那份已在板上实测
#      枚举成功 + user BAR 可用); 校验脚本 _proj_pcie/check_xci.py 可核 .xci 持久化。
#   ③ hls_dir 指向**本目录下的副本** (不是 D:/repo/ECO/...)。
#   ④ Vivado batch 出错**不一定**返回非零 ⇒ 成功判据 = 位流文件存在 (bat 里检查)。
#   ⑤ 闸 G 基线是 6.400ns; 本档跑真实 1G 的 8.000ns (裕量更大)。上板前**必须**确认
#      时序报告 0 失败端点 (违例接收端可能正好在读数通路上 ⇒ 静默读错)。
#=============================================================================
set project_name p6e_ku5p_prj
set top_module   wrapper_p4
set part_name    xcku5p-ffvb676-1-e

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file dirname $script_dir]
set hls_dir    ${root_dir}/hls/slowstack_prj/solution1/syn/verilog

puts "===== P6e KU5P build: 数据面 + PCIe/XDMA 观测通道 (t8p0) ====="

create_project -force $project_name ${root_dir}/vivado_prj -part $part_name
import_files -norecurse ${root_dir}/rtl/crc32_8b.v \
                         ${root_dir}/rtl/fifo_sync.v \
                         ${root_dir}/rtl/checksum16.v \
                         ${root_dir}/rtl/frame_fifo.v \
                         ${root_dir}/rtl/mac_rx_64.v \
                         ${root_dir}/rtl/mac_tx_64.v \
                         ${root_dir}/rtl/tcp_cam.v \
                         ${root_dir}/rtl/tcb.v \
                         ${root_dir}/rtl/tcp_rx.v \
                         ${root_dir}/rtl/tcp_tx_frame.v \
                         ${root_dir}/rtl/retx_ram.v \
                         ${root_dir}/rtl/tcp_echo.v \
                         ${root_dir}/rtl/axis_pipe.v \
                         ${root_dir}/rtl/rx_classify.v \
                         ${root_dir}/rtl/vlan_strip.v \
                         ${root_dir}/rtl/slow_rx_adp.v \
                         ${root_dir}/rtl/slow_cfg_adp.v \
                         ${root_dir}/rtl/slow_tx_adp.v \
                         ${root_dir}/rtl/udp_rx.v \
                         ${root_dir}/rtl/udp_split.v \
                         ${root_dir}/rtl/udp_tx_cfg.v \
                         ${root_dir}/rtl/udp_tx_frame.v \
                         ${root_dir}/rtl/tx_arb.v \
                         ${root_dir}/rtl/app_ctrl.v \
                         ${root_dir}/rtl/app_pattern.v \
                         ${root_dir}/rtl/app_udp_pattern.v \
                         ${root_dir}/rtl/app_status_uart.v
# P6e 新增: 观测通道 (相干快照 CDC) + 寄存器块
import_files -norecurse ${root_dir}/rtl/snap_cdc.v ${root_dir}/_proj_pcie/rtl/axi_regs.v
# P6b 增量 (见文件头): 时钟发生器 + 异步 FIFO + 链式快照序列器
import_files -norecurse ${root_dir}/rtl/clk_gen_p6b.v                          ${root_dir}/rtl/fifo_async.v                          ${root_dir}/rtl/snap_seq.v
# 前端: 按 DEV_USP 选 util_gmii_to_rgmii_us (零 IDELAY); 两个文件都导入, wrapper 内 ifdef 选
import_files -norecurse ${script_dir}/wrapper_p4.v ${script_dir}/util_gmii_to_rgmii_us.v \
                         ${script_dir}/util_gmii_to_rgmii.v ${script_dir}/uart_dbg.v
import_files -norecurse [glob -nocomplain ${hls_dir}/*.v]
# HLS $readmemh 系数文件必须与导入后的 verilog 同目录 (综合按相对路径找)
# 2026-10-26: 旧回退式 `imports/verilog/udp_echo.v` 在归档式 HLS 目录下会把
#   `file dirname ""` 变成 "." ⇒ .dat 拷到 CWD、综合读不到 (0x31 板级根因).
#   改为"全 imports 唯一命中" + 硬失败, 不再有 "." 回退.
set hls_imp_hits [glob -nocomplain ${root_dir}/vivado_prj/${project_name}.srcs/sources_1/imports/*/udp_echo.v]
if {[llength $hls_imp_hits] != 1} {
    puts "HLS_IMPORT_DIR_HITS = [llength $hls_imp_hits]"
    puts "P7B_VERDICT = HLS_IMPORT_DIR_MISSING"
    exit 1
}
set src_dir [file dirname [lindex $hls_imp_hits 0]]
foreach dat [glob -nocomplain ${hls_dir}/*.dat] {
    set dst [file join $src_dir [file tail $dat]]
    if {[catch {file copy -force $dat $dst} e]} {
        puts "HLS_DAT_COPY_FAIL $dat -> $dst : $e"
        puts "P7B_VERDICT = HLS_DAT_COPY_FAIL"
        exit 1
    }
    if {![file exists $dst] || [file size $dst] != [file size $dat]} {
        puts "HLS_DAT_COPY_VERIFY_FAIL $dst"
        puts "P7B_VERDICT = HLS_DAT_COPY_VERIFY_FAIL"
        exit 1
    }
}

# ---- XDMA IP: 参数逐字复制 _proj_pcie/build_pcie_min.tcl (板上实测枚举通过) ----
#      ⚠️ 会在工程里生成 IP 产物 (跑一次 ~1-2 min); 之后综合用持久化的 .xci
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set ip [get_ips xdma_0]
set_property -dict [list \
    CONFIG.pcie_blk_locn              {X0Y0} \
    CONFIG.pf0_device_id              {9034} \
    CONFIG.pf0_subsystem_id           {0007} \
    CONFIG.ref_clk_freq               {100_MHz} \
    CONFIG.mode_selection             {Basic} \
    CONFIG.axi_data_width             {128_bit} \
    CONFIG.num_queues                 {1} \
    CONFIG.axilite_master_en          {true} \
    CONFIG.axilite_master_scale       {Megabytes} \
    CONFIG.axilite_master_size        {1} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X4} \
] $ip
generate_target all $ip

# ---- 约束: P6a 基线 (原样复用) + PCIe 增量 (分开两个文件, 避免分叉) ----
add_files -fileset constrs_1 ${script_dir}/ku5p_p6a_t8p0.xdc
add_files -fileset constrs_1 ${script_dir}/ku5p_p6e_pcie.xdc
# 跨时钟域约束单独一个文件, **且只在实现阶段应用**: 综合前解析时 create_clock 还没生效
# (XDMA 也还是黑盒) ⇒ 里面的 get_clocks 拿到空对象 ⇒ Vivado 会报 CRITICAL WARNING 并
# **静默丢弃** (实测: BUILD_ID=2 那版就是这样, 两个域仍是 "Timed (unsafe)")。
add_files -fileset constrs_1 ${script_dir}/ku5p_p6e_cdc.xdc
set_property used_in_synthesis false [get_files ${script_dir}/ku5p_p6e_cdc.xdc]
# P6b 增量 (见文件头): Y1 100MHz 输入时钟 + 三域 set_clock_groups (后者必须 impl-only)
add_files -fileset constrs_1 ${script_dir}/ku5p_p6b_sysclk.xdc
add_files -fileset constrs_1 ${script_dir}/ku5p_p6b_cdc.xdc
set_property used_in_synthesis false [get_files ${script_dir}/ku5p_p6b_cdc.xdc]

set_property verilog_define {APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1} [current_fileset]
# ⚠️ `DP_156MHZ` = 「数据面跑在 156.25MHz 独立域」—— 它守卫**时钟拓扑 / 两个异步 FIFO /
#    wrapper 的 LED-UART 时间常数 / 6 个 rtl 模块的 8 个时间常数**。与 `PCIE_OBS`
#    (「例化 PCIe 观测通道」) **语义无关**, 必须分别给 (对抗审查 F1: 绑成一个宏的后果是
#    有人"要 PCIe 窗口但数据面仍 125MHz"时会静默拿到 8 个错常数)。
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]
launch_runs impl_1 -jobs 8
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# ---- 读数 (只读; 判定在 bat 里做) ----
open_run impl_1
report_timing_summary -file ${script_dir}/p6e_ku5p_timing.rpt
report_utilization    -file ${script_dir}/p6e_ku5p_util.rpt
report_drc            -file ${script_dir}/p6e_ku5p_drc.rpt
puts "\n===== BITSTREAM: ${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit ====="
exit
