# P11 build 0x2D -- READ-ONLY diagnosis #2: trace what u_snap_p7bdp/tx_p0_frames_r_reg[0]
# is and where hold_b_reg[1248]/D is actually driven from.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp"
set OUT "$here/SNAP_TOP5_DIAG2_0x2D.txt"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 build 0x2D F-21 gate diag #2 (synth_1, READ-ONLY)"

proc show_cell {fh c} {
    set nm [get_property NAME $c]
    set rf [get_property REF_NAME $c]
    puts $fh "CELL $nm REF=$rf"
    set qs [get_pins -quiet -of_objects $c -filter {DIRECTION == OUT}]
    foreach q $qs {
        puts $fh "  OUTPIN [get_property NAME $q]"
        set nets [get_nets -quiet -of_objects $q]
        foreach n $nets {
            set lp [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
            puts $fh "    NET [get_property NAME $n] loads=[llength $lp]"
            foreach l $lp { puts $fh "      LOAD [get_property NAME $l]" }
        }
    }
    set ds [get_pins -quiet -of_objects $c -filter {DIRECTION == IN}]
    foreach d $ds {
        set nets [get_nets -quiet -of_objects $d]
        foreach n $nets {
            set drv [get_pins -quiet -of_objects $n -filter {DIRECTION == OUT}]
            foreach dp $drv { puts $fh "  INPIN [get_property NAME $d] <- DRIVER [get_property NAME $dp]" }
        }
    }
}

puts $fh "\n## A. the mystery cell inside u_snap_p7bdp"
set c [get_cells -hier -quiet -filter "NAME == u_snap_p7bdp/tx_p0_frames_r_reg\[0\]"]
puts $fh "found=[llength $c]"
if {[llength $c]} { show_cell $fh $c }

puts $fh "\n## B. hold_b_reg[1248] cell + D-pin driver (with -hier)"
set hb [get_cells -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[1248\]"]
puts $fh "hold_b1248_cells=[llength $hb]"
if {[llength $hb]} { show_cell $fh $hb }
set dp [get_pins -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[1248\]/D"]
puts $fh "hold_b1248_D_pins=[llength $dp]"
if {[llength $dp]} {
    set n [get_nets -quiet -of_objects $dp]
    foreach nn $n {
        puts $fh "  D_NET [get_property NAME $nn]"
        set drv [get_pins -quiet -of_objects $nn -filter {DIRECTION == OUT}]
        foreach d $drv {
            puts $fh "    D_DRIVER [get_property NAME $d]"
            set dc [get_cells -quiet -of_objects $d]
            puts $fh "    D_DRIVER_CELL [get_property NAME $dc] REF=[get_property REF_NAME $dc]"
        }
    }
}

puts $fh "\n## C. all FDCE cells named *tx_p0_frames_r_reg* inside u_snap_p7bdp"
set tc [get_cells -hier -quiet -filter "NAME =~ u_snap_p7bdp/*tx_p0_frames_r_reg*"]
puts $fh "cells=[llength $tc]"
foreach cc $tc { puts $fh "  [get_property NAME $cc] REF=[get_property REF_NAME $cc]" }

puts $fh "\n## D. hold_b_reg[1248..1279] D-driver sample (bits 1248..1255)"
for {set b 1248} {$b <= 1255} {incr b} {
    set d [get_pins -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[$b\]/D"]
    set s "bit=$b pins=[llength $d]"
    if {[llength $d]} {
        set n [get_nets -quiet -of_objects $d]
        foreach nn $n {
            set drv [get_pins -quiet -of_objects $nn -filter {DIRECTION == OUT}]
            foreach dd $drv { append s " driver=[get_property NAME $dd]" }
        }
    }
    puts $fh $s
}

puts $fh "\n## E. top-level tx_p0_frames_r_reg[0] and the full tx_p0_frames_r_reg family"
set top [get_pins -quiet -filter "NAME == tx_p0_frames_r_reg\[0\]/Q"]
puts $fh "top_Q=[llength $top]"
set fam [get_cells -hier -quiet -filter "NAME =~ tx_p0_frames_r_reg*"]
puts $fh "family_cells=[llength $fam]"
foreach cc [lrange $fam 0 9] { puts $fh "  [get_property NAME $cc] REF=[get_property REF_NAME $cc]" }
close $fh
puts "P11BUILD0x2D-DIAG2 done -> $OUT"
exit
