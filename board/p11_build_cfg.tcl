#=============================================================================
# p11_build_cfg.tcl — P11 P3 (H-4/M-14): 构建配置 / HLS 网表配对 / 变体选择
#
#   纯 proc 文件 (不创建工程); 被 board/build_p7b_ku5p.tcl source, 也被
#   gates/tcl/run_p11_buildcfg_gate.tcl 单测 (正控 + 负控)。
#
#   规则 (设计件 §5.5 + FINDINGS H-4/M-14):
#     · 板构建必须 P11_CFG_ENFORCE=1, 且恰一个 P11_CFG_C{1,2,3,4}
#     · P11_DUAL=1  ⇒ HLS 网表必须有 i_tcp_adv_wnd 端口, 且宏 P11_HLS_ADV_WND=1
#     · P11_DUAL=0 ⇒ HLS 网表必须无该端口, 且不得定义该宏
#   失败返回 verdict 名; 调用方打印 `P7B_VERDICT = <verdict>` 并 exit 1。
#=============================================================================

# 返回 {ok verdict config dual advwnd}
proc p11_build_cfg_check {defs adv_hits} {
    set cn 0
    set cfg ""
    foreach {nm tag} {P11_CFG_C1 c1 P11_CFG_C2 c2 P11_CFG_C3 c3 P11_CFG_C4 c4} {
        if {[lsearch -exact $defs "${nm}=1"] >= 0} { incr cn; set cfg $tag }
    }
    set enf  [expr {[lsearch -exact $defs "P11_CFG_ENFORCE=1"] >= 0}]
    set dual [expr {[lsearch -exact $defs "P11_DUAL=1"] >= 0}]
    set advw [expr {[lsearch -exact $defs "P11_HLS_ADV_WND=1"] >= 0}]
    if {!$enf}                    { return [list 0 P11_CFG_ENFORCE_MISSING       $cfg $dual $advw] }
    if {$cn != 1}                 { return [list 0 P11_CFG_SELECT_ONE            $cfg $dual $advw] }
    if {$dual && $adv_hits <= 0}  { return [list 0 P11_HLS_PORT_MISSING           $cfg $dual $advw] }
    if {$dual && !$advw}          { return [list 0 P11_HLS_ADV_WND_MACRO_MISSING $cfg $dual $advw] }
    if {!$dual && $adv_hits > 0}  { return [list 0 P11_HLS_PORT_UNEXPECTED        $cfg $dual $advw] }
    if {!$dual && $advw}          { return [list 0 P11_HLS_ADV_WND_MACRO_UNEXPECTED $cfg $dual $advw] }
    return [list 1 OK $cfg $dual $advw]
}

# 变体 -> HLS 网表目录 (绝对路径); 未知变体返回空串
#   c1           = 0x2A 单 IP 归档 (MAX=3, 无 adv_wnd)
#   p2_dual_max3 = P2 双 IP 归档 (MAX=3, 无 adv_wnd)
#   p3_dual_max8 = P3 双 IP 归档 (MAX=8, 有 i_tcp_adv_wnd)
proc p11_hls_variant_dir {root variant} {
    switch -- $variant {
        c1 {
            return [file join $root _proj_10g notes p11_build_0x2C_20261018 hls_archive_single_ip]
        }
        p2_dual_max3 {
            return [file join $root _proj_10g notes p11_p3_build_20261019 hls_archive_p2_dual_ip_max3]
        }
        p3_dual_max8 {
            return [file join $root _proj_10g notes p11_p3_build_20261019 hls_archive_p3_dual_ip_max8]
        }
        default { return "" }
    }
}

# 按配置给默认变体 (env 显式指定的优先)
proc p11_default_variant {cfg} {
    switch -- $cfg {
        c1      { return "c1" }
        c2      { return "c1" }        ;# 乙模式业务口单 IP 网表; 乙轮定, 暂挂 c1
        c3      { return "p2_dual_max3" }
        c4      { return "p3_dual_max8" }
        default { return "" }
    }
}

# 统计 HLS 网表里 i_tcp_adv_wnd 的出现次数 (只看 udp_echo.v 顶层端口)
proc p11_adv_wnd_hits {hls_dir} {
    set f [file join $hls_dir udp_echo.v]
    if {![file exists $f]} { return -1 }
    set fh [open $f r]
    set txt [read $fh]
    close $fh
    return [regexp -all {i_tcp_adv_wnd} $txt]
}
