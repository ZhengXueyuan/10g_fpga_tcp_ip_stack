open_hw_manager
connect_hw_server -url 192.168.0.38:3121
current_hw_target [lindex [get_hw_targets] 0]
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROBES.FILE {D:/repo/XCKU5PMini/_proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx} $dev
set_property FULL_PROBES.FILE {D:/repo/XCKU5PMini/_proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx} $dev
refresh_hw_device $dev
set vio [lindex [get_hw_vios] 0]
set p [get_hw_probes vio_probe_in -of_objects $vio]
puts "P=$p CLASS=[get_property CLASS $p]"
puts "--- list_property ---"
foreach pr [lsort [list_property $p]] {
    if {[catch {set v [get_property $pr $p]} e]} { puts "  $pr -> ERR $e" } else { puts "  $pr = <$v>" }
}
puts "--- after refresh_hw_vio ---"
catch {refresh_hw_vio $vio} e2
puts "refresh rc=$e2"
set raw [get_property INPUT_VALUE $p]
puts "INPUT_VALUE=<$raw>"
puts "STR_LEN=[string length $raw]"
puts "IS_INT=[string is integer -strict $raw]"
puts "--- also: OUTPUT_VALUE of vio_phyad ---"
set po [get_hw_probes vio_phyad -of_objects $vio]
catch {set_property OUTPUT_VALUE 5 $po}
catch {commit_hw_vio $po}
puts "phyad OUTPUT_VALUE = <[get_property OUTPUT_VALUE $po]>"
disconnect_hw_server
