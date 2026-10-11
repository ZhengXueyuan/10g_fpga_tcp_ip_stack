#=============================================================================
# synth_only_ku5p.tcl -- P9 (AXIS 改造) 综合检查点 (synth-only, 不出位流, 不碰 vivado_prj/)
#
#   机制: 与 `board/build_p7b_ku5p.tcl` **同一份文件表 + 同一组 define + 同一组 XDC**,
#         但 ① 项目落在本目录 prj_<arm>/ (**绝不用 vivado_prj/p7b_ku5p_prj** ——
#            `create_project -force` 会清掉现役 0x21 构建的取证, 全局 #54),
#         ② 只跑 synth_1 (launch_runs synth_1), 不跑 impl / 不写位流。
#
#   ⭐ P9 与本检查点的关系: 本检查点**先于构建轮**回答 "新 IP (xdma 4.2 + AXI_Stream)
#      能不能编过 + 新件 (`rtl/axis_c2h_stream.v`) 的综合面代价/新锥"。⇒ 它自己也跑
#      与构建脚本**逐字同款**的 XDMA 配置 + 回读断言 (CONF §2.3 的 B 臂写法)。
#
#   ⚠️ synth 面读数是 **pre-place**, 与后布线读数**不可直接比大小** (只做同流程 A/B)。
#   用法: run_synth.bat <arm>   (经 cmd //c 调用; -tclargs 必须放最后)
#=============================================================================
set arm "p9axis"
if {[llength $argv] >= 1} { set arm [lindex $argv 0] }
set project_name p9_axis_synth_${arm}
set top_module   wrapper_p4
set part_name    xcku5p-ffvb676-1-e
set gquad        Quad_X0Y1

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file dirname [file dirname [file dirname $script_dir]]]
set hls_dir    ${root_dir}/hls/slowstack_prj/solution1/syn/verilog
set mac_dir    ${root_dir}/_proj_10g/p7b_mac/rtl
set prj_dir    ${script_dir}/prj_${arm}

proc sec {s} { puts "\nP9SYNTH >>>>>>>>>> $s" }
catch {set_param general.maxThreads 8}

sec "P9SYNTH_ENV"
puts "P9SYNTH_ARM = $arm"
puts "P9SYNTH_ROOT = $root_dir"
puts "P9SYNTH_VIVADO = [version -short]"

sec "P9SYNTH_CREATE $project_name"
create_project -force $project_name $prj_dir -part $part_name
set_property target_language Verilog [current_project]

sec "P9SYNTH_IP_CREATE"
create_ip -name xxv_ethernet -vendor xilinx.com -library ip -version 5.0 -module_name pcs64
set ip [get_ips pcs64]
set DESIRED [list \
    CONFIG.LINE_RATE            {10} \
    CONFIG.CLOCKING             {Asynchronous} \
    CONFIG.BASE_R_KR            {BASE-R} \
    CONFIG.GT_REF_CLK_FREQ      {156.25} \
    CONFIG.GT_TYPE              {GTY} \
    CONFIG.INCLUDE_SHARED_LOGIC {1} \
    CONFIG.GT_GROUP_SELECT      $gquad \
    CONFIG.NUM_OF_CORES         {2} \
    CONFIG.LANE1_GT_LOC         {X0Y4} \
    CONFIG.LANE2_GT_LOC         {X0Y5} \
    CONFIG.CORE                 {Ethernet PCS/PMA 64-bit} ]
set conv -1
for {set rnd 1} {$rnd <= 8} {incr rnd} {
    foreach {k v} $DESIRED { catch {set_property $k $v $ip} e }
    set bad 0
    foreach {k v} $DESIRED {
        set gv "<err>"; catch { set gv [get_property $k $ip] }
        if {[string trim $gv] ne [string trim $v]} { incr bad ; puts "P9SYNTH_RB_MISMATCH $k want=<$v> got=<$gv>" }
    }
    puts "P9SYNTH_ROUND #$rnd MISMATCH_N = $bad"
    if {$bad == 0} { set conv $rnd ; break }
}
puts "P9SYNTH_CONVERGED_AT_ROUND = $conv"
if {$conv < 0} { puts "P9SYNTH_VERDICT = IP_NOT_CONVERGED" ; exit 1 }
generate_target all $ip

