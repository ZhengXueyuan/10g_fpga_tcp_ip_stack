open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
set ns [get_nets -hier -quiet -filter {NAME =~ *core_tx_bytes*}]
puts "core_tx_bytes_nets=[llength $ns]"
foreach n [lrange $ns 0 5] {
  set nm [get_property NAME $n]
  set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  set ld [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]
  puts "NET $nm drv=[llength $drv] loads=[llength $ld]"
  foreach d [lrange $drv 0 2] { puts "   <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
}
close_design
exit 0
