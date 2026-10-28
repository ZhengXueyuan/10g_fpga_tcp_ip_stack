open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
proc pincell {pat pin} {
  set cs [get_cells -hier -quiet -filter "NAME =~ $pat"]
  foreach c $cs {
    set nm [get_property NAME $c]
    set ps [get_pins -quiet -of_objects $c -filter "REF_PIN_NAME == $pin"]
    if {[llength $ps] > 0} {
      set p [lindex $ps 0]
      set clk_pin [get_pins -quiet -of_objects $c -filter {REF_PIN_NAME == "C"}]
      set clk ""
      if {[llength $clk_pin] > 0} {
        set n [get_nets -quiet -of_objects [lindex $clk_pin 0]]
        if {[llength $n] > 0} { set clk [get_property NAME [lindex $n 0]] }
      }
      puts "$nm pin=$pin net=[get_property NAME [lindex [get_nets -quiet -of_objects $p] 0]] clk=$clk"
    }
  }
}
puts "=== st_hold first/last ==="
pincell "*u_app/st_hold_reg*" "D"
puts "=== st_shadow first few ==="
pincell "*u_app/st_shadow_reg*" "D"
close_design
exit 0
