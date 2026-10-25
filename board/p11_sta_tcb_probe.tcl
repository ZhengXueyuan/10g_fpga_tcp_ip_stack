#=============================================================================
# p11_sta_tcb_probe.tcl — P11 C4 关键族定向 STA (可在任意 routed DCP 上复跑)
#
# 用法 (Git Bash / cmd):
#   P11_STA_DCP=<path-to-routed.dcp> P11_STA_MIN_NS=0.0 \
#       vivado -mode batch -source board/p11_sta_tcb_probe.tcl -nojournal -nolog
#
# 目的 (kimi M-2/M-3, 2026-10-26):
#   `u_tcp_tx/u_fifo_* -> u_tcb/*` 是 0x2F/0x30 的真正最差族, 但 top-10 会被
#   manager 链盖住. 本脚本把 4 个 TCB 族 + manager 3 条路径的 slack/src/dst/lvl
#   逐条打印, 并给 `P11_STA_TCB_GATE = PASS/FAIL` (阈值 = P11_STA_MIN_NS, 默认 0).
#   build_p7b_ku5p.tcl 的 post-route 门复用同一组 pattern (见 P11_STA_TCB_GATE).
#
# 输出锚点 (示例):
#   P11_STA_TCB_A = <slack>
#   P11_STA_TCB_A_SRC = ...
#   P11_STA_TCB_A_DST = ...
#   P11_STA_TCB_A_LVL = ...
#   P11_STA_TCB_MIN = ...
#   P11_STA_TCB_GATE = PASS|FAIL
#=============================================================================
if {![info exists ::env(P11_STA_DCP)] || $::env(P11_STA_DCP) eq ""} {
    puts "P11_STA_DCP_MISSING"
    exit 2
}
set dcp $::env(P11_STA_DCP)
set minns 0.0
if {[info exists ::env(P11_STA_MIN_NS)] && $::env(P11_STA_MIN_NS) ne ""} {
    set minns [expr {double($::env(P11_STA_MIN_NS))}]
}
puts "P11_STA_DCP = $dcp"
puts "P11_STA_MIN_NS = $minns"
open_checkpoint $dcp

set gwns [get_property SLACK [get_timing_paths -delay_type max]]
puts "P11_STA_GLOBAL_WNS = $gwns"

# ⭐ 2026-10-26 review finding: 0x32 的全局 WNS 宿主是 **stack2** 的
#   `u_tcp_tx2/u_fifo_b/rptr_reg[0] -> u_tcb2/rcv_wnd_r_reg[9][0]` (+0.019 ns),
#   原 A–F 只覆盖 stack1 ⇒ 定向门对真实最差族是盲的. 这里加 A2–F2 + G2
#   (G2 = stack2 的 u_fifo_b/rptr -> rcv_wnd, 即 0x32 全局 WNS 宿主).
set fams [list \
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
    G2 {u_tcp_tx2/u_fifo_b/rptr_reg\[.*\]/C} {u_tcb2/rcv_wnd_r_reg\[.*\]/CE} \
    MGR_REL {u_app_ctrl/c_rcv_nxt_reg\[.*\]/C} {u_win_pool/.*/D} \
    MGR_UP0 {u_slow_cfg/ev_up_reg/C} {u_win_pool/.*/D} \
    MGR_UP1 {u_slow_cfg2/ev_up_reg/C} {u_win_pool/.*/D}]

set tcb_min 999.0
set tcb_na  0
foreach {tag fpat tpat} $fams {
    set fp [get_pins -hier -quiet -regexp $fpat]
    set tp [get_pins -hier -quiet -regexp $tpat]
    if {[llength $fp] > 0 && [llength $tp] > 0} {
        set path [get_timing_paths -from $fp -to $tp -max_paths 1 -delay_type max]
        if {[llength $path] > 0} {
            set sl [get_property SLACK [lindex $path 0]]
            puts "P11_STA_${tag} = $sl"
            puts "P11_STA_${tag}_SRC = [get_property STARTPOINT_PIN [lindex $path 0]]"
            puts "P11_STA_${tag}_DST = [get_property ENDPOINT_PIN [lindex $path 0]]"
            puts "P11_STA_${tag}_LVL = [get_property LOGIC_LEVELS [lindex $path 0]]"
            if {[lsearch -exact {A B C D E F A2 B2 C2 D2 E2 F2 G2} $tag] >= 0} {
                if {$sl < $tcb_min} { set tcb_min $sl }
            }
        } else {
            puts "P11_STA_${tag} = NA (no path)"
            if {[lsearch -exact {A B C D E F A2 B2 C2 D2 E2 F2 G2} $tag] >= 0} { set tcb_na 1 }
        }
    } else {
        puts "P11_STA_${tag} = NA (pins from=[llength $fp] to=[llength $tp])"
        if {[lsearch -exact {A B C D E F A2 B2 C2 D2 E2 F2 G2} $tag] >= 0} { set tcb_na 1 }
    }
}
puts "P11_STA_TCB_MIN = $tcb_min"
if {$tcb_na} {
    puts "P11_STA_TCB_GATE = FAIL (pins/path missing)"
    exit 1
}
if {$tcb_min < $minns} {
    puts "P11_STA_TCB_GATE = FAIL (min=$tcb_min < $minns)"
    exit 1
}
puts "P11_STA_TCB_GATE = PASS"
exit 0
