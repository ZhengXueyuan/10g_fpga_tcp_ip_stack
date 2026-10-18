# quick probe: snapshot bundle bits and W83..W87 sources
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
open_checkpoint "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set fh [open "$here/SNAP_PROBE_0x2C.txt" w]
set hb [get_cells -hier -quiet -filter "NAME =~ *u_snap_p7bdp/hold_b_reg*"]
set mx -1
foreach c $hb { set nm [get_property NAME $c]; if {[regexp {hold_b_reg\[(\d+)\]$} $nm -> i]} { if {$i > $mx} { set mx $i } } }
puts $fh "hold_b cells = [llength $hb] ; max_index = $mx"
set hist {}
for {set s 0} {$s < 44} {incr s} {
    set lo [expr {$s*32}]; set hi [expr {$s*32+31}]
    set n 0
    foreach c $hb { set nm [get_property NAME $c]; if {[regexp {hold_b_reg\[(\d+)\]$} $nm -> i]} { if {$i >= $lo && $i <= $hi} { incr n } } }
    lappend hist "slot$s=$n"
}
puts $fh [join $hist " "]
foreach pat {tx_p0_frames_r_reg tx_p1_frames_r_reg tx_p0_frames_reg tx_p1_frames_reg ch0_rxcdc_ovf_dp_reg u_maccnt_ch0tx/dst_val_reg u_maccnt_ch0rx/dst_val_reg} {
    set cc [get_cells -hier -quiet -filter "NAME =~ *$pat*"]
    puts $fh [format "%-34s cells=%d" $pat [llength $cc]]
    if {[llength $cc]} { set n 0; foreach c $cc { if {$n<3} { puts $fh "    [get_property NAME $c]"; incr n } } }
}
set sw [get_cells -hier -quiet -filter "NAME =~ *snap_words_r_reg*"]
set smx -1
foreach c $sw { set nm [get_property NAME $c]; if {[regexp {snap_words_r_reg\[(\d+)\]$} $nm -> i]} { if {$i>$smx} {set smx $i} } }
puts $fh "snap_words_r cells=[llength $sw] max_index=$smx"
close $fh
exit
