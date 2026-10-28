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
set mac_dir    ${root_dir}/_proj_10g/p7b_mac/rtl

# ---- P11 P3 (H-4/M-14): 配置 + HLS 网表变体配对 (硬门) -----------------------
#   环境变量:
#     P11_CFG          = c1 | c2 | c3 | c4       (默认 c3 = 本脚本历史档)
#     P11_HLS_VARIANT  = c1 | p2_dual_max3 | p3_dual_max8
#                        (默认按配置: c1->c1, c3->p2_dual_max3, c4->p3_dual_max8)
#   ⚠️ 这是一道**构建前硬门**: 网表/宏不配对 (C3 拿 P3 网表、C4 拿 P2 网表)
#      不是"能跑但有偏差", 而是 SYN-ACK 窗口 0/X 或通告 48KB vs 实配额 12KB
#      的静默错。失败 = `P7B_VERDICT = <原因>` + exit 1 (不创建工程)。
source [file join $script_dir p11_build_cfg.tcl]

set P11_CFG "c3"
if {[info exists ::env(P11_CFG)] && ($::env(P11_CFG) ne "")} {
    set P11_CFG [string tolower $::env(P11_CFG)]
}
set P11_DEFS [list APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 \
                   UDP_TX_OVL=1 TCP_TX_OVL=1]
set P11_CONFIG_NAME ""
switch -- $P11_CFG {
    c1 {
        lappend P11_DEFS P11_CFG_C1=1 P11_CFG_ENFORCE=1
        set P11_CONFIG_NAME "single"
    }
    c2 {
        lappend P11_DEFS P11_CFG_C2=1 P11_CFG_ENFORCE=1 SFP2_MODE_B=1
        set P11_CONFIG_NAME "mirror"
    }
    c3 {
        lappend P11_DEFS P11_CFG_C3=1 P11_CFG_ENFORCE=1 SFP2_MODE_A=1 DUAL_SFP_A=1
        set P11_CONFIG_NAME "shared"
    }
    c4 {
        lappend P11_DEFS P11_CFG_C4=1 P11_CFG_ENFORCE=1 SFP2_MODE_A=1 DUAL_SFP_A=1 P11_DUAL=1
        set P11_CONFIG_NAME "dual"
    }
    default {
        puts "P11_CONFIG_INPUT = <$P11_CFG>"
        puts "P7B_VERDICT = P11_CFG_UNKNOWN"
        exit 1
    }
}
set P11_IS_DUAL [expr {[lsearch -exact $P11_DEFS "P11_DUAL=1"] >= 0}]
if {$P11_IS_DUAL} { lappend P11_DEFS P11_HLS_ADV_WND=1 }

# ---- P11 APP8 (2026-10-27): 8 连接 app（8x app_pattern + 帧级 mux/demux）----
#   默认关 ⇒ 既有构建逐位不变；只在 c4（双口/共享池）下允许。
set P11_APP8_ON 0
if {[info exists ::env(P11_APP8)] && ($::env(P11_APP8) ne "") && ($::env(P11_APP8) ne "0")} {
    if {!$P11_IS_DUAL} {
        puts "P11_APP8_REQUIRES_C4"
        puts "P7B_VERDICT = P11_APP8_REQUIRES_C4"
        exit 1
    }
    lappend P11_DEFS P11_APP8=1
    set P11_APP8_ON 1
}
puts "P11_APP8 = $P11_APP8_ON"

# ---- P11 APP8 OCC (2026-10-28, REVIEW_V5 F10): 每连接接收占用 ----
#   默认 0（本文件的所有构建都定义该宏；wrapper 用宏值，不用 ifdef）。
#   1 = 0x37 修复臂（0x34/0x35 已废弃，见 DESIGN v4 supersede），必须同时 P11_APP8=1 且 c4（P11_DUAL）。
set P11_APP8_OCC_ON 0
if {[info exists ::env(P11_APP8_OCC)] && ($::env(P11_APP8_OCC) ne "")} {
    if {$::env(P11_APP8_OCC) eq "1"} {
        set P11_APP8_OCC_ON 1
    } elseif {$::env(P11_APP8_OCC) eq "0"} {
        set P11_APP8_OCC_ON 0
    } else {
        puts "P11_APP8_OCC_BAD_VALUE"
        puts "P7B_VERDICT = P11_APP8_OCC_BAD_VALUE"
        exit 1
    }
}
if {$P11_APP8_OCC_ON && ((!$P11_APP8_ON) || (!$P11_IS_DUAL))} {
    puts "P11_APP8_OCC_REQUIRES_APP8_C4"
    puts "P7B_VERDICT = P11_APP8_OCC_REQUIRES_APP8_C4"
    exit 1
}
lappend P11_DEFS P11_APP8_OCC=$P11_APP8_OCC_ON
puts "P11_APP8_OCC = $P11_APP8_OCC_ON"

