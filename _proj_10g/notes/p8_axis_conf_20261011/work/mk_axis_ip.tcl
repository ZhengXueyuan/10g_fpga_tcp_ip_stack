#=============================================================================
# mk_axis_ip.tcl -- P8 AXIS 确认轮 (SCRATCH): XDMA 4.2 MM vs AXI4-Stream
#
#   目的: 在**不动仓库任何源文件**的前提下, 钉死"把 XDMA 切成 AXI4-Stream 后
#         真实的 CONFIG.* 展开 与 端口表"。
#
#   本脚本只在本目录下建工程 ($wd/prj), 不 import 任何仓库文件, 不综合,
#   只 create_ip + set_property + generate_target all。
#
#   基线 12 项 = 逐字抄自 board/build_p7b_ku5p.tcl:119-132 (现役 MM 构建)。
#   ST 臂 = 基线 12 项 + CONFIG.xdma_axi_intf_mm {AXI_Stream} (唯一增量)。
#
#   两个 IP 同工程并存: xdma_mm (基线副本) / xdma_st (ST 臂) => 差异可逐条对.
#   不动点回读循环照抄 board/build_p7b_ku5p.tcl:60-72 的 pcs64 范式。
#=============================================================================
set wd [file normalize [file dirname [info script]]]
puts "P8AXIS_WD = $wd"
puts "P8AXIS_VIVADO = [version -short]"

create_project -force scratch_axis $wd/prj -part xcku5p-ffvb676-1-e
set_property target_language Verilog [current_project]
puts "P8AXIS_PART = [get_property PART [current_project]]"

# ---- 基线 12 项 (逐字抄自 board/build_p7b_ku5p.tcl:119-132) ------------------
set BASE [list \
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
    set fp [open $wd/cfg_${tag}.txt w]
    foreach p [lsort [list_property $ip]] {
        if {[string match "CONFIG.*" $p]} {
            set gv "<err>"; catch {set gv [get_property $p $ip]}
            puts $fp "$p = $gv"
        }
    }
    close $fp
    puts "P8AXIS_DUMP $tag -> $wd/cfg_${tag}.txt"
}

proc mp_read {ip name} {
    set gv "<err>"; catch {set gv [get_property MODELPARAM_VALUE.${name} $ip]}
    return $gv
}

proc fixed_point {ip desired tag} {
    set conv -1
    for {set rnd 1} {$rnd <= 8} {incr rnd} {
        foreach {k v} $desired { catch {set_property $k $v $ip} e }
        set bad 0
        foreach {k v} $desired {
            set gv "<err>"; catch {set gv [get_property $k $ip]}
            if {[string trim $gv] ne [string trim $v]} {
                incr bad
                puts "P8AXIS_RB_MISMATCH ${tag} $k want=<$v> got=<$gv>"
            }
        }
        puts "P8AXIS_ROUND ${tag} #$rnd MISMATCH_N = $bad"
        if {$bad == 0} { set conv $rnd ; break }
    }
    puts "P8AXIS_CONVERGED_AT_ROUND ${tag} = $conv"
    return $conv
}

# ---- 臂 A: MM 基线副本 -------------------------------------------------------
puts "\nP8AXIS >>>>>>>>>> ARM_MM"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_mm
set ipmm [get_ips xdma_mm]
set mm_defaults [list]
foreach p [lsort [list_property $ipmm]] {
    if {[string match "CONFIG.*" $p]} { lappend mm_defaults $p [get_property $p $ipmm] }
}
puts "P8AXIS_MM_DEFAULTS_CAPTURED = [expr {[llength $mm_defaults]/2}]"
dump_cfg $ipmm "mm_defaults"
set e ""; set rc [catch {set_property -dict $BASE $ipmm} e]
puts "P8AXIS_MM_SET_RC = $rc"
puts "P8AXIS_MM_SET_MSG = <$e>"
fixed_point $ipmm $BASE "MM"
dump_cfg $ipmm "mm_pre_gen"

