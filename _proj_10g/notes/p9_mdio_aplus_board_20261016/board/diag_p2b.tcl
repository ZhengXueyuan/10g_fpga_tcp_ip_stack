# diag_p2b.tcl -- clean frame-duration sample for the A+ variant (P2b).
# run2 of probe_mdio_aplus.tcl showed that a "commit start -> poll done_sticky" loop
# can read the PREVIOUS transaction's done before the new start has propagated
# (JTAG->fabric update latency jitters; observed ~10 ms in diag C, >=58 ms in run2 P2).
# This run uses the busy-first idiom: wait for busy=1 (the transaction really started),
# THEN wait for done=1, and reports both timestamps + raw words.
set here [file normalize [file dirname [info script]]]
set bit  [lindex $argv 0]
if {$bit eq ""} { error "usage: diag_p2b.tcl <bit path>" }
set ltx [file rootname $bit].ltx
open_hw_manager
connect_hw_server -url 192.168.0.38:3121
current_hw_target [lindex [get_hw_targets] 0]
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev
set vio [lindex [get_hw_vios -of_objects $dev] 0]
proc findprobe {vio names} {
    set all [get_hw_probes -of_objects $vio]
    foreach n $names { foreach p $all { if {$p eq $n} { return $p } } }
    return ""
}
set P_START  [findprobe $vio {vio_start probe_out0}]
set P_PHYAD  [findprobe $vio {vio_phyad probe_out2}]
set P_REGAD  [findprobe $vio {vio_regad probe_out3}]
set P_STATUS [findprobe $vio {vio_probe_in probe_in0}]
puts "PROBES start=$P_START phyad=$P_PHYAD regad=$P_REGAD status=$P_STATUS"
proc vset {vio p val} {
    set w 1
    catch {set w [get_property WIDTH $p]}
    set n [expr {int(ceil($w / 4.0))}]
    set s [format "%0${n}X" [expr {$val & ((1 << $w) - 1)}]]
    set_property OUTPUT_VALUE $s $p
    commit_hw_vio $vio
}
proc vget {vio p} {
    refresh_hw_vio $vio
    set s [get_property INPUT_VALUE $p]
    set ::last_raw $s
    return [expr "0x$s"]
}
proc show {tag v} {
    puts [format "P2B %-18s %s %s  (ssl=%d pbad=%d)" $tag [clock milliseconds] $::last_raw \
          [expr {($v >> 21) & 1}] [expr {($v >> 20) & 1}]]
}
vset $vio $P_PHYAD 1
vset $vio $P_REGAD 2

for {set round 1} {$round <= 3} {incr round} {
    # --- clean pre-state: an accepted start, then wait for it to finish ---
    vset $vio $P_START 0
    vset $vio $P_START 1
    set g0 [clock milliseconds]
    set ok 0
    for {set i 0} {$i < 1500} {incr i} {
        set v [vget $vio $P_STATUS]
        if {($v >> 17) & 1} { set ok 1; break }
        after 10
    }
    show "R${round}_PREBUSY" $v
    for {set i 0} {$i < 1500} {incr i} {
        set v [vget $vio $P_STATUS]
        if {($v >> 16) & 1} { break }
        after 10
    }
    show "R${round}_PREDONE" $v
    puts "P2B R${round}_PRE busy_seen=$ok pre_elapsed_ms=[expr {[clock milliseconds]-$g0}]"

    # --- measured transaction: busy-first idiom ---
    vset $vio $P_START 0
    after 20
    set t0 [clock milliseconds]
    vset $vio $P_START 1
    set t1 [clock milliseconds]
    set tbusy ""
    for {set i 0} {$i < 1500} {incr i} {
        set vb [vget $vio $P_STATUS]
        if {($vb >> 17) & 1} { set tbusy [clock milliseconds]; break }
        after 10
    }
    show "R${round}_BUSY" $vb
    set tdone ""
    for {set i 0} {$i < 1500} {incr i} {
        set vd [vget $vio $P_STATUS]
        if {($vd >> 16) & 1} { set tdone [clock milliseconds]; break }
        after 10
    }
    show "R${round}_DONE" $vd
    puts "P2B R${round}_TIMES t0=$t0 t1=$t1 tbusy=$tbusy tdone=$tdone \
commit_to_busy_ms=[expr {$tbusy-$t0}] busy_to_done_ms=[expr {$tdone-$tbusy}] \
commit_to_done_ms=[expr {$tdone-$t0}] rd=[format %04X [expr {$vd & 0xFFFF}]]"
}
puts "P2B_DONE"
disconnect_hw_server