# ---- P11 APP8 CDC (2026-10-29, DESIGN v4): 8×app 独立 156.25 MHz 域 ----
#   默认关（不定义宏）⇒ 既有构建逐位不变。=1 需 P11_APP8=1 && c4(P11_DUAL) &&
#   DP_156MHZ && P7B_10G（clk_in_100 在 wrapper 的 P7B_10G 分支内）。
set P11_APP8_CDC_ON 0
if {[info exists ::env(P11_APP8_CDC)] && ($::env(P11_APP8_CDC) ne "")} {
    if {$::env(P11_APP8_CDC) eq "1"} {
        set P11_APP8_CDC_ON 1
    } elseif {$::env(P11_APP8_CDC) eq "0"} {
        set P11_APP8_CDC_ON 0
    } else {
        puts "P11_APP8_CDC_BAD_VALUE"
        puts "P7B_VERDICT = P11_APP8_CDC_BAD_VALUE"
        exit 1
    }
}
if {$P11_APP8_CDC_ON && ((!$P11_APP8_ON) || (!$P11_IS_DUAL) ||
                         ([lsearch $P11_DEFS DP_156MHZ=1] < 0) ||
                         ([lsearch $P11_DEFS P7B_10G=1] < 0))} {
    puts "P11_APP8_CDC_REQUIRES_APP8_C4_DP156_P7B10G"
    puts "P7B_VERDICT = P11_APP8_CDC_REQUIRES_APP8_C4_DP156_P7B10G"
    exit 1
}
if {$P11_APP8_CDC_ON} { lappend P11_DEFS P11_APP8_CDC=1 }
puts "P11_APP8_CDC = $P11_APP8_CDC_ON"

# ⭐ 2026-10-27 E1a 0x33: implementation strategy is a build input (default = the
#    0x31/0x32 Performance_Explore). A retry with a different strategy is a NEW INPUT,
#    not "rerun until pass"; used only if the first build's timing gate fails.
set P11_IMPL_STRATEGY "Performance_Explore"
if {[info exists ::env(P11_IMPL_STRATEGY)] && ($::env(P11_IMPL_STRATEGY) ne "")} {
    set P11_IMPL_STRATEGY $::env(P11_IMPL_STRATEGY)
}
puts "P11_IMPL_STRATEGY = $P11_IMPL_STRATEGY"

