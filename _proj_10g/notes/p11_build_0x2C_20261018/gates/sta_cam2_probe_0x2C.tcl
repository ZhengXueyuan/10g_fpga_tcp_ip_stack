# cam_rd_dip loads + timing through the nets
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
open_checkpoint "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set fh [open "$here/CAM2_PROBE_0x2C.txt" w]
set nets [get_nets -hier -quiet -filter "NAME =~ *cam_rd_dip*"]
puts $fh "cam_rd_dip nets = [llength $nets]"
set tot 0; set intx 0; set other {}
foreach n $nets {
    set ld [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
    incr tot [llength $ld]
    foreach l $ld {
        set ln [get_property NAME $l]
        if {[string match "*u_tcp_tx/*" $ln]} { incr intx } else { lappend other $ln }
    }
}
puts $fh "total loads = $tot ; loads under u_tcp_tx = $intx"
set k 0
foreach o $other { if {$k<10} { puts $fh "  OTHER_LOAD $o"; incr k } }
set p {}
catch { set p [get_timing_paths -through $nets -delay_type max -max_paths 1 -sort_by slack] }
if {[llength $p]} { puts $fh "through-nets worst slack=[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]" } else { puts $fh "through-nets NO_PATH" }
set cs [get_cells -hier -quiet -filter "NAME =~ *u_tcp_tx/*csum*"]
set p2 {}
catch { set p2 [get_timing_paths -to $cs -delay_type max -max_paths 1 -sort_by slack] }
if {[llength $p2]} { puts $fh "worst INTO u_tcp_tx/*csum* slack=[get_property SLACK $p2]  [get_property STARTPOINT_PIN $p2] -> [get_property ENDPOINT_PIN $p2]" } else { puts $fh "csum INTO NO_PATH" }
close $fh
exit
