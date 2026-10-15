# query_all_props.tcl -- dump ALL run properties of synth_1 (2025.2)
open_project D:/repo/XCKU5PMini/_proj_mdio/pj_mdio_divbad/mdio_prj.xpr
set r [get_runs synth_1]
set props [report_property -all $r -return_string]
set n 0
foreach line [split $props "\n"] {
    puts "PROP: $line"
    incr n
}
puts "PROP_COUNT=$n"
puts "QUERY_DONE"