set CFG_HLS_VARIANT ""
if {[info exists ::env(P11_HLS_VARIANT)] && ($::env(P11_HLS_VARIANT) ne "")} {
    set CFG_HLS_VARIANT $::env(P11_HLS_VARIANT)
} else {
    set CFG_HLS_VARIANT [p11_default_variant $P11_CFG]
}
set hls_dir [p11_hls_variant_dir $root_dir $CFG_HLS_VARIANT]
if {$hls_dir eq ""} {
    puts "P11_HLS_VARIANT_INPUT = <$CFG_HLS_VARIANT>"
    puts "P7B_VERDICT = P11_HLS_VARIANT_UNKNOWN"
    exit 1
}
if {![file exists [file join $hls_dir udp_echo.v]]} {
    puts "P11_HLS_DIR_MISSING = $hls_dir"
    puts "P7B_VERDICT = P11_HLS_NETLIST_MISSING"
    exit 1
}
set P11_ADV_HITS [p11_adv_wnd_hits $hls_dir]
set P11_CFG_CHK [p11_build_cfg_check $P11_DEFS $P11_ADV_HITS]
puts "P11_CFG_INPUT  = $P11_CFG (env) ; HLS_VARIANT = $CFG_HLS_VARIANT"
puts "P11_CONFIG     = [lindex $P11_CFG_CHK 2] ($P11_CONFIG_NAME)"
puts "P11_HLS_DIR    = $hls_dir"
puts "P11_HLS_ADV_WND_HITS = $P11_ADV_HITS (P11_DUAL=$P11_IS_DUAL)"
puts "P7B_VERILOG_DEFINE_LIST = $P11_DEFS"
if {[lindex $P11_CFG_CHK 0] != 1} {
    puts "P11_CFG_PAIRING_FAIL = [lindex $P11_CFG_CHK 1]"
    puts "P7B_VERDICT = [lindex $P11_CFG_CHK 1]"
    exit 1
}
puts "P11_CFG_PAIRING = OK"

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
    ${root_dir}/rtl/app_multi8.v ${root_dir}/rtl/axis_frame_mux8.v \
    ${root_dir}/rtl/axis_tid_demux8.v ${root_dir}/rtl/app_close_arb8.v \
    ${root_dir}/rtl/app_clk_gen.v ${root_dir}/rtl/app_multi8_cdc.v \
    ${root_dir}/rtl/app_status_uart.v     ${root_dir}/rtl/rx_merge2.v ${root_dir}/rtl/tx_demux2.v ${root_dir}/rtl/maccnt_sync.v \
    ${root_dir}/rtl/win_pool_mgr.v ${root_dir}/rtl/retx_pool_shared.v \
    ${root_dir}/rtl/slow_merge2.v ${root_dir}/rtl/slow_demux2.v ${root_dir}/rtl/slow_cfg_demux.v
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
# ⛔ 2026-10-26 修复 (0x31 板级定位): 旧代码先试 `imports/verilog/udp_echo.v`;
#    该路径不存在时 `file dirname ""` 返回 "." (**不是空串**) ⇒ 下面的 if 不触发,
#    `.dat` 被拷到构建 CWD (`board/`) 而不是导入目录 ⇒ 综合报
#    `Synth 8-4445 could not open $readmem ...` + `rom0 ... does not have driver` ⇒
#    preamble/src_mac/arp_dump ROM 全 0 ⇒ HLS 每帧前导 = 0x00 ⇒ slow_tx_adp 全 purge
#    (0x31 板级: W7=0 / W18 随请求递增 / W20=0)。这里改为**确定路径 + 硬失败**,
#    不再有 "." 回退; 并在 synth 日志门里复查 (见 P7B_HLS_ROM_LOG_GATE)。
set hls_imp_dir [file join ${root_dir}/vivado_prj/${project_name}.srcs/sources_1/imports [file tail $hls_dir]]
if {![file exists [file join $hls_imp_dir udp_echo.v]]} {
    set hls_imp_hits [glob -nocomplain ${root_dir}/vivado_prj/${project_name}.srcs/sources_1/imports/*/udp_echo.v]
    if {[llength $hls_imp_hits] != 1} {
        puts "P11_HLS_IMPORT_DIR_HITS = [llength $hls_imp_hits]"
        puts "P7B_VERDICT = HLS_IMPORT_DIR_MISSING"
        exit 1
    }
    set hls_imp_dir [file dirname [lindex $hls_imp_hits 0]]
}
set hls_dat_files [glob -nocomplain ${hls_dir}/*.dat]
if {[llength $hls_dat_files] < 1} {
    puts "P11_HLS_DAT_N = 0"
    puts "P7B_VERDICT = HLS_DAT_MISSING"
    exit 1
}
set hls_dat_copied 0
foreach dat $hls_dat_files {
    set dst [file join $hls_imp_dir [file tail $dat]]
    if {[catch {file copy -force $dat $dst} e]} {
        puts "P11_HLS_DAT_COPY_FAIL $dat -> $dst : $e"
        puts "P7B_VERDICT = HLS_DAT_COPY_FAIL"
        exit 1
    }
    if {![file exists $dst] || [file size $dst] != [file size $dat]} {
        puts "P11_HLS_DAT_COPY_VERIFY_FAIL $dst"
        puts "P7B_VERDICT = HLS_DAT_COPY_VERIFY_FAIL"
        exit 1
    }
    incr hls_dat_copied
}
puts "P11_HLS_DAT_COPIED = $hls_dat_copied dir=$hls_imp_dir"

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
# P11 APP8 0x34 pblock 实验 (2026-10-28): **实测否定** —— build_fail2 读数
#   WNS -0.644 / setup 13,282 vs 无 pblock 的 -0.337 / 6,642 ⇒ 隔离 u_app 反而更差.
# ⇒ 默认 **关闭**; 只有显式 P11_APP8_PBLOCK=1 才重新引入 (保留为可复跑实验).
# 见 ku5p_p7b_app8.xdc 头注释 + build_fail2/FAILURE.md.
if {[info exists ::env(P11_APP8_PBLOCK)] && ($::env(P11_APP8_PBLOCK) eq "1")} {
    add_files -fileset constrs_1 ${script_dir}/ku5p_p7b_app8.xdc
    set_property used_in_synthesis false [get_files ${script_dir}/ku5p_p7b_app8.xdc]
    puts "P11_APP8_PBLOCK = 1 (negative experiment re-enabled)"
} else {
    puts "P11_APP8_PBLOCK = 0 (pblock experiment disabled; see build_fail2/FAILURE.md)"
}
# P11 APP8 CDC (0x36/0x37): clk_app↔dp_clk 双向 false_path (只 CDC 构建; DESIGN v4 §2.2)
if {$P11_APP8_CDC_ON} {
    add_files -fileset constrs_1 ${script_dir}/ku5p_p7b_app8_cdc.xdc
    set_property used_in_synthesis false [get_files ${script_dir}/ku5p_p7b_app8_cdc.xdc]
    puts "P11_APP8_CDC_XDC = 1 (false_path clk_app <-> dp_clk)"
} else {
    puts "P11_APP8_CDC_XDC = 0"
}

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
# P11 P3 (2026-10-19): 四配置选择 (设计件 §2.1). 默认 = C3 cfg_shared (0x2D).
#   C4 构建 = `P11_CFG=c4` (⇒ P11_CFG_C4 + P11_DUAL + P11_HLS_ADV_WND, P3 网表)。
#   HLS 网表/宏配对已在脚本开头硬判 (H-4); 这里只落宏。
set_property verilog_define $P11_DEFS [current_fileset]
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

# ---- HLS $readmemh ROM 初始化硬门 (2026-10-26 0x31 板级定位) ----
#   0x31 的 synth 日志实测: 3 条 `Synth 8-4445 could not open $readmem` +
#   3 条 `Synth 8-3848 ... rom0 ... does not have driver`。后果 = preamble/src_mac/
#   arp_dump ROM 全 0 ⇒ HLS TX 每帧前导 0x00 ⇒ slow_tx_adp 结构性全 purge
#   (板级 W7 恒 0 / W18 随请求递增 / W20=0; 所有 TCP 建连走慢路径 ⇒ 全线不可用)。
#   这条门必须在 impl 之前拦下: 只信"文件已拷"不够, 要信综合真的读到了。
sec "P7B_HLS_ROM_LOG_GATE"
set rom_hits 0
set rom_read_ok 0
if {![file exists $synth_log]} {
    puts "P7B_HLS_ROM_LOG_MISSING $synth_log"
    puts "P7B_VERDICT = HLS_ROM_LOG_MISSING"
    exit 1
}
set fh [open $synth_log r]
while {[gets $fh line] >= 0} {
    if {[regexp -nocase {8-4445|could not open \$readmem|rom0.*does not have driver} $line]} {
        incr rom_hits
        if {$rom_hits <= 20} { puts "P7B_HLS_ROM_LOG_HIT $line" }
    }
    if {[regexp -nocase {8-3876.*read successfully} $line]} {
        incr rom_read_ok
    }
}
close $fh
puts "P7B_HLS_ROM_LOG_HITS = $rom_hits"
puts "P7B_HLS_ROM_READ_OK = $rom_read_ok (expect >= $hls_dat_copied)"
if {$rom_hits != 0} {
    puts "P7B_VERDICT = HLS_ROM_UNINIT"
    exit 1
}
# kimi M-6 (2026-10-26 review): 只查失败会漏掉"读被跳过但没警告"的静默态；
#   正读 `8-3876 ... read successfully` 必须 >= 本次拷贝的 .dat 数。
if {$rom_read_ok < $hls_dat_copied} {
    puts "P7B_VERDICT = HLS_ROM_READ_MISSING"
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
# ⛔ P11 0x2D backstop-1 (2026-10-18): 预登记 backstop 第 1 档「删 W86/W87」删除了
#    u_maccnt_ch0rx/u_maccnt_ch0tx 的唯一消费者 (p7bdp 槽 42/43) ⇒ 无负载实例会被
#    综合剪掉 ⇒ maccnt_sync 实例数 = 0 是本档的**预期读数**, 不是黑盒/漏导入。
#    非 C4 档仍硬性要求 rx_merge2/tx_demux2 ≥1 且所有实例 IS_BLACKBOX=0; maccnt_sync
#    只作读数打印。⚠️ 若后续退档恢复 W86/W87, 必须把 `$n3 < 1` 条件加回。
# ⭐ P11 P3 C4 (2026-10-19): fast merge/demux **退役** ⇒ 本档预期 n1=n2=0;
#    改查 5 个 P3 新件 (win_pool_mgr/retx_pool_shared/slow_merge2/slow_demux2/
#    slow_cfg_demux) 均 ≥1 且无黑盒。固定句: C4 若出现 rx_merge2/tx_demux2 也是错。
if {$P11_IS_DUAL} {
    set bb 0
    foreach c [concat $c1 $c2 $c3] {
        if {[get_property IS_BLACKBOX $c]} { incr bb }
    }
    set p3ok 1
    foreach nm {win_pool_mgr retx_pool_shared slow_merge2 slow_demux2 slow_cfg_demux} {
        set cc [get_cells -hier -quiet -filter "REF_NAME =~ $nm"]
        set nn [llength $cc]
        puts "P7B_P3_MODULE $nm=$nn"
        if {$nn < 1} { set p3ok 0 }
        foreach c $cc {
            if {[get_property IS_BLACKBOX $c]} { incr bb }
        }
    }
    # P11 APP8 (v6): 4 个新件必须解析且非黑盒（REVIEW_RESPONSE M12；0x24 URAM 先例）
    #   ⚠️ app_close_arb8 在 0x34/0x35 的连续 app (TX_CONTINUOUS=1) 下输入 close_req
    #   恒 0 ⇒ 综合合法折叠为 0 个 cell；0x34 首跑即此假红（其余 3 件 =1，
    #   P7B_BLACKBOX_LOG_HITS=0）。⇒ 硬门只要求前 3 件 ≥1；close arb 计数只登记，
    #   若存在则查黑盒。模块功能由 tb_app_multi8 的 C 段单元门覆盖。
    if {$P11_APP8_ON} {
        foreach nm {app_multi8 axis_frame_mux8 axis_tid_demux8} {
            set cc [get_cells -hier -quiet -filter "REF_NAME =~ $nm"]
            set nn [llength $cc]
            puts "P7B_APP8_MODULE $nm=$nn"
            if {$nn < 1} { set p3ok 0 }
            foreach c $cc {
                if {[get_property IS_BLACKBOX $c]} { incr bb }
            }
        }
        # P11 APP8 CDC (V4-15): 新件 app_clk_gen / app_multi8_cdc 必须解析且非黑盒。
        # 漏导入形态: u_appclkgen 黑盒 ⇒ 无 clk_app, app 不工作而综合/时序照样过。
        if {$P11_APP8_CDC_ON} {
            foreach nm {app_clk_gen app_multi8_cdc} {
                set cc [get_cells -hier -quiet -filter "REF_NAME =~ $nm"]
                set nn [llength $cc]
                puts "P7B_APP8_MODULE $nm=$nn (CDC)"
                if {$nn < 1} { set p3ok 0 }
                foreach c $cc {
                    if {[get_property IS_BLACKBOX $c]} { incr bb }
                }
            }
        }
        set cc [get_cells -hier -quiet -filter "REF_NAME =~ app_close_arb8"]
        set nn [llength $cc]
        puts "P7B_APP8_MODULE app_close_arb8=$nn (0 expected: continuous app closes never)"
        foreach c $cc {
            if {[get_property IS_BLACKBOX $c]} { incr bb }
        }
    }
    puts "P7B_BLACKBOX_COUNT $bb"
    if {$n1 != 0 || $n2 != 0 || !$p3ok || $bb != 0} {
        puts "P7B_MODULE_MISSING_OR_BLACKBOX" ; exit 1
    }
} else {
    set bb 0
    foreach c [concat $c1 $c2 $c3] {
        if {[get_property IS_BLACKBOX $c]} { incr bb }
    }
    puts "P7B_BLACKBOX_COUNT $bb"
    if {$n1 < 1 || $n2 < 1 || $bb != 0} {
        puts "P7B_MODULE_MISSING_OR_BLACKBOX" ; exit 1
    }
}

# ---- P11 F-21: W83/W84 must pass through u_snap_p7bdp's coherent CDC ----
#   0x2C 构建的布后实测: `snap_dout_all` 顶部 5 项走 `w8x_snap = w8x_dp` 直连 ⇒
#   p7bdp 槽 39..43 成死逻辑 (`hold_b_reg[1248..1407]` = 0 个寄存器),
#   `tx_p0_frames_r_reg[0]/Q` 直接进 `u_pcie_regs/snap_din` (裸多比特 CDC)。
#   ⛔ P11 0x2D backstop-1 (2026-10-18): W86/W87 已删 ⇒ 剩余槽集 = 39..41;
#      ⛔ backstop-2: 再删 W85 ⇒ 剩余槽集 = 39..40 (位 1248..1311; 对应 W83/W84)。
#      ⭐ P11 E1a-1 (2026-10-27): E1A_EN=1 (P11_DUAL/c4) 时槽集 = **39..52** (14 槽);
#      非 E1A 构建 (c1/c3) 新槽是常量 0 ⇒ 只查 39..40 (2 槽), 避免假红。
#      门**必须**按剩余槽集检查, 否则会因已删槽位不存在而假红。改动属新输入,
#      已在 0x2D retry 报告登记。
#   本段是**综合后 (post-synth) 结构门** (open_run synth_1 = 综合网表; 构建轮执行):
#     ① 槽 39..top_hi (E1A: 52, 位 1248..1695; 非 E1A: 40) 每槽至少 1 个 hold_b 寄存器;
#     ② `tx_p0_frames_r_reg[0]/Q` 的负载里**必须**有 u_snap_p7bdp/hold_b,
#        且**不得**有 u_pcie_regs/snap_din (综合名) / snap_words_r (布局名)。
#   ⚠️ 负载枚举必须 `get_pins -leaf`: 层次边界 pin
#      `u_snap_p7bdp/tx_p0_frames_r_reg[0]` 只是别名, 非叶子 pin 枚举会漏掉
#      `u_snap_p7bdp/hold_b_reg[1248]/D` ⇒ 假红 (0x2D 首跑即此)。
#   失败 = `P7B_SNAP_TOP5_CDC_MISSING` / `P7B_SNAP_TOP5_FANOUT_BAD` + exit 1。
sec "P7B_SNAP_TOP5_CDC"
# ⭐ E1a-1: slots 41..52 exist only when E1A_EN=1 (P11_DUAL). In c1/c3 the sources are
#    constant 0, so hold_b cells may be optimized away; checking them would be a false red.
set e1a_on 0
if {[lsearch -exact $P11_DEFS "P11_DUAL=1"] >= 0} { set e1a_on 1 }
# P11 APP8 CDC (V4-05): W97 = p7bdp 槽 53 ⇒ 必须把 53 也纳入 hold_b 检查，
# 否则新字走裸多比特 CDC（F-21 同类复发面；0x2C 已实测过该形态）。
set top_hi [expr {$P11_APP8_CDC_ON ? 53 : ($e1a_on ? 52 : 40)}]
puts "P7B_SNAP_TOP5_E1A_ON = $e1a_on (slots 39..$top_hi)"
set top5_bad 0
for {set s 39} {$s <= $top_hi} {incr s} {
    set lo [expr {$s * 32}]
    set hi [expr {$s * 32 + 31}]
    set nc 0
    for {set b $lo} {$b <= $hi} {incr b} {
        if {[llength [get_cells -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[$b\]"]] > 0} {
            incr nc
        }
    }
    puts "P7B_SNAP_TOP5_SLOT slot=$s bits=$lo..$hi cells=$nc"
    if {$nc < 1} { incr top5_bad }
}
if {$top5_bad != 0} {
    puts "P7B_SNAP_TOP5_CDC_MISSING slots_with_zero_cells=$top5_bad"
    exit 1
}
puts "P7B_SNAP_TOP5_SLOTS_OK = [expr {$top_hi - 39 + 1}]"
set f_pin [get_pins -quiet -filter "NAME == tx_p0_frames_r_reg\[0\]/Q"]
if {[llength $f_pin] != 1} {
    puts "P7B_SNAP_TOP5_FANOUT_BAD pin_not_found tx_p0_frames_r_reg\[0\]/Q"
    exit 1
}
set f_nets [get_nets -quiet -of_objects $f_pin]
set f_loads {}
foreach n $f_nets { set f_loads [concat $f_loads [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]] }
set f_hb 0
set f_sd 0
foreach l $f_loads {
    set ln [get_property NAME $l]
    if {[string match "*u_snap_p7bdp/hold_b_reg*" $ln]} { incr f_hb }
    if {[string match "*u_pcie_regs/snap_din*" $ln] || [string match "*u_pcie_regs/snap_words_r*" $ln]} { incr f_sd }
}
puts "P7B_SNAP_TOP5_FANOUT tx_p0_frames_r_reg\[0\]/Q loads=[llength $f_loads] hold_b=$f_hb snap_din=$f_sd"
if {$f_hb < 1 || $f_sd != 0} {
    puts "P7B_SNAP_TOP5_FANOUT_BAD hold_b=$f_hb snap_din=$f_sd"
    exit 1
}
puts "P7B_SNAP_TOP5_FANOUT_OK"

# ---- P11 0x2F: 定向 STA 预检 (synth 后; 可 P11_STA_ONLY=1 单独跑) -----------
#   0x2F 的 73 min 构建在最后才发现 42 级 rel 路径 (WNS -6.456)。本段在
#   synth 网表上先把 "app_ctrl 扫描态 -> win_pool 状态" 与 ev_up 路径的
#   估计 slack 打出来, 并给出全局最差几条, 便于在 impl 前发现形态错误。
sec "P11_STA_PRECHECK"
set wpm_rel_pins [get_pins -hier -quiet -regexp {u_app_ctrl.*c_rcv_nxt_reg.*/C}]
set wpm_dst_pins [get_pins -hier -quiet -regexp {u_win_pool/.*/D}]
puts "P11_STA_WPM_REL_PINS = [llength $wpm_rel_pins]"
puts "P11_STA_WPM_DST_PINS = [llength $wpm_dst_pins]"
if {[llength $wpm_rel_pins] > 0 && [llength $wpm_dst_pins] > 0} {
    set tp_rel [get_timing_paths -from $wpm_rel_pins -to $wpm_dst_pins \
                    -max_paths 1 -delay_type max]
    if {[llength $tp_rel] > 0} {
        puts "P11_STA_WPM_REL_WNS = [get_property SLACK [lindex $tp_rel 0]]"
        puts "P11_STA_WPM_REL_SRC = [get_property STARTPOINT_PIN [lindex $tp_rel 0]]"
        puts "P11_STA_WPM_REL_DST = [get_property ENDPOINT_PIN [lindex $tp_rel 0]]"
        puts "P11_STA_WPM_REL_LEVELS = [get_property LOGIC_LEVELS [lindex $tp_rel 0]]"
    } else {
        puts "P11_STA_WPM_REL_WNS = NA"
    }
} else {
    puts "P11_STA_WPM_REL_WNS = NA (pins not found)"
}
foreach {tag from_pat} {evup0 {u_slow_cfg/ev_up_reg/C} evup1 {u_slow_cfg2/ev_up_reg/C}} {
    set fp [get_pins -quiet $from_pat]
    if {[llength $fp] > 0 && [llength $wpm_dst_pins] > 0} {
        set tp [get_timing_paths -from $fp -to $wpm_dst_pins -max_paths 1 -delay_type max]
        if {[llength $tp] > 0} {
            puts "P11_STA_WPM_${tag}_WNS = [get_property SLACK [lindex $tp 0]]"
        } else {
            puts "P11_STA_WPM_${tag}_WNS = NA"
        }
    } else {
        puts "P11_STA_WPM_${tag}_WNS = NA (pins not found)"
    }
}
set tp_top [get_timing_paths -max_paths 5 -delay_type max]
puts "P11_STA_TOP_COUNT = [llength $tp_top]"
foreach p $tp_top {
    puts "P11_STA_TOP slack=[get_property SLACK $p] src=[get_property STARTPOINT_PIN $p] dst=[get_property ENDPOINT_PIN $p] lvl=[get_property LOGIC_LEVELS $p]"
}
if {[info exists ::env(P11_STA_ONLY)] && $::env(P11_STA_ONLY) == "1"} {
    # synth 检查点也留资源报告（P11 APP8 估 LUT 预算用；不改变任何设计）
    report_utilization -hierarchical -hierarchical_depth 2         -file ${root_dir}/board/p11_synth_util.rpt
    puts "P11_SYNTH_UTIL_RPT = ${root_dir}/board/p11_synth_util.rpt"
    puts "P11_STA_ONLY_OK"
    puts "P7B_VERDICT = OK"
    close_design
    exit 0
}
close_design

