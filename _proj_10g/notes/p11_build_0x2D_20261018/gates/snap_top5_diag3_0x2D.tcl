# P11 build 0x2D -- READ-ONLY diagnosis #3: prove the load is a hierarchical net pin
# (alias) and enumerate the true leaf loads of the Q net.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp"
set OUT "$here/SNAP_TOP5_DIAG3_0x2D.txt"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 build 0x2D F-21 gate diag #3 (synth_1, READ-ONLY)"

set q [get_pins -quiet -filter "NAME == tx_p0_frames_r_reg\[0\]/Q"]
set nets [get_nets -quiet -of_objects $q]
puts $fh "Q nets=[llength $nets]"
foreach n $nets {
    puts $fh "NET [get_property NAME $n]"
    set all [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
    puts $fh "  IN pins (default)=[llength $all]"
    foreach p $all {
        puts $fh "    [get_property NAME $p]  TYPE=[get_property TYPE $p] IS_LEAF=[get_property IS_LEAF $p] DIR=[get_property DIRECTION $p]"
    }
    set leaf [get_pins -quiet -leaf -of_objects $n]
    puts $fh "  LEAF pins=[llength $leaf]"
    foreach p $leaf {
        puts $fh "    [get_property NAME $p]  TYPE=[get_property TYPE $p] DIR=[get_property DIRECTION $p]"
    }
    # nets crossing into the module: list all nets with the same base name
}
puts $fh "\n## same-named hierarchical pins/nets:"
foreach pn {u_snap_p7bdp/tx_p0_frames_r_reg\[0\]} {
    set p [get_pins -hier -quiet -filter "NAME == $pn"]
    puts $fh "PIN $pn found=[llength $p]"
    if {[llength $p]} {
        puts $fh "  TYPE=[get_property TYPE $p] IS_LEAF=[get_property IS_LEAF $p] DIR=[get_property DIRECTION $p]"
    }
    set n [get_nets -hier -quiet -filter "NAME == $pn"]
    puts $fh "NET $pn found=[llength $n]"
}
puts $fh "\n## hold_b_reg[1248]/D net back-trace to a leaf driver"
set d [get_pins -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[1248\]/D"]
set dn [get_nets -quiet -of_objects $d]
foreach n $dn {
    puts $fh "D_NET [get_property NAME $n]"
    set drv [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
    foreach p $drv {
        puts $fh "  DRIVER [get_property NAME $p] TYPE=[get_property TYPE $p] IS_LEAF=[get_property IS_LEAF $p]"
    }
    # is this net identical to the top Q net? compare object identity via list
    set same 0
    foreach qn $nets { if {[get_property NAME $qn] eq [get_property NAME $n]} { set same 1 } }
    puts $fh "  same_name_as_top_Q_net=$same"
}
close $fh
puts "P11BUILD0x2D-DIAG3 done -> $OUT"
exit
