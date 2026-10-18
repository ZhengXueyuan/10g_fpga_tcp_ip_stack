#=============================================================================
# build_p7b_ku5p.tcl -- P7b: **10G 前端** 与既有 64 位数据面合体 (KU5P)
#
#   基线 = build_p6b_final_ku5p.tcl 的文件清单 + 策略 (PCIE_OBS + DP_156MHZ + APP_MODE),
#   增量 = ① 官方 `xxv_ethernet` PCS/PMA 64-bit (2 通道, X0Y4+X0Y5, 156.25MHz 参考钟)
#          ② 自写 64 位 XGMII MAC (`_proj_10g/p7b_mac/rtl/`)
#          ③ wrapper 的 `ifdef P7B_10G` 分支 (前端整体换掉, 数据面一字未动)
#          ④ 两份新 XDC (引脚 + 四域 set_clock_groups)
#
# 产物: vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4.bit
#       + p7b_ku5p_{timing,util,drc}.rpt
#
# ⚠️ 纪律 (逐条):
#   ① 默认构建 (无 P7B_10G) 的端口表/逻辑**逐位不变** —— 新增的一切都在 `ifdef P7B_10G` 内。
#   ② **本脚本不烧板** (没有 program_hw_devices), 也不写 QSPI。
#   ③ Vivado batch 出错不一定返回非零 ⇒ 成功判据 = 位流文件存在 (bat 里检查)。
#   ④ 硬门: 日志 grep `12-4739` (约束被静默丢弃) / 隐式网五键 / 扩展键 (见 bat)。
#   ⑤ `p7b_pcs_stub.v` **不导入** (它只给仿真用; P7B_SIM_NOPCS 不定义 ⇒ 不被引用)。
#=============================================================================
set project_name p7b_ku5p_prj
set top_module   wrapper_p4
set part_name    xcku5p-ffvb676-1-e
set gquad        Quad_X0Y1        ;# quad 225 = channels X0Y4..X0Y7 (SFP A / SFP B)

set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file dirname $script_dir]
set hls_dir    ${root_dir}/hls/slowstack_prj/solution1/syn/verilog
set mac_dir    ${root_dir}/_proj_10g/p7b_mac/rtl

proc sec {s} { puts "\nP7B >>>>>>>>>> $s" }
catch {set_param general.maxThreads 8}

# ---- F-6: HLS 源/网表 sha256 (构建必须归档; 拿不到 = 硬失败) ------------------
#   ⚠️ Vivado 的 Tcl 没有内置 sha256 ⇒ 用 Windows 自带 PowerShell 的 Get-FileHash
#      (逐文件一调; ~50 次进程启动 ≈ 十几秒, 可接受)。任一文件缺失/哈希失败返回 FAIL。
proc p7b_ps_sha256 {f} {
    if {![file exists $f]} { return "MISSING" }
    set out ""
    if {[catch {set out [exec powershell -NoProfile -Command "(Get-FileHash -LiteralPath '$f' -Algorithm SHA256).Hash"]} e]} {
        puts "P7B_HASH_EXEC_ERR $e"
        return "ERR"
    }
    return [string tolower [string trim $out]]
}
proc p7b_sha256_set {files} {
    global script_dir
    set acc ""
    foreach f [lsort $files] {
        set h [p7b_ps_sha256 $f]
        puts "P7B_HASH_FILE $h $f"
        if {($h eq "ERR") || ($h eq "MISSING")} { return "FAIL" }
        append acc $h
    }
    set tmp [file join $script_dir _p7b_hash_acc.tmp]
    set fh [open $tmp w]
    puts -nonewline $fh $acc
    close $fh
    set comb [p7b_ps_sha256 $tmp]
    file delete -force $tmp
    return $comb
}

