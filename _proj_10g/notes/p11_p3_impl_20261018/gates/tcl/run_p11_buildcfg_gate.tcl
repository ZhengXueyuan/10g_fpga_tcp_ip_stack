#=============================================================================
# run_p11_buildcfg_gate.tcl — H-4/M-14: 构建配置 / HLS 网表配对 单测
#   正控: c3+p2_dual_max3 (无端口/无宏) ; c4+p3_dual_max8 (有端口/有宏)
#   负控: ENFORCE 缺 / 双 C / dual 无宏 / dual 网表无端口 / 非 dual 网表有端口 /
#         非 dual 定义宏 / 未知变体
#   verdict: `P11_BUILDCFG_GATE PASS` / FAIL
#=============================================================================
set script_dir [file dirname [file normalize [info script]]]
set root_dir   [file dirname [file dirname [file dirname [file dirname $script_dir]]]]
# gates/tcl -> gates -> p11_p3_impl_20261018 -> notes -> _proj_10g -> repo
set root_dir [file normalize [file join $script_dir .. .. .. .. ..]]
source [file join $root_dir board p11_build_cfg.tcl]

set fails 0
proc chk {cond name} {
    global fails
    if {$cond} { puts "P11_BUILDCFG_RULE $name OK" } else { puts "P11_BUILDCFG_RULE $name FAIL"; incr fails }
}

set base [list APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1]

# ---- 变体目录/端口计数 ----
set d1 [p11_hls_variant_dir $root_dir c1]
set d2 [p11_hls_variant_dir $root_dir p2_dual_max3]
set d3 [p11_hls_variant_dir $root_dir p3_dual_max8]
chk [file exists [file join $d1 udp_echo.v]] "c1 archive exists"
chk [file exists [file join $d2 udp_echo.v]] "p2 archive exists"
chk [file exists [file join $d3 udp_echo.v]] "p3 archive exists"
set h1 [p11_adv_wnd_hits $d1]
set h2 [p11_adv_wnd_hits $d2]
set h3 [p11_adv_wnd_hits $d3]
puts "P11_HLS_ADV_HITS c1=$h1 p2=$h2 p3=$h3"
chk [expr {$h1 == 0}] "c1 has no i_tcp_adv_wnd"
chk [expr {$h2 == 0}] "p2 has no i_tcp_adv_wnd"
chk [expr {$h3 > 0}]  "p3 has i_tcp_adv_wnd"
chk [expr {[p11_hls_variant_dir $root_dir bogus] eq ""}] "unknown variant -> empty"

# ---- 正控 ----
set defs_c3 [concat $base [list P11_CFG_C3=1 P11_CFG_ENFORCE=1 SFP2_MODE_A=1 DUAL_SFP_A=1]]
set defs_c4 [concat $base [list P11_CFG_C4=1 P11_CFG_ENFORCE=1 SFP2_MODE_A=1 DUAL_SFP_A=1 P11_DUAL=1 P11_HLS_ADV_WND=1]]
set r3 [p11_build_cfg_check $defs_c3 $h2]
set r4 [p11_build_cfg_check $defs_c4 $h3]
puts "P11_BUILDCFG_POS c3=[lindex $r3 1] config=[lindex $r3 2] ; c4=[lindex $r4 1] config=[lindex $r4 2]"
chk [expr {[lindex $r3 0] == 1 && [lindex $r3 2] eq "c3"}] "positive c3+p2"
chk [expr {[lindex $r4 0] == 1 && [lindex $r4 2] eq "c4"}] "positive c4+p3"

# ---- 负控 ----
proc neg {name defs hits want} {
    global fails
    set r [p11_build_cfg_check $defs $hits]
    set got [lindex $r 1]
    if {[lindex $r 0] == 0 && $got eq $want} {
        puts "P11_BUILDCFG_NEG $name -> $got OK"
    } else {
        puts "P11_BUILDCFG_NEG $name -> got=<$got> want=<$want> FAIL"
        incr fails
    }
}
neg "no-enforce"      [concat $base [list P11_CFG_C3=1]]                          0 P11_CFG_ENFORCE_MISSING
neg "two-C"           [concat $base [list P11_CFG_C3=1 P11_CFG_C4=1 P11_CFG_ENFORCE=1]] 0 P11_CFG_SELECT_ONE
neg "dual-no-macro"   [concat $base [list P11_CFG_C4=1 P11_CFG_ENFORCE=1 P11_DUAL=1]] 3 P11_HLS_ADV_WND_MACRO_MISSING
neg "dual-p2-net"     [concat $base [list P11_CFG_C4=1 P11_CFG_ENFORCE=1 P11_DUAL=1 P11_HLS_ADV_WND=1]] 0 P11_HLS_PORT_MISSING
neg "nondual-p3-net"  [concat $base [list P11_CFG_C3=1 P11_CFG_ENFORCE=1]]         3 P11_HLS_PORT_UNEXPECTED
neg "nondual-macro"   [concat $base [list P11_CFG_C3=1 P11_CFG_ENFORCE=1 P11_HLS_ADV_WND=1]] 0 P11_HLS_ADV_WND_MACRO_UNEXPECTED

# ---- build_p7b_ku5p.tcl 静态接线 ----
set bt [file join $root_dir board build_p7b_ku5p.tcl]
set txt ""
if {[file exists $bt]} { set fh [open $bt r]; set txt [read $fh]; close $fh }
chk [expr {[string first "p11_build_cfg.tcl" $txt] >= 0}] "build tcl sources p11_build_cfg.tcl"
chk [expr {[string first "p11_build_cfg_check" $txt] >= 0}] "build tcl calls pairing check"
chk [expr {[string first "P11_CFG_PAIRING" $txt] >= 0}] "build tcl prints P11_CFG_PAIRING"
chk [expr {[string first "P11_CONFIG" $txt] >= 0}] "build tcl prints P11_CONFIG"
chk [expr {[string first "set_property verilog_define \$P11_DEFS" $txt] >= 0}] "build tcl uses computed defines"

if {$fails == 0} {
    puts "P11_BUILDCFG_GATE PASS"
    exit 0
} else {
    puts "P11_BUILDCFG_GATE FAIL fails=$fails"
    exit 1
}
