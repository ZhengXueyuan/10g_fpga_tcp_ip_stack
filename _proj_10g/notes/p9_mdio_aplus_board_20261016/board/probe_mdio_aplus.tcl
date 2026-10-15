# probe_mdio_aplus.tcl -- A+ arm (E7/E8 variant: DIV=65537 -> clamped 65536).  RUN2.
#
# Round p9_mdio_aplus_board_20261016.  run1 of this script died in its P3 loop on a
# Tcl arity bug (for-loop missing its "next" argument) and its decode labels put
# bit20 on "ssl" and bit21 on "pbad".  diag_aplus2.tcl (raw-bit run) settled the map
# BY MEASUREMENT on this exact bitstream:
#   bit20 = param_bad        (static 1 on this variant; 0 on the production arm)
#   bit21 = stat_start_lost  (0 -> 1 when a start rises while busy; cleared by the
#                             next ACCEPTED start; verified: diag D sets it, diag E
#                             clears it)
#   bits [19:16] = mdio_i / eth_rstn / busy / done_sticky  (busy=1 and mdio=0 seen
#   mid-frame in diag C, done 0->1 at frame end)
# This run2 prints the RAW 22-bit hex word alongside the decoded columns so the
# evidence does not depend on any label convention.
#
# Expected physics (DIV_SAFE=65536): MDC 762.9 Hz (period 1.31072 ms); one frame =
# 64 MDC periods = 8388608 clk @10ns = 83.886 ms; busy window 83.9 ms >> the
# production 32 us, so a host-driven second start CAN land inside it.
#
# Arms:
#   P1  read param_bad (bit20)                 expect 1 (production arm reads 0)
#   P2  one timed transaction (PHY read 1/r2)  expect rd=001C, elapsed ~tens of ms
#       (its own 3-commit sequence may or may not drop a start -- reported as-is)
#   P3  start=1 / start=0 / start=1: the 2nd rise inside the busy window must set
#       stat_start_lost (bit21); a later clean ACCEPTED start must clear it.
#       Up to 5 attempts (commit jitter can miss the window -- record honestly).
#
# Five JTAG/VIO traps preserved (ltx bound; probe names = net names; commit/refresh
# want the hw_vio CORE; INPUT_VALUE is a hex string; OUTPUT_VALUE zero-padded).

set here [file normalize [file dirname [info script]]]
set bit  [lindex $argv 0]
if {$bit eq ""} { error "usage: probe_mdio_aplus.tcl <bit path>" }
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

if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
    set_property FULL_PROBES.FILE $ltx $dev
    puts "PROBES $ltx"
} else {
    error "no .ltx next to $bit -- VIO probes will not be enumerable"
}
refresh_hw_device $dev

set vio [lindex [get_hw_vios -of_objects $dev] 0]
if {$vio eq ""} { error "no VIO found on $dev -- does the bitstream contain it?" }
puts "VIO $vio"

proc findprobe {vio names} {
    set all [get_hw_probes -of_objects $vio]
    foreach n $names {
        foreach p $all {
            if {$p eq $n} { return $p }
        }
    }
    return ""
}

set P_START  [findprobe $vio {vio_start  probe_out0}]
set P_PHYAD  [findprobe $vio {vio_phyad  probe_out2}]
set P_REGAD  [findprobe $vio {vio_regad  probe_out3}]
set P_WRDATA [findprobe $vio {vio_wr_data probe_out4}]
set P_STATUS [findprobe $vio {vio_probe_in probe_in0}]
puts "PROBES start=$P_START phyad=$P_PHYAD regad=$P_REGAD wr=$P_WRDATA status=$P_STATUS"
foreach {n p} [list start $P_START phyad $P_PHYAD regad $P_REGAD status $P_STATUS] {
    if {$p eq ""} { error "could not resolve VIO probe '$n'" }
}
puts "ALLPROBES [get_hw_probes -of_objects $vio]"

