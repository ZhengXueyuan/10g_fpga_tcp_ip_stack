# cam_rd_dip -> u_tcp_tx/*csum* via nets (cam_rd_dip is a wire, not a cell)
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
open_checkpoint "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set fh [open "$here/CAM_PROBE_0x2C.txt" w]
set nets [get_nets -hier -quiet -filter "NAME =~ *cam_rd_dip*"]
puts $fh "cam_rd_dip nets = [llength $nets]"
set drivers {}
foreach n $nets {
    set dp [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
    foreach d $dp { lappend drivers $d }
}
set drivers [lsort -unique $drivers]
puts $fh "driver pins = [llength $drivers]"
set k 0
foreach d $drivers { if {$k < 8} { puts $fh "  DRV [get_property NAME $d]"; incr k } }
set cs [get_cells -hier -quiet -filter "NAME =~ *u_tcp_tx/*csum*"]
puts $fh "u_tcp_tx/*csum* cells = [llength $cs]"
if {[llength $drivers]} {
    set p {}
    catch { set p [get_timing_paths -from $drivers -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p]} { puts $fh "cam drivers FROM slack=[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]" } else { puts $fh "cam drivers FROM NO_PATH" }
    set p2 {}
    catch { set p2 [get_timing_paths -from $drivers -to $cs -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p2]} { puts $fh "cam drivers -> csum slack=[get_property SLACK $p2]  [get_property STARTPOINT_PIN $p2] -> [get_property ENDPOINT_PIN $p2]" } else { puts $fh "cam drivers -> csum NO_PATH" }
}
close $fh
exit
