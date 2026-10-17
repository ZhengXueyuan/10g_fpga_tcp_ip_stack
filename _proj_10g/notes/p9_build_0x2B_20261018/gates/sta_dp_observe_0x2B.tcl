# P1BUILD0x2B directed STA observation (DESIGN_v5 §10.3 list) -- read-only on routed dcp.
# Run AFTER the build completes (never concurrently with a build).
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set OUT "$here/STA_DP_OBSERVE_0x2B.txt"
puts "P1BUILD0x2B-STA open $DCP"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P1BUILD0x2B directed STA (post-route dcp)  [clock format [clock seconds]]"
puts $fh "# dcp = $DCP"

# --- global + DP-domain (g_hw.clk_out0) worst paths --------------------------
set gp [get_timing_paths -delay_type max -max_paths 1 -sort_by slack]
puts $fh "# GLOBAL worst_setup_slack = [get_property SLACK $gp]"
if {[llength $gp]} {
    puts $fh "# GLOBAL start = [get_property STARTPOINT_PIN $gp]"
    puts $fh "# GLOBAL end   = [get_property ENDPOINT_PIN $gp]"
}
set dp_paths {}
catch {
    set dp_paths [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 10 -sort_by slack]
}
puts $fh "\n# --- DP group (g_hw.clk_out0) top10 by slack ---"
set i 0
foreach p $dp_paths {
    incr i
    puts $fh [format "DP%02d slack=%s  %s -> %s" $i [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}

# --- DESIGN_v5 §10.3 directed families ---------------------------------------
set fams {
  u_snap_p7bdp/hold_b_reg
  pcs0_ferr_sr
  pcs0_bad_sr
  pcs0_badv_sr
  pcs0_errv_sr
  pcs0_erv_sr
  pcs0_vcc_sr
  pcs0_fifo_sr
  los1_sr
  los2_sr
  los1_evt
  los2_evt
  las_prim_cnt
  pcs0_ferr_evt
  pcs0_bad_evt
  pcs0_erv_evt
  pcs0_vcc_cyc
}
puts $fh "\n# --- directed families: worst setup path FROM the family ---"
foreach f $fams {
    set cells [get_cells -hier -quiet -filter "NAME =~ *$f*"]
    if {![llength $cells]} { puts $fh [format "%-24s NO_CELL (0 matches)" $f] ; continue }
    set p {}
    catch { set p [get_timing_paths -from $cells -delay_type max -max_paths 1 -sort_by slack] }
    if {![llength $p]} { puts $fh [format "%-24s NO_PATH (cells=%d)" $f [llength $cells]] ; continue }
    puts $fh [format "%-24s cells=%-4d slack=%s  %s -> %s" $f [llength $cells] [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}

puts $fh "\n# --- directed families: worst setup path INTO the family (sink check) ---"
foreach f $fams {
    set cells [get_cells -hier -quiet -filter "NAME =~ *$f*"]
    if {![llength $cells]} { continue }
    set p {}
    catch { set p [get_timing_paths -to $cells -delay_type max -max_paths 1 -sort_by slack] }
    if {![llength $p]} { puts $fh [format "%-24s NO_PATH_IN (cells=%d)" $f [llength $cells]] ; continue }
    puts $fh [format "%-24s cells=%-4d slack=%s  %s -> %s" $f [llength $cells] [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}
close $fh
puts "P1BUILD0x2B-STA done -> $OUT"
exit