# ---- 臂 B: ST 臂 (基线 + 唯一增量) -------------------------------------------
puts "\nP8AXIS >>>>>>>>>> ARM_ST"
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_st
set ipst [get_ips xdma_st]
# 单设一次, 单独记录这一条 set_property 的返回 (参数名/取值合法性证据)
set e2 ""
set rc2 [catch {set_property CONFIG.xdma_axi_intf_mm {AXI_Stream} $ipst} e2]
puts "P8AXIS_ST_SET_INTF_RC = $rc2"
puts "P8AXIS_ST_SET_INTF_MSG = <$e2>"
set rb ""; catch {set rb [get_property CONFIG.xdma_axi_intf_mm $ipst]}
puts "P8AXIS_ST_INTF_READBACK_IMMEDIATE = <$rb>"
set DESIRED "$BASE CONFIG.xdma_axi_intf_mm {AXI_Stream}"
fixed_point $ipst $DESIRED "ST"
dump_cfg $ipst "st_pre_gen"

# ---- 生成 (只 generate_target all, 不 synth) ---------------------------------
puts "\nP8AXIS >>>>>>>>>> GENERATE"
set eg ""; set rcg [catch {generate_target all $ipmm} eg]
puts "P8AXIS_GEN_MM_RC = $rcg ; MSG = <$eg>"
set eg2 ""; set rcg2 [catch {generate_target all $ipst} eg2]
puts "P8AXIS_GEN_ST_RC = $rcg2 ; MSG = <$eg2>"

dump_cfg $ipmm "mm_post_gen"
dump_cfg $ipst "st_post_gen"

# ---- 生成后显式读数 (含 model param) -----------------------------------------
foreach {tag ip} [list MM $ipmm ST $ipst] {
    puts "P8AXIS_POSTGEN_${tag}_INTF_MM   = <[mp_read $ip XDMA_AXI_INTF_MM]>"
    puts "P8AXIS_POSTGEN_${tag}_DMA_MM    = <[mp_read $ip DMA_MM]>"
    puts "P8AXIS_POSTGEN_${tag}_DMA_ST    = <[mp_read $ip DMA_ST]>"
    puts "P8AXIS_POSTGEN_${tag}_AXI_DATA_WIDTH = <[mp_read $ip AXI_DATA_WIDTH]>"
    puts "P8AXIS_POSTGEN_${tag}_AXI_ADDR_WIDTH = <[mp_read $ip AXI_ADDR_WIDTH]>"
    puts "P8AXIS_POSTGEN_${tag}_USER_CLK_FREQ  = <[mp_read $ip USER_CLK_FREQ]>"
    puts "P8AXIS_POSTGEN_${tag}_EN_WCHNL_0 = <[mp_read $ip EN_WCHNL_0]>"
    puts "P8AXIS_POSTGEN_${tag}_EN_RCHNL_0 = <[mp_read $ip EN_RCHNL_0]>"
    puts "P8AXIS_POSTGEN_${tag}_C2H_NUM_CHNL = <[mp_read $ip C_C2H_NUM_CHNL]>"
    puts "P8AXIS_POSTGEN_${tag}_H2C_NUM_CHNL = <[mp_read $ip C_H2C_NUM_CHNL]>"
    puts "P8AXIS_POSTGEN_${tag}_AXILITE_MASTER = <[mp_read $ip XDMA_AXILITE_MASTER]>"
    puts "P8AXIS_POSTGEN_${tag}_DSC_BYPASS_RD = <[mp_read $ip DSC_BYPASS_RD]>"
    puts "P8AXIS_POSTGEN_${tag}_DSC_BYPASS_WR = <[mp_read $ip DSC_BYPASS_WR]>"
    puts "P8AXIS_POSTGEN_${tag}_XDMA_AXIST_BYPASS = <[mp_read $ip XDMA_AXIST_BYPASS]>"
    puts "P8AXIS_POSTGEN_${tag}_IS_LOCKED = <[get_property IS_LOCKED $ip]>"
}

# ---- 端口表: synth stub + veo (引擎自己产出的权威件) -------------------------
foreach {tag ip} [list mm xdma_mm st xdma_st] {
    set gdir [get_property IP_DIR $ip]
    puts "P8AXIS_IPDIR_${tag} = $gdir"
    set fp [open $wd/gendir_${tag}.txt w]
    foreach f [glob -nocomplain $gdir/*] { puts $fp $f }
    foreach f [glob -nocomplain $gdir/synth/*] { puts $fp $f }
    foreach f [glob -nocomplain $gdir/hdl/*] { puts $fp $f }
    close $fp
}

puts "\nP8AXIS DONE"
exit
