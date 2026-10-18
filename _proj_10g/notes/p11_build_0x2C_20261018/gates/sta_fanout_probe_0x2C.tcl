# fanout probe: are W83/W84/W87 sources sampled by the axi-domain snapshot array
# directly, instead of going through u_snap_p7bdp/hold_b ?
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
open_checkpoint "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set fh [open "$here/FANOUT_PROBE_0x2C.txt" w]
proc loads_of {fh tag cellpat} {
    set cs [get_cells -hier -quiet -filter "NAME =~ *$cellpat*"]
    puts $fh "\n# $tag  cells=[llength $cs]"
    if {![llength $cs]} { return }
    set c [lindex $cs 0]
    set nm [get_property NAME $c]
    set pins [get_pins -quiet -of_objects $c -filter {DIRECTION == OUT}]
    puts $fh "  first_cell=$nm  out_pins=[llength $pins]"
    foreach pn $pins {
        set nets [get_nets -quiet -of_objects $pn]
        foreach n $nets {
            set ld [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]
            puts $fh "    pin=[get_property NAME $pn] net=[get_property NAME $n] loads=[llength $ld]"
            set k 0
            foreach l $ld {
                if {$k < 12} { puts $fh "      LOAD [get_property NAME $l]"; incr k }
            }
            set sn 0; set hb 0; set other 0
            foreach l $ld {
                set ln [get_property NAME $l]
                if {[string match "*snap_words_r_reg*" $ln]} { incr sn }
                if {[string match "*u_snap_p7bdp/hold_b_reg*" $ln]} { incr hb }
                if {[string match "*u_snap_p7bdp*" $ln]} { }
            }
            puts $fh "    LOADCOUNT snap_words_r=$sn hold_b=$hb"
        }
    }
}
loads_of $fh "tx_p0_frames_r_reg" "tx_p0_frames_r_reg"
loads_of $fh "tx_p1_frames_r_reg" "tx_p1_frames_r_reg"
loads_of $fh "maccnt_ch0tx/dst_val_reg" "u_maccnt_ch0tx/dst_val_reg"
# snapshot word 87 (bits 2784..2815) cells
set n87 0; set n86 0; set n85 0; set n84 0; set n83 0
foreach c [get_cells -hier -quiet -filter "NAME =~ *snap_words_r_reg*"] {
    set nm [get_property NAME $c]
    if {[regexp {snap_words_r_reg\[(\d+)\]} $nm -> i]} {
        if {$i >= 2784 && $i <= 2815} { incr n87 }
        if {$i >= 2752 && $i <= 2783} { incr n86 }
        if {$i >= 2720 && $i <= 2751} { incr n85 }
        if {$i >= 2688 && $i <= 2719} { incr n84 }
        if {$i >= 2656 && $i <= 2687} { incr n83 }
    }
}
puts $fh "\nsnap_words_r word83..87 bit counts: W83=$n83 W84=$n84 W85=$n85 W86=$n86 W87=$n87 (32 = full)"
# clock of the snapshot array
set sw [get_cells -hier -quiet -filter "NAME =~ *snap_words_r_reg*"]
if {[llength $sw]} {
    set ck [get_pins -quiet -of_objects [lindex $sw 0] -filter {REF_PIN_NAME == CLK}]
    foreach pn $ck {
        set nn [get_nets -quiet -of_objects $pn]
        foreach n $nn { puts $fh "snap_words_r CLK net = [get_property NAME $n]" }
    }
}
close $fh
exit
