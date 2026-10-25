# Unit harness for the P11_STA_TCB_GATE block extracted from board/build_p7b_ku5p.tcl.
# This does NOT run Vivado; it stubs get_pins/get_timing_paths/get_property and
# exercises the gate's pass / missing-pin / negative-slack / non-c4 paths.
# Env: BLOCK_FILE, P11_CFG, ROOT_DIR, MISSING_SUBSTR (optional), FORCE_SLACK (optional)
proc sec {s} { puts "SEC $s" }
set P11_CFG $::env(P11_CFG)
set p11_sta_min 0.0
set root_dir $::env(ROOT_DIR)
set project_name "p7b_ku5p_prj"
set top_module "wrapper_p4"
unset -nocomplain ::env(P11_STA_MIN_NS)

set ::last_from ""
set ::last_to ""
set ::force_slack ""
if {[info exists ::env(FORCE_SLACK)] && $::env(FORCE_SLACK) ne ""} {
    set ::force_slack $::env(FORCE_SLACK)
}
set ::missing_substr ""
if {[info exists ::env(MISSING_SUBSTR)] && $::env(MISSING_SUBSTR) ne ""} {
    set ::missing_substr $::env(MISSING_SUBSTR)
}

# Return the pattern itself as the "pin" so get_timing_paths can tell families apart.
proc get_pins {args} {
    set pat [lindex $args end]
    if {$::missing_substr ne "" && [string first $::missing_substr $pat] >= 0} {
        return {}
    }
    return [list $pat]
}
proc get_timing_paths {args} {
    set i [lsearch -exact $args -from]
    if {$i >= 0} { set ::last_from [lindex $args [expr {$i + 1}]] }
    set j [lsearch -exact $args -to]
    if {$j >= 0} { set ::last_to [lindex $args [expr {$j + 1}]] }
    return [list "path"]
}
proc get_property {prop obj} {
    switch -- $prop {
        SLACK {
            if {$::force_slack ne ""} { return $::force_slack }
            # 0x32 measured host: stack2 G2 = b/rptr -> rcv_wnd.  Make that the min.
            if {[string first "u_tcp_tx2/u_fifo_b/rptr_reg" $::last_from] >= 0 &&
                [string first "u_tcb2/rcv_wnd_r_reg" $::last_to] >= 0} {
                return 0.019
            }
            return 0.1
        }
        STARTPOINT_PIN { return $::last_from }
        ENDPOINT_PIN   { return $::last_to }
        LOGIC_LEVELS   { return 16 }
        default        { return "" }
    }
}

source $::env(BLOCK_FILE)
puts "HARNESS_END"
