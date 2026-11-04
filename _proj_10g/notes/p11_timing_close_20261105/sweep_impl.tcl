# sweep_impl.tcl -- P11 DP timing closure P1: same synth netlist, 3 impl strategies.
open_project {D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.xpr}
set arms {{impl_s2 Performance_NetDelay_high} {impl_s3 Congestion_SpreadLogic_high} {impl_s4 Performance_Explore}}
foreach a $arms {
    lassign $a name strat
    if {[llength [get_runs -quiet $name]] == 0} {
        create_run $name -flow {Vivado Implementation 2025} -parent_run synth_1 -strategy $strat
        puts "SWEEP_CREATE $name $strat"
    } else {
        set_property strategy $strat [get_runs $name]
        puts "SWEEP_REUSE $name $strat"
    }
    reset_run $name
}
foreach a $arms {
    lassign $a name strat
    catch {launch_runs $name -to_step write_bitstream -jobs 6} e
    puts "SWEEP_LAUNCH $name $strat err=$e"
}
foreach a $arms {
    lassign $a name strat
    wait_on_run $name
    puts "SWEEP_STATUS $name $strat status=[get_property STATUS [get_runs $name]] progress=[get_property PROGRESS [get_runs $name]]"
}
puts "SWEEP_ALL_DONE"