sec "P7B_IMPL"
# 0x30/0x31: 0x2F/0x30 的 TCB 写口族 (`u_tcp_tx/u_fifo_* -> u_tcb/*`) 是
#   既存最差族: 0x2F -3.77 / 0x30 -0.418 (manager 修好后才显形)。RTL 侧任何
#   TCB 写延迟都会破坏 retx 序列 (txdrop50 实测 3/5 帧失配)，因此改走 placement
#   策略搜索 (P7B_MAC_TIMING_FIX §7.3: 同 RTL 换策略可摆动 0.2–0.46 ns，方向
#   不可控；本轮用它争取 0.418 ns 的缺口，结果由构建门裁定)。
set_property strategy $P11_IMPL_STRATEGY [get_runs impl_1]
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
# ---- P11 P3 (M-13): frame_fifo 32 片选定向 STA (登记; 构建轮执行观察) --------
#   C4 的每口 tcp_echo = frame_fifo D=16384/AW=14 ⇒ NB=D/512=32 片选,
#   main_sel 32 路 OR + 边存 16384x9; 设计件的 +27–30k LUT 估计**未显式计**
#   第一口 64→128KB 的 +1.1–2.2k LUT。构建轮必须:
#     ① 核对 placed LUT/BRAM 与设计件 §6 的纸面包络;
#     ② 对每个 frame_fifo 实例做定向 STA (例如
#        `report_timing -max_paths 10 -through [get_pins -hier <inst>/*/C]`,
#        或按实例内 main_sel/addr 网定向 `-from/-to`), 而不是只看 top-N。
#   本脚本只**枚举实例名** (构建日志留证); 定向报告在构建轮按上面命令执行。
sec "P11_FRAME_FIFO_STA"
set ff_cells [get_cells -hier -quiet -filter {REF_NAME =~ frame_fifo}]
puts "P11_FRAME_FIFO_STA_CELLS = [llength $ff_cells]"
foreach c $ff_cells { puts "P11_FRAME_FIFO_STA_CELL $c" }

