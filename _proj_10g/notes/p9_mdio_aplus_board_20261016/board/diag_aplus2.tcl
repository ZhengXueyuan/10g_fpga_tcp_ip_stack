# diag_aplus2.tcl -- RAW-bit diagnostic for the A+ variant arm (P1/P2/P3 re-run).
#
# Why: run1 of probe_mdio_aplus.tcl died in the P3 loop on a Tcl arity bug
# (for-loop missing its "next" argument) and its sdec()/fmt7() LABELS put
# bit20 on "ssl" and bit21 on "pbad" -- the RTL packs {stat_start_lost, param_bad,
# ...} so the RTL says [21]=stat_start_lost, [20]=param_bad.  This script prints
# the RAW 22-bit word plus an explicit bit-by-bit breakdown, and verifies known
# bit positions with togglable signals (force_rst->[18], busy->[17], done->[16]),
# so the label question is settled by measurement, not by convention.
set here [file normalize [file dirname [info script]]]
set bit  [lindex $argv 0]
if {$bit eq ""} { error "usage: diag_aplus2.tcl <bit path>" }
if {![file exists $bit]} { error "bitstream not found: $bit" }
set ltx [file rootname $bit].ltx
puts "BIT $bit"
puts "LTX $ltx"

open_hw_manager
connect_hw_server -url 192.168.0.38:3121
current_hw_target [lindex [get_hw_targets] 0]
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
puts "DEVICE $dev"
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev
set vio [lindex [get_hw_vios -of_objects $dev] 0]
puts "VIO $vio"

proc findprobe {vio names} {
    set all [get_hw_probes -of_objects $vio]
    foreach n $names {
        foreach p $all { if {$p eq $n} { return $p } }
    }
    return ""
}
set P_START  [findprobe $vio {vio_start  probe_out0}]
set P_OUT1   [findprobe $vio {u_vio_n_2 probe_out1}]
set P_PHYAD  [findprobe $vio {vio_phyad  probe_out2}]
set P_REGAD  [findprobe $vio {vio_regad  probe_out3}]
set P_WRDATA [findprobe $vio {vio_wr_data probe_out4}]
set P_STATUS [findprobe $vio {vio_probe_in probe_in0}]
puts "PROBES start=$P_START out1=$P_OUT1 phyad=$P_PHYAD regad=$P_REGAD wr=$P_WRDATA status=$P_STATUS"
foreach p [get_hw_probes -of_objects $vio] {
    puts "PROBEDETAIL $p width=[get_property WIDTH $p]"
}
set WIDTH_CHECK [get_property WIDTH $P_STATUS]
puts "STATUS_WIDTH=$WIDTH_CHECK  (want 22)"

proc vset {vio p val} {
    set w 1
    catch {set w [get_property WIDTH $p]}
    set n [expr {int(ceil($w / 4.0))}]
    set s [format "%0${n}X" [expr {$val & ((1 << $w) - 1)}]]
    set_property OUTPUT_VALUE $s $p
    commit_hw_vio $vio
}
# raw string fetch of the status probe
proc vraw {vio p} {
    refresh_hw_vio $vio
    return [get_property INPUT_VALUE $p]
}
proc vnum {vio p} {
    return [expr "0x[vraw $vio $p]"]
}
proc bits {v} {
    set s ""
    for {set i 21} {$i >= 16} {incr i -1} {
        append s "b$i=[expr {($v >> $i) & 1}] "
    }
    append s [format "rd=%04X" [expr {$v & 0xFFFF}]]
    return $s
}
proc stamp {tag v} {
    puts [format "DIAG %-26s %s  %s" $tag [clock milliseconds] [bits $v]]
}

# ---------------- A: idle raw ----------------
set v [vnum $vio $P_STATUS]
stamp "A_IDLE" $v
puts "A_RAW [vraw $vio $P_STATUS]"

# ---------------- B: force_rst toggle (verifies [18]); P_OUT1 = {force_rst, op} ----------------
vset $vio $P_OUT1 2
after 20
set v [vnum $vio $P_STATUS]
stamp "B_FORCE_RST_1" $v
vset $vio $P_OUT1 0
after 20
set v [vnum $vio $P_STATUS]
stamp "B_FORCE_RST_0" $v

# ---------------- C: single frame, instrumented ----------------
vset $vio $P_START 0
after 20
set v [vnum $vio $P_STATUS]
stamp "C_PRE" $v
set t0 [clock milliseconds]
vset $vio $P_START 1
set t1 [clock milliseconds]
set v [vnum $vio $P_STATUS]
stamp "C_AFTER_START" $v
set t2 [clock milliseconds]
puts "C_TIMES t0=$t0 t1=$t1 t2=$t2 d_commit=[expr {$t1-$t0}] d_read=[expr {$t2-$t1}]"
set tdone ""
for {set i 0} {$i < 400} {incr i} {
    set v [vnum $vio $P_STATUS]
    if {($v >> 16) & 1} { set tdone [clock milliseconds]; break }
    after 10
}
if {$tdone ne ""} {
    stamp "C_DONE" $v
    puts "C_ELAPSED done_at=$tdone elapsed_from_start=[expr {$tdone-$t0}]"
} else {
    puts "C_DONE TIMEOUT"
}

# ---------------- D: trigger test with RAW reads at each step ----------------
# ensure idle
for {set i 0} {$i < 400} {incr i} {
    set v [vnum $vio $P_STATUS]
    if {!(($v >> 17) & 1)} { break }
    after 10
}
vset $vio $P_START 0
after 20
set v [vnum $vio $P_STATUS]
stamp "D_PRE" $v
set d1 [clock milliseconds]
vset $vio $P_START 1
set d2 [clock milliseconds]
vset $vio $P_START 0
set d3 [clock milliseconds]
vset $vio $P_START 1
set d4 [clock milliseconds]
puts "D_COMMITS d1=$d1 d2=$d2 d3=$d3 d4=$d4 d_c2c1=[expr {$d2-$d1}] d_c3c2=[expr {$d3-$d2}] d_c4c3=[expr {$d4-$d3}] span=[expr {$d4-$d1}]"
set v [vnum $vio $P_STATUS]
stamp "D_AFTER_TRIGGER" $v
after 30
set v [vnum $vio $P_STATUS]
stamp "D_AFTER_PLUS30" $v
for {set i 0} {$i < 400} {incr i} {
    set v [vnum $vio $P_STATUS]
    if {($v >> 16) & 1} { break }
    after 10
}
stamp "D_AFTER_DONE" $v

# ---------------- E: clean accepted start should clear the dropped flag ----------------
vset $vio $P_START 0
set e1 [clock milliseconds]
vset $vio $P_START 1
set e2 [clock milliseconds]
after 20
set v [vnum $vio $P_STATUS]
stamp "E_CLEAN_START" $v
puts "E_TIMES e1=$e1 e2=$e2 d=[expr {$e2-$e1}]"
for {set i 0} {$i < 400} {incr i} {
    set v [vnum $vio $P_STATUS]
    if {($v >> 16) & 1} { break }
    after 10
}
stamp "E_DONE" $v
puts "DIAG_DONE"
disconnect_hw_server