sec "P9SYNTH_ADD_DATAPATH"
import_files -norecurse \
    ${root_dir}/rtl/crc32_8b.v ${root_dir}/rtl/fifo_sync.v ${root_dir}/rtl/checksum16.v \
    ${root_dir}/rtl/frame_fifo.v ${root_dir}/rtl/mac_rx_64.v ${root_dir}/rtl/mac_tx_64.v \
    ${root_dir}/rtl/tcp_cam.v ${root_dir}/rtl/tcb.v ${root_dir}/rtl/tcp_rx.v \
    ${root_dir}/rtl/tcp_tx_frame.v ${root_dir}/rtl/retx_ram.v ${root_dir}/rtl/tcp_echo.v \
    ${root_dir}/rtl/axis_pipe.v ${root_dir}/rtl/rx_classify.v ${root_dir}/rtl/vlan_strip.v \
    ${root_dir}/rtl/slow_rx_adp.v ${root_dir}/rtl/slow_cfg_adp.v ${root_dir}/rtl/slow_tx_adp.v \
    ${root_dir}/rtl/udp_rx.v ${root_dir}/rtl/udp_split.v ${root_dir}/rtl/udp_tx_cfg.v \
    ${root_dir}/rtl/udp_tx_frame.v ${root_dir}/rtl/tx_arb.v ${root_dir}/rtl/app_ctrl.v \
    ${root_dir}/rtl/app_pattern.v ${root_dir}/rtl/app_udp_pattern.v \
    ${root_dir}/rtl/app_status_uart.v
# P9: 载荷镜像 (app_rx_mirror) + **新件** axis_c2h_stream (AXIS 成形器);
#     期 B 的三件套 (mir_dma_ring / aximm_c2h_win / aximm_h2c_discard) **不再导入**
#     (wrapper 不再例化它们; 文件仍保留在树里, 单元门见 sim/p7b_mirdma/ 与 sim/p7b_h2cdisc/)
foreach f [list ${root_dir}/rtl/app_rx_mirror.v ${root_dir}/rtl/axis_c2h_stream.v] {
    if {[file exists $f]} {
        import_files -norecurse $f
        puts "P9SYNTH_IMPORTED [file tail $f] 1"
    } else {
        puts "P9SYNTH_IMPORTED [file tail $f] 0"
    }
}
sec "P9SYNTH_ADD_OBS"
import_files -norecurse ${root_dir}/rtl/snap_cdc.v ${root_dir}/_proj_pcie/rtl/axi_regs.v \
                         ${root_dir}/rtl/clk_gen_p6b.v ${root_dir}/rtl/fifo_async.v \
                         ${root_dir}/rtl/snap_seq.v
sec "P9SYNTH_ADD_MAC"
import_files -norecurse ${mac_dir}/crc32_64.v ${mac_dir}/mac_rx_10g.v ${mac_dir}/mac_tx_10g.v
sec "P9SYNTH_ADD_BOARD"
import_files -norecurse ${root_dir}/board/wrapper_p4.v ${root_dir}/board/util_gmii_to_rgmii_us.v \
                         ${root_dir}/board/util_gmii_to_rgmii.v ${root_dir}/board/uart_dbg.v
