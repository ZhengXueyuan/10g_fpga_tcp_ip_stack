# query_generic_prop.tcl -- find the correct run property name for synthesis generics (2025.2)
open_project D:/repo/XCKU5PMini/_proj_mdio/pj_mdio_divbad/mdio_prj.xpr
set r [get_runs synth_1]
puts "RUN_OBJ=$r"
set props [report_property -all $r -return_string]
foreach line [split $props "\n"] {
    if {[string match -nocase "*generic*" $line]} {
        puts "PROP_GENERIC: $line"
    }
}
puts "QUERY_DONE"
