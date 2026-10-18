# P11 build 0x2D -- READ-ONLY diagnosis #4: D-driver of bit0 of each slot 39..43.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp"
set OUT "$here/SNAP_TOP5_DIAG4_0x2D.txt"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 build 0x2D F-21 gate diag #4 (synth_1, READ-ONLY): slot bit0 D-drivers"
foreach b {1248 1280 1312 1344 1376} {
    set s [expr {$b / 32}]
    set d [get_pins -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[$b\]/D"]
    if {![llength $d]} { puts $fh "bit=$b slot=$s NO_D_PIN"; continue }
    set n [get_nets -quiet -of_objects $d]
    set line "bit=$b slot=$s net=[get_property NAME $n]"
    set drv [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
    foreach p $drv {
        set c [get_cells -quiet -of_objects $p]
        append line " driver=[get_property NAME $p] cell=[get_property NAME $c] ref=[get_property REF_NAME $c]"
    }
    puts $fh $line
}
close $fh
puts "P11BUILD0x2D-DIAG4 done -> $OUT"
exit