set wns   [get_property SLACK [get_timing_paths -delay_type max]]
set whs   [get_property SLACK [get_timing_paths -delay_type min]]
puts "P7B_WNS = $wns"
puts "P7B_WHS = $whs"
puts "P7B_WPWS = [get_property SLACK [get_timing_paths -delay_type min_max -max_paths 1 -sort_by group]]"

# ---- P11 0x2F: 时序硬门 (WNS>0 ∧ setup/hold/PW 失败端点=0) ----------------
#   ⛔ 0x2F 的 P7B_VERDICT=OK 只判"位流文件存在" ⇒ 时序 -6.456ns 的位流也拿了 OK。
#   本段把报告里的三类失败端点数读出来, 不满足就把位流改名隔离 + 硬失败退出。
sec "P7B_TIMING_GATE"
set setup_fail -1
set hold_fail  -1
set pw_fail    -1
set ts_report "${script_dir}/p7b_ku5p_timing.rpt"
if {[file exists $ts_report]} {
    set fh [open $ts_report r]
    set ts_txt [read $fh]
    close $fh
    # ⚠️ 不能抓第一个 "Setup :" —— report_timing_summary 先给每个时钟组各一段,
    #   第一段通常是某个子组 (0 失败), 而全局失败在最后/顶端表. 0x30 首跑实测:
    #   全局 3126 失败 / WNS -0.418, 而第一个 "Setup :" 是 0 ⇒ 旧解析假绿.
    #   正确来源 = "Design Timing Summary" 后的 12 列数据行
    #   (WNS TNS setup_fail setup_total WHS THS hold_fail hold_total WPWS TPWS pw_fail pw_total).
    set dts_idx [string first "Design Timing Summary" $ts_txt]
    if {$dts_idx >= 0} {
        set dts_txt [string range $ts_txt $dts_idx end]
        if {[regexp {\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)\s+(-?[0-9.]+)\s+(-?[0-9.]+)\s+(\d+)\s+(\d+)} $dts_txt -> \
                ts_wns ts_tns setup_fail ts_setup_total ts_whs ts_ths hold_fail ts_hold_total \
                ts_wpws ts_tpws pw_fail ts_pw_total]} {
            puts "P7B_TIMING_TABLE_WNS = $ts_wns"
            puts "P7B_TIMING_TABLE_TNS = $ts_tns"
            puts "P7B_TIMING_TABLE_SETUP_TOTAL = $ts_setup_total"
        } else {
            puts "P7B_TIMING_TABLE_PARSE_FAIL"
        }
    } else {
        puts "P7B_TIMING_TABLE_MISSING"
    }
} else {
    puts "P7B_TIMING_REPORT_MISSING $ts_report"
}
if {![string is double -strict $wns]} { set wns -999.0 }
puts "P7B_TIMING_SETUP_FAIL = $setup_fail"
puts "P7B_TIMING_HOLD_FAIL = $hold_fail"
puts "P7B_TIMING_PW_FAIL = $pw_fail"
# 口径对称 (kimi L-7): 判定用 Design Timing Summary 表值; get_timing_paths 值只作
#   交叉核对. 两者不一致时打印 MISMATCH (不掩盖), 仍以表值为准.
if {[info exists ts_wns] && [string is double -strict $ts_wns]} {
    puts "P7B_TIMING_WNS_DB = $wns"
    puts "P7B_TIMING_WNS_TABLE = $ts_wns"
    if {abs($wns - $ts_wns) > 0.000001} {
        puts "P7B_TIMING_WNS_MISMATCH db=$wns table=$ts_wns"
    }
    set wns_gate $ts_wns
} else {
    set wns_gate $wns
}
set timing_ok [expr {($wns_gate > 0.0) && ($setup_fail == 0) && ($hold_fail == 0) && ($pw_fail == 0)}]
if {$timing_ok} {
    puts "P7B_TIMING_GATE = PASS"
} else {
    puts "P7B_TIMING_GATE = FAIL (wns=$wns_gate setup=$setup_fail hold=$hold_fail pw=$pw_fail)"
    set bitfile "${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit"
    if {[file exists $bitfile]} {
        file rename -force $bitfile "${bitfile}.TIMING_FAIL"
        puts "P7B_BIT_QUARANTINED = ${bitfile}.TIMING_FAIL"
    }
    puts "P7B_VERDICT = TIMING_FAIL"
    exit 1
}