set WIDTH_CHECK "FAIL"
catch {set WIDTH_CHECK [get_property WIDTH $P_STATUS]}
puts "STATUS_WIDTH=$WIDTH_CHECK  (want 22)"

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
    set r "HEX"
    catch {set r [get_property INPUT_VALUE_RADIX $p]}
    switch -- $r {
        HEX     { return [expr "0x$s"] }
        BIN     { return [expr "0b$s"] }
        OCT     { return [expr "0o$s"] }
        default { return [expr {$s}] }
    }
}

# decode with the MEASURED map: [21]=stat_start_lost, [20]=param_bad, [19]=mdio_i,
# [18]=eth_rstn, [17]=busy, [16]=done_sticky
proc sdec {v} {
    return [list [expr {$v & 0xFFFF}] [expr {($v >> 16) & 1}] \
                 [expr {($v >> 17) & 1}] [expr {($v >> 18) & 1}] \
                 [expr {($v >> 19) & 1}] [expr {($v >> 21) & 1}] \
                 [expr {($v >> 20) & 1}]]
}
proc fmt7 {r} {
    lassign $r rd done busy rstn mdio ssl pbad
    return [format "rd=%04X done=%d busy=%d rstn=%d mdio=%d ssl=%d pbad=%d" \
            $rd $done $busy $rstn $mdio $ssl $pbad]
}
proc fmtr {vio r} {
    return [format "%s raw=%s" [fmt7 $r] [vrawstr $vio]]
}
proc vrawstr {vio} { return $::last_raw }

proc wait_done {vio p status_tag} {
    set t0 [clock milliseconds]
    for {set i 0} {$i < 1200} {incr i} {
        set v [vget $vio $p]
        if {($v >> 16) & 1} {
            puts "APLUS_WAIT_DONE $status_tag ok i=$i dt_ms=[expr {[clock milliseconds] - $t0}] $::last_raw"
            return [list $v $i]
        }
        after 10
    }
    puts "APLUS_WAIT_DONE $status_tag TIMEOUT dt_ms=[expr {[clock milliseconds] - $t0}] $::last_raw"
    return [list [vget $vio $p] 1200]
}

proc wait_idle {vio p status_tag} {
    set t0 [clock milliseconds]
    for {set i 0} {$i < 1200} {incr i} {
        set v [vget $vio $p]
        if {!(($v >> 17) & 1)} {
            puts "APLUS_WAIT_IDLE $status_tag ok i=$i dt_ms=[expr {[clock milliseconds] - $t0}] $::last_raw"
            return $v
        }
        after 10
    }
    puts "APLUS_WAIT_IDLE $status_tag TIMEOUT dt_ms=[expr {[clock milliseconds] - $t0}] $::last_raw"
    return [vget $vio $p]
}

vset $vio $P_PHYAD 5
set rb [get_property OUTPUT_VALUE $P_PHYAD]
puts "WRITE_CHECK phyad set to 5, reads back <$rb>"
vset $vio $P_PHYAD 1

# ---------------- P1: param_bad (bit20) on the variant bit ----------------
puts "APLUS_P1_BEGIN"
set v [vget $vio $P_STATUS]
puts "APLUS_P1_IDLE [fmtr $vio [sdec $v]]"
puts "APLUS_P1_PBAD_BIT20 [expr {($v >> 20) & 1}]  (variant expects 1; production arm expects 0)"
puts "APLUS_P1_END"

