# P1BUILD0x2B STA follow-up: (a) hold_b FROM path group/slack, (b) family hits in top-200.
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set OUT "$here/STA_FOLLOWUP_0x2B.txt"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P1BUILD0x2B STA follow-up [clock format [clock seconds]]"

set cells [get_cells -hier -quiet -filter "NAME =~ *u_snap_p7bdp/hold_b_reg*"]
puts $fh "# hold_b cells = [llength $cells]"
set p {}
catch { set p [get_timing_paths -from $cells -delay_type max -max_paths 1 -sort_by slack] }
if {[llength $p]} {
    puts $fh "# hold_b FROM: SLACK=<[get_property SLACK $p]> START=<[get_property STARTPOINT_PIN $p]> END=<[get_property ENDPOINT_PIN $p]>"
}
# top-200 worst setup paths whole design, then scan for new ch0 families
set topf "$here/TOP200_0x2B.rpt"
report_timing -delay_type max -max_paths 200 -sort_by slack -file $topf
set txt [read [open $topf r]]
puts $fh "\n# top200 scan for ch0 families (occurrences):"
foreach f {u_snap_p7bdp pcs0_ferr pcs0_bad pcs0_badv pcs0_erv pcs0_vcc pcs0_fifo los1_sr los2_sr los1_evt los2_evt pcs0_ferr_evt pcs0_bad_evt pcs0_erv_evt pcs0_vcc_cyc} {
    puts $fh [format "%-16s %d" $f [regexp -all -- $f $txt]]
}
close $fh
puts "P1BUILD0x2B-STA-FOLLOWUP done -> $OUT"
exit