# ---- P11 0x31: TCB 写口族定向 STA 硬门 (kimi M-3) --------------------------
#   0x2F/0x30 的教训 = top-10 被 manager 链盖住, 真正的既存族
#   `u_tcp_tx/u_fifo_* -> u_tcb/*` 只在定向查询里可见. 本段在 post-route 设计上
#   强制查这 4 个族; C4 下任一族 slack < P11_STA_MIN_NS (默认 0.0) 或 pin 缺失
#   => STA_FAMILY_FAIL + 位流改名隔离. 非 C4 只打印 SKIP.
#   ⚠️ 本门是全局时序门的**补充**, 不替代 WNS/端点门.
sec "P11_STA_TCB_GATE"
set p11_sta_min 0.0
if {[info exists ::env(P11_STA_MIN_NS)] && $::env(P11_STA_MIN_NS) ne ""} {
    set p11_sta_min [expr {double($::env(P11_STA_MIN_NS))}]
}
# ⭐ 2026-10-26 review finding: 0x32 的全局 WNS 宿主是 **stack2** 的
#   `u_tcp_tx2/u_fifo_b/rptr[0] -> u_tcb2/rcv_wnd[9][0]` (+0.019); 原 A–F 只覆盖
#   stack1 (min +0.115) ⇒ 本门对真实最差族是盲的。A2–F2 = stack2 同族;
#   G2 = stack2 的 u_fifo_b/rptr -> rcv_wnd (0x32 全局 WNS 宿主)。
#   0x32 routed DCP 实测: A2=0.047 / C2=0.041 / G2=0.019; MIN=0.019。
set tcb_fams [list \
    A {u_tcp_tx/u_fifo_a/rptr_reg\[.*\]/C} {u_tcb/rcv_wnd_r_reg\[.*\]/CE} \
    B {u_tcp_tx/u_fifo_b/wptr_reg\[.*\]/C} {u_tcb/snd_nxt_r_reg\[.*\]/CE} \
    C {u_tcp_tx/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb/snd_una_r_reg\[.*\]/CE} \
    D {u_tcp_tx/u_ackq/rptr_reg\[.*\]/C} {u_tcb/rcv_wnd_r_reg\[.*\]/CE} \
    E {u_tcp_tx/u_fifo_b/wptr_reg\[.*\]/C} {u_tcb/snd_wnd_r_reg\[.*\]/CE} \
    F {u_tcp_tx/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb/snd_wnd_r_reg\[.*\]/CE} \
    A2 {u_tcp_tx2/u_fifo_a/rptr_reg\[.*\]/C} {u_tcb2/rcv_wnd_r_reg\[.*\]/CE} \
    B2 {u_tcp_tx2/u_fifo_b/wptr_reg\[.*\]/C} {u_tcb2/snd_nxt_r_reg\[.*\]/CE} \
    C2 {u_tcp_tx2/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb2/snd_una_r_reg\[.*\]/CE} \
    D2 {u_tcp_tx2/u_ackq/rptr_reg\[.*\]/C} {u_tcb2/rcv_wnd_r_reg\[.*\]/CE} \
    E2 {u_tcp_tx2/u_fifo_b/wptr_reg\[.*\]/C} {u_tcb2/snd_wnd_r_reg\[.*\]/CE} \
    F2 {u_tcp_tx2/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb2/snd_wnd_r_reg\[.*\]/CE} \
    G2 {u_tcp_tx2/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb2/rcv_wnd_r_reg\[.*\]/CE}]
