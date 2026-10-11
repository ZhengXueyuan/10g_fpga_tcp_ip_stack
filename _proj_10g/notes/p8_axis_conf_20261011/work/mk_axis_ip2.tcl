#=============================================================================
# mk_axis_ip2.tcl -- P8 AXIS 确认轮 实验 2: 钉死 "128 位在 ST 模式下是否合法"
#
# 实验 1 (mk_axis_ip.tcl) 观测到:
#   - set_property CONFIG.xdma_axi_intf_mm {AXI_Stream} 单设 => RC=0, 回读 = AXI_Stream
#   - 但随后 set_property -dict <12 项基线> 报:
#       ERROR: [IP_Flow 19-3461] Value '128_bit' is out of the range for parameter
#              'AXI Data width(axi_data_width)' ... Valid values are - 64_bit
#       INFO:  [IP_Flow 19-3438] Customization errors found ... Restoring to previous valid configuration.
#   - 而回读逐项匹配 (MISMATCH_N=0), 生成产物 AXI_DATA_WIDTH=128 / USER_CLK_FREQ=2
# 本实验 = 四臂定位"到底哪一步/哪种顺序才合法", 并给出可照抄的写法。
#
# 四臂 (每臂 = 全新 create_ip, 互不污染):
#   A: 一次 -dict 设 13 项, 且 pl_link_cap_* 排在 axi_data_width 之前
#   B: 先设 12 项基线 (含 link speed/width), 再单独设 intf      <- 最贴近"追加一行"的改法
#   C: 先单独设 intf, 再设其余 11 项 (不含 axi_data_width?) -> 含 width, 复现实验 1 的顺序
#   D: 先设 12 项基线, 再单独设 intf, 并把 width 改成 64_bit (ST 64 位臂)
#=============================================================================
set wd [file normalize [file dirname [info script]]]
puts "P8AXIS2_VIVADO = [version -short]"
create_project -force scratch_axis2 $wd/prj2 -part xcku5p-ffvb676-1-e
set_property target_language Verilog [current_project]

set BASE12 [list \
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

proc dump_cfg {ip tag} {
    global wd
    set fp [open $wd/cfg2_${tag}.txt w]
    foreach p [lsort [list_property $ip]] {
        if {[string match "CONFIG.*" $p]} {
            set gv "<err>"; catch {set gv [get_property $p $ip]}
            puts $fp "$p = $gv"
        }
    }
    close $fp
}
proc rb {ip k} { set v "<err>"; catch {set v [get_property $k $ip]} ; return $v }
proc keyread {ip tag} {
    foreach k {axi_data_width axisten_freq xdma_axi_intf_mm pl_link_cap_max_link_speed pl_link_cap_max_link_width plltype} {
        puts "P8AXIS2_${tag}_$k = <[rb $ip CONFIG.$k]>"
    }
}

# ---------------- ARM A: 一次 -dict 13 项, link 参数在前 ----------------------
puts "\nP8AXIS2 >>>>>>>>>> ARM_A (single dict, link params before width)"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_a
set ipa [get_ips xdma_a]
set A [list \
    CONFIG.pcie_blk_locn              {X0Y0} \
    CONFIG.pf0_device_id              {9034} \
    CONFIG.pf0_subsystem_id           {0007} \
    CONFIG.ref_clk_freq               {100_MHz} \
    CONFIG.mode_selection             {Basic} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X4} \
    CONFIG.axi_data_width             {128_bit} \
    CONFIG.num_queues                 {1} \
    CONFIG.axilite_master_en          {true} \
    CONFIG.axilite_master_scale       {Megabytes} \
    CONFIG.axilite_master_size        {1} \
    CONFIG.xdma_axi_intf_mm           {AXI_Stream} ]
set ea ""; set rca [catch {set_property -dict $A $ipa} ea]
puts "P8AXIS2_A_RC = $rca ; MSG = <$ea>"
keyread $ipa A
dump_cfg $ipa a

# ---------------- ARM B: 12 项基线 -> 再单独设 intf ---------------------------
puts "\nP8AXIS2 >>>>>>>>>> ARM_B (12 base first, then intf alone)"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_b
set ipb [get_ips xdma_b]
set eb ""; set rcb [catch {set_property -dict $BASE12 $ipb} eb]
puts "P8AXIS2_B_RC_BASE = $rcb ; MSG = <$eb>"
dump_cfg $ipb b_pre
set eb2 ""; set rcb2 [catch {set_property CONFIG.xdma_axi_intf_mm {AXI_Stream} $ipb} eb2]
puts "P8AXIS2_B_RC_INTF = $rcb2 ; MSG = <$eb2>"
keyread $ipb B
dump_cfg $ipb b_post

# ---------------- ARM C: 先设 intf, 再设其余 12 (复现实验 1 顺序) --------------
puts "\nP8AXIS2 >>>>>>>>>> ARM_C (intf first, then 12 base)"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_c
set ipc [get_ips xdma_c]
set ec ""; set rcc [catch {set_property CONFIG.xdma_axi_intf_mm {AXI_Stream} $ipc} ec]
puts "P8AXIS2_C_RC_INTF = $rcc ; MSG = <$ec>"
set ec2 ""; set rcc2 [catch {set_property -dict $BASE12 $ipc} ec2]
puts "P8AXIS2_C_RC_BASE = $rcc2 ; MSG = <$ec2>"
keyread $ipc C
dump_cfg $ipc c

# ---------------- ARM D: 12 项基线 + intf + 64_bit ---------------------------
puts "\nP8AXIS2 >>>>>>>>>> ARM_D (12 base with 64_bit, then intf)"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_d
set ipd [get_ips xdma_d]
set d64 [list \
    CONFIG.pcie_blk_locn              {X0Y0} \
    CONFIG.pf0_device_id              {9034} \
    CONFIG.pf0_subsystem_id           {0007} \
    CONFIG.ref_clk_freq               {100_MHz} \
    CONFIG.mode_selection             {Basic} \
    CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
    CONFIG.pl_link_cap_max_link_width {X4} \
    CONFIG.axi_data_width             {64_bit} \
    CONFIG.num_queues                 {1} \
    CONFIG.axilite_master_en          {true} \
    CONFIG.axilite_master_scale       {Megabytes} \
    CONFIG.axilite_master_size        {1} ]
set ed ""; set rcd [catch {set_property -dict $d64 $ipd} ed]
puts "P8AXIS2_D_RC_BASE = $rcd ; MSG = <$ed>"
set ed2 ""; set rcd2 [catch {set_property CONFIG.xdma_axi_intf_mm {AXI_Stream} $ipd} ed2]
puts "P8AXIS2_D_RC_INTF = $rcd2 ; MSG = <$ed2>"
keyread $ipd D
dump_cfg $ipd d

# ---------------- 生成四臂 ----------------------------------------------------
puts "\nP8AXIS2 >>>>>>>>>> GENERATE"
foreach {n ip} [list a $ipa b $ipb c $ipc d $ipd] {
    set eg ""; set rcg [catch {generate_target all $ip} eg]
    puts "P8AXIS2_GEN_${n}_RC = $rcg ; MSG = <$eg>"
    dump_cfg $ip "post_${n}"
}
puts "\nP8AXIS2 DONE"
exit