sec "P7B_ENV"
puts "P7B_VIVADO = [version -short]"
puts "P7B_PART_N = [llength [get_parts $part_name -quiet]]"
# F-6: HLS 源 (hls/src/*.cpp|*.h + run_hls.tcl) 与网表 (verilog/*.v + *.dat) 双哈希
set hls_src_files [concat [glob -nocomplain ${root_dir}/hls/src/*.cpp] \
                         [glob -nocomplain ${root_dir}/hls/src/*.h] \
                         [glob -nocomplain ${root_dir}/hls/run_hls.tcl]]
set hls_net_files [concat [glob -nocomplain ${hls_dir}/*.v] \
                         [glob -nocomplain ${hls_dir}/*.dat]]
set HLS_SRC_HASH [p7b_sha256_set $hls_src_files]
set HLS_NET_HASH [p7b_sha256_set $hls_net_files]
puts "HLS_SRC_HASH = $HLS_SRC_HASH  (n=[llength $hls_src_files] files: hls/src/*.cpp|*.h + hls/run_hls.tcl)"
puts "HLS_NET_HASH = $HLS_NET_HASH  (n=[llength $hls_net_files] files: hls/slowstack_prj/solution1/syn/verilog/*.v|*.dat)"
if {($HLS_SRC_HASH eq "FAIL") || ($HLS_NET_HASH eq "FAIL")} {
    puts "P7B_VERDICT = HLS_HASH_FAIL"
    exit 1
}

sec "P7B_CREATE $project_name"
create_project -force $project_name ${root_dir}/vivado_prj -part $part_name
set_property target_language Verilog [current_project]

# ---- 官方 PCS/PMA 64-bit (参数逐字照抄闸 1 的 s1_prepare.tcl, 那份已板级验收) -----
#   ⚠️ 设 CONFIG.CORE 会**静默重置**它的从属参数 (闸 1 侦察期实测) ⇒ 用不动点迭代:
#      每轮重设全部参数 + 全量回读比对, 直到零失配。
sec "P7B_IP_CREATE"
create_ip -name xxv_ethernet -vendor xilinx.com -library ip -version 5.0 -module_name pcs64
set ip [get_ips pcs64]
puts "P7B_IS_LOCKED_AT_CREATE = [get_property IS_LOCKED $ip]"
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
        set gv "<err>"; catch {set gv [get_property $k $ip]}
        if {[string trim $gv] ne [string trim $v]} { incr bad ; puts "P7B_RB_MISMATCH $k want=<$v> got=<$gv>" }
    }
    puts "P7B_ROUND #$rnd MISMATCH_N = $bad"
    if {$bad == 0} { set conv $rnd ; break }
}
puts "P7B_CONVERGED_AT_ROUND = $conv"
if {$conv < 0} { puts "P7B_VERDICT = IP_NOT_CONVERGED" ; exit 1 }
generate_target all $ip
puts "P7B_IS_LOCKED_POSTGEN = [get_property IS_LOCKED $ip]"
catch {puts "P7B_LOCK_DETAILS = [get_property LOCK_DETAILS $ip]"}
catch {puts "P7B_USED_LICENSE_KEYS = [get_property USED_LICENSE_KEYS $ip]"}
puts "P7B_GT_REF_CLK_FREQ = [get_property CONFIG.GT_REF_CLK_FREQ $ip]"
puts "P7B_LINE_RATE       = [get_property CONFIG.LINE_RATE $ip]"
puts "P7B_CORE            = [get_property CONFIG.CORE $ip]"
puts "P7B_NUM_OF_CORES    = [get_property CONFIG.NUM_OF_CORES $ip]"

# ---- 数据面 (与 P6b 最终构建同一份清单) -------------------------------------
sec "P7B_ADD_DATAPATH"
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
    ${root_dir}/rtl/app_status_uart.v     ${root_dir}/rtl/rx_merge2.v ${root_dir}/rtl/tx_demux2.v ${root_dir}/rtl/maccnt_sync.v
sec "P7B_ADD_OBS"
import_files -norecurse ${root_dir}/rtl/snap_cdc.v ${root_dir}/_proj_pcie/rtl/axi_regs.v \
                         ${root_dir}/rtl/clk_gen_p6b.v ${root_dir}/rtl/fifo_async.v \
                         ${root_dir}/rtl/snap_seq.v \
                         ${root_dir}/rtl/app_rx_mirror.v \
                         ${root_dir}/rtl/axis_c2h_stream.v \
                         ${root_dir}/rtl/mir_uram_fifo.v
# ⚠️ P9 (2026-10-13, 构建轮 0x24): `rtl/mir_uram_fifo.v` (= `u_mir_buf`, URAM288 32 KB 板内缓冲)
#   是 **URAM 实施轮 (2026-10-13) 新增的件** —— 那一轮是 xsim-only, 没碰本清单 ⇒
#   构建轮补这一行。**缺它 = 该模块是黑盒** (Vivado 对未导入的被例化模块不报硬错,
#   只是把 `u_mir_buf` 当 black box ⇒ URAM288 不推断、缓冲不存在 = 安静失效)。
#   加件先例 = 173b18d (同一区域加 `axis_c2h_stream.v`)。
# ⛔ P9 (2026-10-11): 期 B 的三件套 (`rtl/mir_dma_ring.v` / `rtl/aximm_c2h_win.v` /
#   `rtl/aximm_h2c_discard.v`) **不再导入** —— AXIS 改造后 wrapper 不再例化它们
#   (它们的单元门仍保留在 `sim/p7b_mirdma/` `sim/p7b_h2cdisc/`, 直接编模块本身)。
#   ⚠️ 文件**保留在树里** (回退/对照用), 只是不进本构建的源清单。
sec "P7B_ADD_MAC"
import_files -norecurse ${mac_dir}/crc32_64.v ${mac_dir}/mac_rx_10g.v ${mac_dir}/mac_tx_10g.v
sec "P7B_ADD_BOARD"
import_files -norecurse ${script_dir}/wrapper_p4.v ${script_dir}/util_gmii_to_rgmii_us.v \
                         ${script_dir}/util_gmii_to_rgmii.v ${script_dir}/uart_dbg.v
import_files -norecurse [glob -nocomplain ${hls_dir}/*.v]
# HLS $readmemh 系数文件必须与导入后的 verilog 同目录 (综合按相对路径找)
set src_dir [file dirname [lindex [glob -nocomplain ${root_dir}/vivado_prj/${project_name}.srcs/sources_1/imports/verilog/udp_echo.v] 0]]
if {$src_dir eq ""} {
    set src_dir [file dirname [lindex [glob -nocomplain ${root_dir}/vivado_prj/${project_name}.srcs/sources_1/imports/*/udp_echo.v] 0]]
}
foreach dat [glob -nocomplain ${hls_dir}/*.dat] { file copy -force $dat $src_dir/ }

# ---- XDMA (参数逐字复制 build_p6e_ku5p.tcl 那份已实测枚举通过的; ⭐ P9: 接口 = AXI4-Stream) ----
sec "P7B_ADD_XDMA"
# ⭐ P9 (2026-10-11): PCIe 用户接口 **AXI4-MM → AXI4-Stream** (唯一配置增量 = 1 行)。
#   权威 = EDA 确认轮 `_proj_10g/notes/p8_axis_conf_20261011/CONF.md` (§0/§2/§3)。三条纪律:
#     ① **写法 = CONF 的 "B 臂"**: 12 项基线照抄 (一次 -dict) + **之后单独一行**设接口模式。
#        (A/B 两臂产物参数集逐字相同; ⛔ 不用实验 1 的"逐条设 + 吞异常"路径 —— 它会在
#        `axi_data_width` 早于 link 参数落地时被拒; ⛔ 更不许把宽度写 `64_bit` —— 8.0 GT/s ×
#        X4 下非法 ⇒ 触发**静默回滚**, 回滚态 (64_bit/2.5GT/s/X1/CPLL) 板上完全不可用。)
#     ② **日志 = 判据**: `IP_Flow 19-3461` / `19-3438`("Restoring to previous valid
#        configuration") 出现即**硬失败** —— 回读比对**抓不到回滚** (回滚把"我设的"与
#        "读回的"一起改了; CONF 实验 2 的 D 臂实证: 终态 64_bit 且 `generate_target` RC=0)。
#        两层牙: (a) `set_msg_config` 把这两条消息**升格为 ERROR** ⇒ set_property 直接抛错;
#        (b) catch 收 RC + 消息文本扫描 (`Common 17-39` 同族)。
#     ③ **生成后回读断言** (照上面 pcs64 的不动点范式):
#        (i) 13 项 CONFIG 逐项比对; (ii) 生成产物 (`synth/xdma_0.sv` 的 CORE_GENERATION_INFO)
#        6 个展开参数 (DMA_ST=1 / DMA_MM=0 / XDMA_AXI_INTF_MM=0 / AXI_DATA_WIDTH=128 /
#        USER_CLK_FREQ=2 / XDMA_AXILITE_MASTER=TRUE); (iii) 与**冻结参照转储**逐行 diff ——
#        "本次 vs MM 参照" 必须**只差 2 行** (`CONFIG.Component_Name` + `CONFIG.xdma_axi_intf_mm`;
#        = CONF §2.1 的决定性判据), "本次 vs ST 参照" 只差 1 行 (Component_Name)。
#        ⛔ 参照件缺失 = **硬失败** (判据不静默降级; 参照件在 `p8_axis_conf_20261011/work/`)。
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
set xdma_bad 0
set xerr "" ;  set xrc  [catch {set_property -dict $XDMA_BASE12 $xip} xerr]
puts "P7B_XDMA_RC_BASE = $xrc ; MSG = <$xerr>"
set xerr2 "" ; set xrc2 [catch {set_property CONFIG.xdma_axi_intf_mm $XDMA_IF_MODE $xip} xerr2]
puts "P7B_XDMA_RC_INTF = $xrc2 ; MSG = <$xerr2>"
if {$xrc != 0 || $xrc2 != 0} { set xdma_bad 1 ; puts "P7B_XDMA_CFG_CATCH_FAIL" }
foreach m [list $xerr $xerr2] {
    foreach pat {19-3461 19-3438 {Restoring to previous valid configuration} 17-39} {
        if {[string first $pat $m] >= 0} { puts "P7B_XDMA_MSG_HIT <$pat> MSG=<$m>" ; set xdma_bad 1 }
    }
}
# (i) 13 项逐项回读
set XDMA_RB [concat $XDMA_BASE12 [list CONFIG.xdma_axi_intf_mm $XDMA_IF_MODE]]
set xdma_rb_bad 0
foreach {k v} $XDMA_RB {
    set gv "<err>" ; catch { set gv [get_property $k $xip] }
    if {[string trim $gv] ne [string trim $v]} {
        incr xdma_rb_bad ; puts "P7B_XDMA_RB_MISMATCH $k want=<$v> got=<$gv>"
    }
}
puts "P7B_XDMA_RB_MISMATCH_N = $xdma_rb_bad"
generate_target all $xip
# (ii) 生成产物里的展开参数 (权威 = 引擎自己的产物, 不是我对 get_property 的转述)
set xdma_gen_file ""
foreach f [list \
    "${root_dir}/vivado_prj/${project_name}.gen/sources_1/ip/xdma_0/synth/xdma_0.sv" \
    "${root_dir}/vivado_prj/${project_name}.gen/sources_1/ip/xdma_0/xdma_0_stub.v" \
    "${root_dir}/vivado_prj/${project_name}.gen/sources_1/ip/xdma_0/sim/xdma_0.sv" ] {
    if {[file exists $f]} { set xdma_gen_file $f ; break }
}
puts "P7B_XDMA_GEN_FILE = $xdma_gen_file"
set xdma_gen_bad 0
if {$xdma_gen_file eq ""} {
    set xdma_gen_bad 1 ; puts "P7B_XDMA_GEN_MISSING (无生成产物可解析)"
} else {
    set fh [open $xdma_gen_file r] ; set gtxt [read $fh] ; close $fh
    foreach t {DMA_ST=1 DMA_MM=0 XDMA_AXI_INTF_MM=0 AXI_DATA_WIDTH=128 USER_CLK_FREQ=2 XDMA_AXILITE_MASTER=TRUE} {
        if {[string first $t $gtxt] < 0} { incr xdma_gen_bad ; puts "P7B_XDMA_GEN_MISS <$t>" }
    }
    puts "P7B_XDMA_GEN_BAD_N = $xdma_gen_bad"
}
# (iii) 与冻结参照转储逐行 diff (决定性: "只差预期的那几行")
proc p7b_cfg_dump {ip path} {
    set fp [open $path w]
    foreach p [lsort [list_property $ip]] {
        if {[string match "CONFIG.*" $p]} {
            set gv "<err>" ; catch { set gv [get_property $p $ip] }
            puts $fp "$p = $gv"
        }
    }
    close $fp
    return $path
}
proc p7b_cfg_diff_keys {ref mine} {
    #  ⚠️ 差异键**必须从 A 里删掉**再进 diffs —— 否则它会被"左表残留"循环**再数一次**
    #     (排练脚本 `p9_axis_impl_20261011/check_cfgdiff_teeth.tcl` 实测抓到: 2 行被数成 4 行
    #      ⇒ 构建里会**假红**)。左表残留只会剩"只在参照里、我方没有"的键。
    array set A {}
    set fa [open $ref r]
    while {[gets $fa line] >= 0} { if {[regexp {^(\S+) = (.*)$} $line -> k v]} { set A($k) $v } }
    close $fa
    set diffs {}
    set fb [open $mine r]
    while {[gets $fb line] >= 0} {
        if {[regexp {^(\S+) = (.*)$} $line -> k v]} {
            if {[info exists A($k)] && ($A($k) eq $v)} {
                unset A($k)
            } else {
                lappend diffs $k
                catch { unset A($k) }
            }
        }
    }
    close $fb
    foreach k [lsort [array names A]] { lappend diffs $k }
    return $diffs
}
set xdma_cfg_mine "${script_dir}/p7b_ku5p_xdma_cfg_post_gen.txt"
p7b_cfg_dump $xip $xdma_cfg_mine
puts "P7B_XDMA_CFG_DUMP = $xdma_cfg_mine"
set ref_dir ${root_dir}/_proj_10g/notes/p8_axis_conf_20261011/work
set xdma_diff_bad 0
foreach arm [list \
        [list ST ${ref_dir}/cfg_st_post_gen.txt [list CONFIG.Component_Name]] \
        [list MM ${ref_dir}/cfg_mm_post_gen.txt [list CONFIG.Component_Name CONFIG.xdma_axi_intf_mm]] ] {
    set tag  [lindex $arm 0]
    set ref  [lindex $arm 1]
    set exp  [lindex $arm 2]
    if {![file exists $ref]} {
        incr xdma_diff_bad ; puts "P7B_XDMA_CFGREF_MISSING $tag $ref" ; continue
    }
    set dk [p7b_cfg_diff_keys $ref $xdma_cfg_mine]
    puts "P7B_XDMA_CFGDIFF_${tag}_N = [llength $dk] ; {[join $dk { }]}"
    foreach k $dk { if {[lsearch -exact $exp $k] < 0} { incr xdma_diff_bad ; puts "P7B_XDMA_CFGDIFF_UNEXPECTED $tag $k" } }
    foreach k $exp { if {[lsearch -exact $dk $k] < 0} { incr xdma_diff_bad ; puts "P7B_XDMA_CFGDIFF_MISSING $tag $k" } }
}
if {$xdma_bad || $xdma_rb_bad != 0 || $xdma_gen_bad != 0 || $xdma_diff_bad != 0} {
    puts "P7B_VERDICT = XDMA_ST_CFG_FAIL"
    exit 1
}
puts "P7B_XDMA_VERDICT = OK (AXI_Stream / 回读 13/13 / 生成参数 6/6 / 参照 diff 只差预期行)"

# ---- 约束 -------------------------------------------------------------------
sec "P7B_CONSTR"
add_files -fileset constrs_1 ${script_dir}/ku5p_p7b_gt.xdc
add_files -fileset constrs_1 ${script_dir}/ku5p_p6e_pcie.xdc
add_files -fileset constrs_1 ${script_dir}/ku5p_p6b_sysclk.xdc
add_files -fileset constrs_1 ${script_dir}/ku5p_p7b_cdc.xdc
set_property used_in_synthesis false [get_files ${script_dir}/ku5p_p7b_cdc.xdc]

# ⚠️ 这一版是为了**线速测量**而打开 `UDP_TX_OVL`（组帧器乒乓重叠）：
#   `rtl/udp_tx_frame.v` 的 body 一分为二，`ifdef UDP_TX_OVL` = 乒乓双 bank 版（343 insertion / 0 deletion），
#   `else` = HEAD 帧器**逐字保留**（默认分支）。关掉这个 define 就回到 HEAD 的帧器行为（帧器 378 拍/帧 → 191 拍/帧）。
#   同时 `P7B_10G` 内的 8 路并行图案发生器（`rtl/app_udp_pattern.v`）一并生效。
#   两者叠加 = 本次线速测量构建；既有四个宏（APP_MODE/DEV_USP/PCIE_OBS/DP_156MHZ）与 `P7B_10G` 一字未动。
#
# ⚠️ 2026-10-07 Stage C 追加 `TCP_TX_OVL`（本刀**唯一的开关**）：
#   `rtl/tcp_tx_frame.v` 的 body 一分为二，`ifdef TCP_TX_OVL` = **乒乓双 bank / 收发重叠**版,
#   `else` = 串行版。⇒ 组帧器从"串行"换成"乒乓", TCP app TX 与 RX 并行。
#   ⛔ **宏关 ≠ HEAD**：F1 的 8 行修复（`retx_ovf` + `ring_start` 追加 `!retx_ovf`）落在
#      **默认分支**里, 逐行 diff = 恰那 8 行（`_proj_10g/notes/P7B_STAGEC_TX_REGRESSION.md` §环境事实 2）
#      ⇒ "关掉宏就回到 HEAD 的逐字行为"这句**对 `tcp_tx_frame.v` 已作废**。
#   `TIMING`/面积读数由本次构建收口（设计件 §5-2 的估计 = 无实测背书）。
set_property verilog_define {APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1 SFP2_MODE_A=1 DUAL_SFP_A=1} [current_fileset]
puts "P7B_VERILOG_DEFINE = [get_property verilog_define [current_fileset]]"
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1
puts "P7B_TOP = [get_property top [current_fileset]]"
puts "P7B_NFILES = [llength [get_files -quiet]]"
foreach f [get_files -quiet -of [get_filesets constrs_1]] { puts "P7B_CONSTR_FILE $f" }

sec "P7B_SYNTH"
reset_run synth_1
catch {launch_runs synth_1 -jobs 8} e
puts "P7B_SYNTH_LAUNCH = $e"
wait_on_run synth_1
catch {puts "P7B_SYNTH_STATUS = [get_property STATUS [get_runs synth_1]]"}
if {![string match "100%*" [get_property PROGRESS [get_runs synth_1]]]} {
    puts "P7B_VERDICT = SYNTH_FAIL"
    exit 1
}

# ---- F-6/N-3: synth 日志黑盒硬门 (这条 grep 才是硬门; cell-count 对黑盒也返回) ----
#   `black box` / `Synth 8-3491` (= 未解析模块被当黑盒) 必须 0 命中。
#   历史锚: 2026-10-18 的 0x2B 构建 `synth_1/runme.log` 实测 0 命中 ⇒ 本门不会误伤。
sec "P7B_BLACKBOX_LOG_GATE"
set synth_log "${root_dir}/vivado_prj/${project_name}.runs/synth_1/runme.log"
set bb_hits 0
if {![file exists $synth_log]} {
    puts "P7B_BLACKBOX_LOG_MISSING $synth_log"
    set bb_hits 1
} else {
    set fh [open $synth_log r]
    while {[gets $fh line] >= 0} {
        if {[regexp -nocase {black box|8-3491} $line]} {
            incr bb_hits
            if {$bb_hits <= 20} { puts "P7B_BLACKBOX_LOG_HIT $line" }
        }
    }
    close $fh
}
puts "P7B_BLACKBOX_LOG_HITS = $bb_hits"
if {$bb_hits != 0} {
    puts "P7B_VERDICT = BLACKBOX_LOG_HIT"
    exit 1
}

# ---- P11 P2-甲 (N-3/N-4): 新件模块解析硬门 ----
#   cell-count 对黑盒**也**返回实例 ⇒ 只用计数判"已解析"是假门。必须查
#   IS_BLACKBOX / report_black_boxes; 本活把两者都打出来, 任一黑盒 = 硬失败。
#   失败形态先例: mir_uram_fifo 未导入 ⇒ 安静黑盒 (构建脚本注释 :105)。
sec "P7B_MODULE_RESOLVE"
open_run synth_1
set c1 [get_cells -hier -quiet -filter {REF_NAME =~ rx_merge2}]
set c2 [get_cells -hier -quiet -filter {REF_NAME =~ tx_demux2}]
set c3 [get_cells -hier -quiet -filter {REF_NAME =~ maccnt_sync}]
set n1 [llength $c1]; set n2 [llength $c2]; set n3 [llength $c3]
puts "P7B_MODULE_RESOLVED rx_merge2=$n1 tx_demux2=$n2 maccnt_sync=$n3"
set bb 0
foreach c [concat $c1 $c2 $c3] {
    if {[get_property IS_BLACKBOX $c]} { incr bb }
}
puts "P7B_BLACKBOX_COUNT $bb"
if {$n1 < 1 || $n2 < 1 || $n3 < 1 || $bb != 0} { puts "P7B_MODULE_MISSING_OR_BLACKBOX" ; exit 1 }
close_design

sec "P7B_IMPL"
set_property strategy Performance_ExtraTimingOpt [get_runs impl_1]
reset_run impl_1
catch {launch_runs impl_1 -to_step write_bitstream -jobs 8} e2
puts "P7B_IMPL_LAUNCH = $e2"
wait_on_run impl_1
catch {puts "P7B_IMPL_STATUS = [get_property STATUS [get_runs impl_1]]"}

sec "P7B_REPORTS"
open_run impl_1
report_timing_summary -file ${script_dir}/p7b_ku5p_timing.rpt
report_utilization    -file ${script_dir}/p7b_ku5p_util.rpt
report_drc            -file ${script_dir}/p7b_ku5p_drc.rpt
report_clock_interaction -file ${script_dir}/p7b_ku5p_clkinteract.rpt
# 关键读数显式打印 (bat 里 grep) —— 不让"报告存在"冒充"读数已看"
set wns   [get_property SLACK [get_timing_paths -delay_type max]]
set whs   [get_property SLACK [get_timing_paths -delay_type min]]
puts "P7B_WNS = $wns"
puts "P7B_WHS = $whs"
puts "P7B_WPWS = [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by group]]"
puts "P7B_BIT = ${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit"
puts "P7B_BIT_EXISTS = [file exists ${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit]"
if {![file exists ${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit]} {
    puts "P7B_VERDICT = BITSTREAM_MISSING"
    exit 1
}
# F-20: 成功判据的**文本侧** (bat 侧还要叠 rc + 本行; Vivado 报 ERROR 时 rc 可能仍是 0)
puts "P7B_VERDICT = OK"
puts "P7B DONE"
exit
