# P11 P2 build 0x2C -- directed STA follow-up (read-only on post-route dcp).
# Fixes two probes that returned 0 cells in sta_directed_0x2C.tcl:
#   (a) u_snap_p7bdp/hold_b_reg is two-dimensional (or renamed) -> inspect names;
#   (b) cam_rd_dip is a net/pin, not a cell -> query pins.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set OUT "$here/STA_DIRECTED_FIX_0x2C.txt"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 P2 build 0x2C directed STA follow-up  [clock format [clock seconds]]"

# ---- (a) hold_b_reg name form ----------------------------------------------
set hb_all [get_cells -hier -quiet -filter "NAME =~ *u_snap_p7bdp/hold_b_reg*"]
puts $fh "\n# hold_b_reg total cells = [llength $hb_all]"
set shown 0
foreach c $hb_all {
    if {$shown < 8} { puts $fh "#   sample NAME=[get_property NAME $c]"; incr shown }
}
# select the five new words W83..W87 = p7bdp slots 39..43
set sel2d {}
set sel1d {}
foreach c $hb_all {
    set nm [get_property NAME $c]
    if {[regexp {hold_b_reg\[(\d+)\]\[(\d+)\]} $nm -> w b]} {
        if {$w >= 39 && $w <= 43} { lappend sel2d $c }
    } elseif {[regexp {hold_b_reg\[(\d+)\]} $nm -> idx]} {
        if {$idx >= 1248 && $idx <= 1407} { lappend sel1d $c }
    } elseif {[regexp {hold_b_reg_reg\[(\d+)\]\[(\d+)\]|hold_b_reg_reg\[(\d+)\]} $nm]} {
        # placeholder for a _reg suffix form; selected by caller below if present
    }
}
puts $fh "slot39..43 2-D cells = [llength $sel2d]"
puts $fh "bit1248..1407 1-D cells = [llength $sel1d]"
set sel [concat $sel2d $sel1d]
if {[llength $sel]} {
    set p {}
    catch { set p [get_timing_paths -from $sel -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p]} {
        puts $fh "W83..W87-hold_b FROM slack=[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]"
    } else { puts $fh "W83..W87-hold_b FROM NO_PATH" }
    set p2 {}
    catch { set p2 [get_timing_paths -to $sel -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p2]} {
        puts $fh "W83..W87-hold_b TO   slack=[get_property SLACK $p2]  [get_property STARTPOINT_PIN $p2] -> [get_property ENDPOINT_PIN $p2]"
    } else { puts $fh "W83..W87-hold_b TO NO_PATH" }
} else {
    puts $fh "W83..W87-hold_b SELECTED = 0 (name form not matched; sample above)"
}

# ---- (b) cam_rd_dip -> u_tcp_tx/*csum* via pins ----------------------------
set cp [get_pins -hier -quiet -filter "NAME =~ *cam_rd_dip*"]
puts $fh "\ncam_rd_dip pins = [llength $cp]"
set n 0
foreach p $cp { if {$n < 6} { puts $fh "#   PIN [get_property NAME $p]"; incr n } }
set cs [get_cells -hier -quiet -filter "NAME =~ *u_tcp_tx/*csum*"]
puts $fh "u_tcp_tx/*csum* cells = [llength $cs]"
if {[llength $cp]} {
    set p {}
    catch { set p [get_timing_paths -from $cp -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p]} { puts $fh "cam_rd_dip(pin) FROM slack=[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]" } else { puts $fh "cam_rd_dip(pin) FROM NO_PATH" }
    set p2 {}
    catch { set p2 [get_timing_paths -from $cp -to $cs -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p2]} { puts $fh "cam_rd_dip(pin) -> *csum* slack=[get_property SLACK $p2]  [get_property STARTPOINT_PIN $p2] -> [get_property ENDPOINT_PIN $p2]" } else { puts $fh "cam_rd_dip(pin) -> *csum* NO_PATH" }
}
set cn [get_nets -hier -quiet -filter "NAME =~ *cam_rd_dip*"]
puts $fh "cam_rd_dip nets = [llength $cn]"
set k 0
foreach x $cn { if {$k < 4} { puts $fh "#   NET [get_property NAME $x]"; incr k } }

# ---- snapshot array family in top-200 (any cell, not only hold_b) ----------
set topf "$here/TOP200_0x2C_fix.rpt"
report_timing -delay_type max -max_paths 200 -sort_by slack -file $topf
set txt [read [open $topf r]]
puts $fh "\ntop200 occurrences:"
foreach f {u_snap_p7bdp snap_cdc u_hls u_maccnt f_lip ctrl_lip u_rx_merge u_tx_udp_arb u_tx_arb} {
    puts $fh [format "  %-20s %d" $f [regexp -all -- $f $txt]]
}
close $fh
puts "P11BUILD0x2C-STA-FIX done -> $OUT"
exit