set tcb_min 999.0
set tcb_na  0
if {$P11_CFG eq "c4"} {
    foreach {tag fpat tpat} $tcb_fams {
        set fp [get_pins -hier -quiet -regexp $fpat]
        set tp [get_pins -hier -quiet -regexp $tpat]
        if {[llength $fp] > 0 && [llength $tp] > 0} {
            set tpath [get_timing_paths -from $fp -to $tp -max_paths 1 -delay_type max]
            if {[llength $tpath] > 0} {
                set tsl [get_property SLACK [lindex $tpath 0]]
                puts "P11_STA_TCB_$tag = $tsl"
                puts "P11_STA_TCB_${tag}_SRC = [get_property STARTPOINT_PIN [lindex $tpath 0]]"
                puts "P11_STA_TCB_${tag}_DST = [get_property ENDPOINT_PIN [lindex $tpath 0]]"
                puts "P11_STA_TCB_${tag}_LVL = [get_property LOGIC_LEVELS [lindex $tpath 0]]"
                if {$tsl < $tcb_min} { set tcb_min $tsl }
            } else {
                puts "P11_STA_TCB_$tag = NA (no path)"
                set tcb_na 1
            }
        } else {
            puts "P11_STA_TCB_$tag = NA (pins from=[llength $fp] to=[llength $tp])"
            set tcb_na 1
        }
    }
    puts "P11_STA_TCB_MIN = $tcb_min"
    if {$tcb_na} {
        puts "P11_STA_TCB_GATE = FAIL (family pins missing)"
        set bitfile "${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit"
        if {[file exists $bitfile]} {
            file rename -force $bitfile "${bitfile}.STA_FAMILY_FAIL"
            puts "P7B_BIT_QUARANTINED = ${bitfile}.STA_FAMILY_FAIL"
        }
        puts "P7B_VERDICT = STA_FAMILY_FAIL"
        exit 1
    }
    if {$tcb_min < $p11_sta_min} {
        puts "P11_STA_TCB_GATE = FAIL (min=$tcb_min < $p11_sta_min)"
        set bitfile "${root_dir}/vivado_prj/${project_name}.runs/impl_1/${top_module}.bit"
        if {[file exists $bitfile]} {
            file rename -force $bitfile "${bitfile}.STA_FAMILY_FAIL"
            puts "P7B_BIT_QUARANTINED = ${bitfile}.STA_FAMILY_FAIL"
        }
        puts "P7B_VERDICT = STA_FAMILY_FAIL"
        exit 1
    }
    puts "P11_STA_TCB_GATE = PASS"
} else {
    puts "P11_STA_TCB_GATE = SKIP (non-c4)"
}
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