# ------------- P2: one timed transaction (PHY read phyad=1 reg2) -------------
puts "APLUS_P2_BEGIN"
vset $vio $P_PHYAD 1
vset $vio $P_REGAD 2
set t_c1 [clock milliseconds]
vset $vio $P_START 1
set t_c2 [clock milliseconds]
vset $vio $P_START 0
set t_c3 [clock milliseconds]
puts "APLUS_P2_COMMIT_MS c1=$t_c1 c2=$t_c2 c3=$t_c3 d_c2c1=[expr {$t_c2-$t_c1}] d_c3c2=[expr {$t_c3-$t_c2}]"
set busy_seen 0
set tdone ""
set vd ""
for {set i 0} {$i < 1200} {incr i} {
    set v [vget $vio $P_STATUS]
    if {($v >> 17) & 1} { set busy_seen 1 }
    if {($v >> 16) & 1} { set tdone [clock milliseconds]; set vd $v; break }
    after 10
}
puts "APLUS_P2_BUSY_SEEN $busy_seen"
if {$tdone ne ""} {
    puts "APLUS_P2_DONE_AT_MS $tdone (elapsed_from_start_commit=[expr {$tdone-$t_c1}] elapsed_from_rearm=[expr {$tdone-$t_c3}])"
    puts "APLUS_P2_RESULT [fmtr $vio [sdec $vd]]"
    puts "APLUS_P2_ID rd=[format %04X [expr {$vd & 0xFFFF}]] (expect 001C for phyad=1 PHYID1)"
} else {
    puts "APLUS_P2_RESULT TIMEOUT_NO_DONE"
}
puts "APLUS_P2_END"

# ------------- P3: stat_start_lost trigger inside the busy window -------------
puts "APLUS_P3_BEGIN"
set triggered 0
set attempts 0
for {set k 1} {$k <= 5} {incr k} {
    incr attempts
    wait_idle $vio $P_STATUS "pre_attempt_$k"
    set v [vget $vio $P_STATUS]
    puts "APLUS_P3_PRE k=$k [fmtr $vio [sdec $v]]"
    vset $vio $P_START 0
    set c1 [clock milliseconds]
    vset $vio $P_START 1
    set c2 [clock milliseconds]
    vset $vio $P_START 0
    set c3 [clock milliseconds]
    vset $vio $P_START 1
    set c4 [clock milliseconds]
    puts "APLUS_P3_COMMIT_MS k=$k c1=$c1 c2=$c2 c3=$c3 c4=$c4 d_c2c1=[expr {$c2-$c1}] d_c3c2=[expr {$c3-$c2}] d_c4c3=[expr {$c4-$c3}] span_c1_c4=[expr {$c4-$c1}]"
    after 20
    set v3 [vget $vio $P_STATUS]
    puts "APLUS_P3_AFTER k=$k [fmtr $vio [sdec $v3]]"
    set s3 [expr {($v3 >> 21) & 1}]
    set b3 [expr {($v3 >> 17) & 1}]
    puts "APLUS_P3_SSL k=$k ssl_bit21=$s3 busy_after=$b3 (trigger if ssl=1 while the 2nd rise landed inside the ~83.9ms busy window)"
    if {$s3 == 1} {
        set triggered 1
        puts "APLUS_P3_TRIGGERED k=$k"
        break
    } else {
        puts "APLUS_P3_NOT_TRIGGERED k=$k (commit latency may have missed the window; not a defect)"
        wait_done $vio $P_STATUS "after_miss_$k"
    }
}
puts "APLUS_P3_ATTEMPTS $attempts"
if {$triggered} {
    wait_done $vio $P_STATUS "post_trigger"
    set cb1 [clock milliseconds]
    vset $vio $P_START 0
    set cb2 [clock milliseconds]
    vset $vio $P_START 1
    set cb3 [clock milliseconds]
    after 20
    set vc [vget $vio $P_STATUS]
    puts "APLUS_P3_CLEAN_COMMIT_MS cb1=$cb1 cb2=$cb2 cb3=$cb3"
    puts "APLUS_P3_CLEAN_READ [fmtr $vio [sdec $vc]]"
    puts "APLUS_P3_SSL_CLEARED ssl_bit21=[expr {($vc >> 21) & 1}] (expect 0 after an accepted start)"
    wait_done $vio $P_STATUS "post_clean"
    set vf [vget $vio $P_STATUS]
    puts "APLUS_P3_FINAL [fmtr $vio [sdec $vf]]"
} else {
    puts "APLUS_P3_SSL_CLEARED SKIPPED (never triggered in $attempts attempts)"
}

set ve [vget $vio $P_STATUS]
puts "APLUS_P1_FINAL [fmtr $vio [sdec $ve]]"
puts "APLUS_P3_END"

disconnect_hw_server
puts "PROBE_MDIO_APLUS_DONE"
