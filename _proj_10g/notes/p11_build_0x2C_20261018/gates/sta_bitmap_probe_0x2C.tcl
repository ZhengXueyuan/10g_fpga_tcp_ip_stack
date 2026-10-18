# map W83..W87 bits: which snap_din index does each source reach?
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
open_checkpoint "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set fh [open "$here/BITMAP_PROBE_0x2C.txt" w]
proc drv_of_pin {fh pinname} {
    set ps [get_pins -quiet $pinname]
    if {![llength $ps]} { puts $fh "  $pinname : NO_PIN"; return }
    set nets [get_nets -quiet -of_objects $ps]
    foreach n $nets {
        set dp [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
        set drv "?"
        if {[llength $dp]} { set drv [get_property NAME [lindex $dp 0]] }
        puts $fh "  $pinname : net=[get_property NAME $n] driver=$drv"
    }
}
puts $fh "# driver of selected u_pcie_regs/snap_din bits"
foreach i {2422 2656 2688 2720 2752 2784} { drv_of_pin $fh "u_pcie_regs/snap_din\[$i\]" }
puts $fh "\n# D-pin drivers of selected snap_words_r bits (pcie domain regs)"
foreach i {2422 2656 2688 2720 2752 2784} {
    set c [get_cells -quiet "u_pcie_regs/snap_words_r_reg\[$i\]"]
    if {![llength $c]} { puts $fh "  snap_words_r_reg[$i] : NO_CELL"; continue }
    set pin [get_pins -quiet -of_objects $c -filter {REF_PIN_NAME == D}]
    foreach pn $pin {
        set nn [get_nets -quiet -of_objects $pn]
        foreach n $nn {
            set dp [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
            set drv "?"
            if {[llength $dp]} { set drv [get_property NAME [lindex $dp 0]] }
            puts $fh "  snap_words_r_reg[$i]/D net=[get_property NAME $n] driver=$drv"
        }
    }
}
close $fh
exit
