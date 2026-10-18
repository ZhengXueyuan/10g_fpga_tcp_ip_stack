# P11 F-21: negative control for the post-synth structure gate.
# Opens the 0x2C build's SYNTH checkpoint (the pre-fix netlist) and runs the
# exact checks that board/build_p7b_ku5p.tcl now performs.  Expected result:
#   slots 39..43 = 0 registers, tx_p0_frames_r_reg[0]/Q -> snap_din (hold_b=0)
# i.e. the gate has teeth.  This is a READ-ONLY checkpoint open (no build).
set root [file normalize [file join [file dirname [file normalize [info script]]] ".." ".." ".." ".."]]
set dcp  [file join $root "vivado_prj" "p7b_ku5p_prj.runs" "synth_1" "wrapper_p4.dcp"]
set out  [file join [file dirname [file normalize [info script]]] "SNAP_TOP5_PROBE_0x2C.txt"]
puts "SNAP_TOP5_PROBE dcp=$dcp exists=[file exists $dcp]"
open_checkpoint $dcp
set fh [open $out w]
for {set s 39} {$s <= 43} {incr s} {
    set lo [expr {$s * 32}]
    set hi [expr {$s * 32 + 31}]
    set nc 0
    for {set b $lo} {$b <= $hi} {incr b} {
        if {[llength [get_cells -hier -quiet -filter "NAME == u_snap_p7bdp/hold_b_reg\[$b\]"]] > 0} { incr nc }
    }
    puts $fh "slot=$s bits=$lo..$hi cells=$nc"
}
set f_pin [get_pins -quiet -filter "NAME == tx_p0_frames_r_reg\[0\]/Q"]
puts $fh "tx_p0_frames_r_reg\[0\]/Q pins=[llength $f_pin]"
set f_nets [get_nets -quiet -of_objects $f_pin]
set f_loads {}
foreach n $f_nets { set f_loads [concat $f_loads [get_pins -quiet -of_objects $n -filter {DIRECTION == IN}]] }
set f_hb 0; set f_sd 0
foreach l $f_loads {
    set ln [get_property NAME $l]
    if {[string match "*u_snap_p7bdp/hold_b_reg*" $ln]} { incr f_hb }
    if {[string match "*u_pcie_regs/snap_din*" $ln]}    { incr f_sd }
    if {[llength $f_loads] <= 8} { puts $fh "  LOAD $ln" }
}
puts $fh "LOADCOUNT hold_b=$f_hb snap_din=$f_sd (0x2C expected: hold_b=0 snap_din>=1)"
close $fh
close_design
exit
