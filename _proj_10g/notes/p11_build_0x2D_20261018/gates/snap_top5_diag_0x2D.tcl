# P11 build 0x2D -- READ-ONLY diagnosis of the F-21 post-synth gate failure.
# Opens the synth checkpoint only; never runs implementation, never touches sources.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp"
set OUT "$here/SNAP_TOP5_DIAG_0x2D.txt"
puts "P11BUILD0x2D-DIAG open $DCP"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 build 0x2D: F-21 gate failure diagnosis (synth_1 checkpoint, READ-ONLY)"
puts $fh "# dcp = $DCP"
puts $fh "# time = [clock format [clock seconds]]"

proc loads_of_pin {fh tag pin} {
    set nets [get_nets -quiet -of_objects $pin]
    puts $fh "$tag nets=[llength $nets]"
    foreach n $nets {
        set lp [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
        puts $fh "  NET [get_property NAME $n] loads=[llength $lp]"
        foreach l $lp { puts $fh "    LOAD [get_property NAME $l]" }
    }
}

puts $fh "\n## 1. exact pin tx_p0_frames_r_reg\[0\]/Q"
set p [get_pins -quiet -filter "NAME == tx_p0_frames_r_reg\[0\]/Q"]
puts $fh "pins_found=[llength $p]"
if {[llength $p]} { loads_of_pin $fh "Q" $p }

puts $fh "\n## 2. all cells matching *tx_p0_frames_r_reg\[0\]* (replication candidates)"
set cells [get_cells -hier -quiet -filter "NAME =~ *tx_p0_frames_r_reg\[0\]*"]
puts $fh "cells=[llength $cells]"
foreach c $cells {
    puts $fh "  CELL [get_property NAME $c] REF=[get_property REF_NAME $c]"
    set q [get_pins -quiet -of_objects $c -filter {NAME =~ */Q}]
    foreach qq $q { loads_of_pin $fh "   Q([get_property NAME $qq])" $qq }
}

puts $fh "\n## 3. driver chain into u_snap_p7bdp/hold_b_reg\[1248\]/D"
set d [get_pins -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[1248\]/D"]
puts $fh "D pins_found=[llength $d]"
if {[llength $d]} {
    set nets [get_nets -quiet -of_objects $d]
    foreach n $nets {
        puts $fh "  NET_FEEDING_D [get_property NAME $n]"
        set drv [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
        foreach dp $drv {
            puts $fh "    DRIVER_PIN [get_property NAME $dp]"
            set dc [get_cells -quiet -of_objects $dp]
            puts $fh "    DRIVER_CELL [get_property NAME $dc] REF=[get_property REF_NAME $dc]"
        }
    }
}

puts $fh "\n## 4. hold_b_reg[1248..1407] count (recheck)"
set hb [get_cells -hier -quiet -filter "NAME =~ *u_snap_p7bdp/hold_b_reg*"]
puts $fh "all_hold_b=[llength $hb]"
foreach s {39 40 41 42 43} {
    set lo [expr {$s*32}]; set hi [expr {$s*32+31}]; set n 0
    foreach c $hb {
        set nm [get_property NAME $c]
        if {[regexp {hold_b_reg\[(\d+)\]} $nm -> idx]} {
            if {$idx >= $lo && $idx <= $hi} { incr n }
        }
    }
    puts $fh "  slot=$s bits=$lo..$hi cells=$n"
}

puts $fh "\n## 5. any direct clock-domain path left to u_pcie_regs/snap_din from tx_p0_frames_r*"
set sd [get_cells -hier -quiet -filter "NAME =~ *u_pcie_regs/snap_din*"]
puts $fh "snap_din_cells=[llength $sd]"
set tf [get_cells -hier -quiet -filter "NAME =~ *tx_p0_frames_r_reg*"]
puts $fh "tx_p0_frames_r_cells=[llength $tf]"
set p2 {}
catch { set p2 [get_timing_paths -from $tf -to $sd -delay_type max -max_paths 5 -sort_by slack] }
puts $fh "paths tx_p0_frames_r* -> snap_din* = [llength $p2]"
foreach pp $p2 {
    puts $fh "  PATH slack=[get_property SLACK $pp] [get_property STARTPOINT_PIN $pp] -> [get_property ENDPOINT_PIN $pp]"
}
close $fh
puts "P11BUILD0x2D-DIAG done -> $OUT"
exit
