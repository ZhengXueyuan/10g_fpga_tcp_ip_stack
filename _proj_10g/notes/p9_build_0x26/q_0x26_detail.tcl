# q_0x26_detail.tcl - RFC cone detail: worst path INTO the three judge latches
#   (acc_l / ackresp_l / w6a_ok_l) + dup_l, full report (logic/route split, clock skew).
#   usage: vivado -mode batch -nojournal -nolog -source q_0x26_detail.tcl -tclargs <dcp> <outdir>
set dcp [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
open_checkpoint $dcp
foreach {tag pin} {accl u_tcp_rx/acc_l_reg/D ackresp u_tcp_rx/ackresp_l_reg/D w6a u_tcp_rx/w6a_ok_l_reg/D dup u_tcp_rx/dup_l_reg/D} {
  set p [get_pins -quiet $pin]
  puts "D $tag pin=$pin found=[llength $p]"
  if {[llength $p] > 0} {
    catch {report_timing -to $p -delay_type max -max_paths 1 -sort_by slack -file $out/$tag.rpt}
    set tp [get_timing_paths -to $p -delay_type max -max_paths 1 -sort_by slack -quiet]
    if {[llength $tp] > 0} {
      set t [lindex $tp 0]
      puts "D $tag slack=[get_property SLACK $t] lvl=[get_property LOGIC_LEVELS $t] sp=[get_property STARTPOINT_PIN $t] ep=[get_property ENDPOINT_PIN $t]"
      puts "D $tag datapath_delay=[get_property DATAPATH_DELAY $t] logic_delay=[get_property DATAPATH_LOGIC_DELAY $t] route_delay=[get_property DATAPATH_NET_DELAY $t] clk_skew=[get_property CLOCK_PATH_SKEW $t]"
    } else { puts "D $tag NOPATH" }
  }
}
puts "D_DONE"