import_files -norecurse [glob -nocomplain ${hls_dir}/*.v]
set src_dir [file dirname [lindex [glob -nocomplain ${prj_dir}/${project_name}.srcs/sources_1/imports/verilog/udp_echo.v] 0]]
if {$src_dir eq ""} {
    set src_dir [file dirname [lindex [glob -nocomplain ${prj_dir}/${project_name}.srcs/sources_1/imports/*/udp_echo.v] 0]]
}
foreach dat [glob -nocomplain ${hls_dir}/*.dat] { file copy -force $dat $src_dir/ }

sec "P9SYNTH_ADD_XDMA"
# ⭐ 与 `board/build_p7b_ku5p.tcl` 的 XDMA 块**逐字同款** (含 AXIS 配置 + 两层日志牙 + 回读断言)
#   —— 本检查点因此也充当"构建轮之前的排练": 新 IP 编不过 / 静默回滚, 这里就红。
set_msg_config -id {IP_Flow 19-3461} -new_severity {ERROR}
set_msg_config -id {IP_Flow 19-3438} -new_severity {ERROR}
catch { set_msg_config -string {Restoring to previous valid configuration} -new_severity {ERROR} }
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set xip [get_ips xdma_0]
set XDMA_BASE12 [list \
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
    CONFIG.pl_link_cap_max_link_width {X4} ]
set XDMA_IF_MODE {AXI_Stream}
set p9x_bad 0
set xerr "" ;  set xrc  [catch {set_property -dict $XDMA_BASE12 $xip} xerr]
puts "P9SYNTH_XDMA_RC_BASE = $xrc ; MSG = <$xerr>"
set xerr2 "" ; set xrc2 [catch {set_property CONFIG.xdma_axi_intf_mm $XDMA_IF_MODE $xip} xerr2]
puts "P9SYNTH_XDMA_RC_INTF = $xrc2 ; MSG = <$xerr2>"
if {$xrc != 0 || $xrc2 != 0} { set p9x_bad 1 ; puts "P9SYNTH_XDMA_CFG_CATCH_FAIL" }
foreach m [list $xerr $xerr2] {
    foreach pat {19-3461 19-3438 {Restoring to previous valid configuration} 17-39} {
        if {[string first $pat $m] >= 0} { puts "P9SYNTH_XDMA_MSG_HIT <$pat>" ; set p9x_bad 1 }
    }
}
set XDMA_RB [concat $XDMA_BASE12 [list CONFIG.xdma_axi_intf_mm $XDMA_IF_MODE]]
set p9x_rb_bad 0
foreach {k v} $XDMA_RB {
    set gv "<err>" ; catch { set gv [get_property $k $xip] }
    if {[string trim $gv] ne [string trim $v]} { incr p9x_rb_bad ; puts "P9SYNTH_XDMA_RB_MISMATCH $k want=<$v> got=<$gv>" }
}
puts "P9SYNTH_XDMA_RB_MISMATCH_N = $p9x_rb_bad"
generate_target all $xip
set xdma_gen_file ""
foreach f [list \
    "${prj_dir}/${project_name}.gen/sources_1/ip/xdma_0/synth/xdma_0.sv" \
    "${prj_dir}/${project_name}.gen/sources_1/ip/xdma_0/xdma_0_stub.v" ] {
    if {[file exists $f]} { set xdma_gen_file $f ; break }
}
set p9x_gen_bad 0
if {$xdma_gen_file eq ""} {
    set p9x_gen_bad 1 ; puts "P9SYNTH_XDMA_GEN_MISSING"
} else {
    set fh [open $xdma_gen_file r] ; set gtxt [read $fh] ; close $fh
    puts "P9SYNTH_XDMA_GEN_FILE = $xdma_gen_file"
    foreach t {DMA_ST=1 DMA_MM=0 XDMA_AXI_INTF_MM=0 AXI_DATA_WIDTH=128 USER_CLK_FREQ=2 XDMA_AXILITE_MASTER=TRUE} {
        if {[string first $t $gtxt] < 0} { incr p9x_gen_bad ; puts "P9SYNTH_XDMA_GEN_MISS <$t>" }
    }
}
puts "P9SYNTH_XDMA_GEN_BAD_N = $p9x_gen_bad"
if {$p9x_bad || $p9x_rb_bad != 0 || $p9x_gen_bad != 0} {
    puts "P9SYNTH_VERDICT = XDMA_ST_CFG_FAIL"
    exit 1
}
puts "P9SYNTH_XDMA_VERDICT = OK"

sec "P9SYNTH_CONSTR"
add_files -fileset constrs_1 ${root_dir}/board/ku5p_p7b_gt.xdc
add_files -fileset constrs_1 ${root_dir}/board/ku5p_p6e_pcie.xdc
add_files -fileset constrs_1 ${root_dir}/board/ku5p_p6b_sysclk.xdc
add_files -fileset constrs_1 ${root_dir}/board/ku5p_p7b_cdc.xdc
set_property used_in_synthesis false [get_files ${root_dir}/board/ku5p_p7b_cdc.xdc]

set_property verilog_define {APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1} [current_fileset]
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1
puts "P9SYNTH_NFILES = [llength [get_files -quiet]]"

sec "P9SYNTH_SYNTH"
reset_run synth_1
catch {launch_runs synth_1 -jobs 8} e
puts "P9SYNTH_LAUNCH = $e"
wait_on_run synth_1
catch {puts "P9SYNTH_STATUS = [get_property STATUS [get_runs synth_1]]"}
if {![string match "100%*" [get_property PROGRESS [get_runs synth_1]]]} {
    puts "P9SYNTH_VERDICT = SYNTH_FAIL"
    exit 1
}

sec "P9SYNTH_REPORTS"
open_run synth_1
report_timing_summary -file ${script_dir}/synth_${arm}_timing_summary.rpt
report_utilization    -file ${script_dir}/synth_${arm}_util.rpt
report_timing -delay_type max -max_paths 200 -file ${script_dir}/synth_${arm}_top200.rpt
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set whs [get_property SLACK [get_timing_paths -delay_type min]]
puts "P9SYNTH_WNS = $wns"
puts "P9SYNTH_WHS = $whs"
catch { puts "P9SYNTH_CLOCKS = [get_clocks -quiet]" }
# 定向查询: 新件 (u_mir_axis) 的 FROM/TO 锥 (新件是本刀唯一的 pcie 域新逻辑)
set axispins [get_pins -quiet -hierarchical -filter {NAME =~ *u_mir_axis*}]
puts "P9SYNTH_AXIS_PINS = [llength $axispins]"
if {[llength $axispins] > 0} {
    catch { report_timing -delay_type max -max_paths 40 -from $axispins -file ${script_dir}/synth_${arm}_axis_from.rpt }
    catch { report_timing -delay_type max -max_paths 40 -to   $axispins -file ${script_dir}/synth_${arm}_axis_to.rpt }
}
# 对照: 镜像件 (u_mir) 的锥 (它在 0x21 里已存在, 用来判"有没有把镜像也拖慢")
set mirpins [get_pins -quiet -hierarchical -filter {NAME =~ *u_mir/*}]
puts "P9SYNTH_MIR_PINS = [llength $mirpins]"
if {[llength $mirpins] > 0} {
    catch { report_timing -delay_type max -max_paths 40 -to $mirpins -file ${script_dir}/synth_${arm}_mir_to.rpt }
}
puts "P9SYNTH_DONE"
exit
