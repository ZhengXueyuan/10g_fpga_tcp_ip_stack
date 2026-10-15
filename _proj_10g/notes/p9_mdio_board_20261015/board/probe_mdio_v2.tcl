# probe_mdio_v2.tcl -- drive the VIO MDIO master on the KU5P board over JTAG.
#
# Round p9_mdio_board_20261015 (B3). Base = _proj_mdio/probe_phy.tcl with the
# self-contained PROGRAMMING section (:53-61 / program_hw_devices) REMOVED --
# programming happens earlier via the audited tcpreg launcher (1MHz + DONE gate).
# This script only connects, binds the .ltx, and reads.
#
# VIO bit map (must match mdio_vio_top.v after edits E1-E5; new bits at the MSB end):
#   probe_out0[0]   start       probe_in0[15:0] rd_data
#   probe_out1[0]   op          probe_in0[16]   done_sticky
#   probe_out1[1]   force_rst   probe_in0[17]   busy
#   probe_out2[4:0] phyad       probe_in0[18]   eth_rstn
#   probe_out3[4:0] regad       probe_in0[19]   mdio_i
#   probe_out4[15:0] wr_data    probe_in0[20]   param_bad    (NEW, static 0 on prod)
#                               probe_in0[21]   stat_start_lost (NEW, sticky)
#
# The five JTAG/VIO traps from probe_phy.tcl are preserved verbatim in spirit:
#  1. .ltx must be associated with hw_device or get_hw_probes returns empty.
#  2. Probe names = CONNECTED NET names (vio_start/vio_phyad/.../vio_probe_in);
#     both spellings are looked up.
#  3. commit_hw_vio / refresh_hw_vio want the hw_vio CORE, not a probe.
#  4. INPUT_VALUE is a STRING in INPUT_VALUE_RADIX (HEX by default).
#  5. OUTPUT_VALUE must be zero-padded to the probe's radix width.
#
# Arms (per DESIGN_v2r2 §4.2):
#   J-A  full scan 32 addresses x {reg2, reg3}; answer set must be exactly {0,1}
#   J-B  interleaved freshness (1,r2)->(7,r2)->(0,r2)->(7,r2)->(0,r2)->(1,r2)->(31,r2)
#   J-D  new-bit reading: every record's ssl / pbad columns (expect 0 everywhere;
#        "constant 0" and "not wired" are indistinguishable on this arm -- R-b)
# Every transaction is logged as one raw TX line (first-hand archive).

set here [file normalize [file dirname [info script]]]
set bit  [lindex $argv 0]
if {$bit eq ""} {
    set bit D:/repo/XCKU5PMini/_proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit
}
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

# NOTE: no program_hw_devices here -- the board was programmed by the tcpreg
# launcher (1MHz + DONE gate) before this script ran. We only bind probes.
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

# ---- direct check that the 22-bit width sync took effect (DESIGN §2.4) ----
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
    set r "HEX"
    catch {set r [get_property INPUT_VALUE_RADIX $p]}
    switch -- $r {
        HEX     { return [expr "0x$s"] }
        BIN     { return [expr "0b$s"] }
        OCT     { return [expr "0o$s"] }
        default { return [expr {$s}] }
    }
}

# One clause-22 read. Returns {data done busy rstn mdio ssl pbad}.
proc mdio_read {phyad regad} {
    global vio P_START P_PHYAD P_REGAD P_STATUS
    vset $vio $P_PHYAD $phyad
    vset $vio $P_REGAD $regad
    vset $vio $P_START 1            ;# rising edge -> one frame
    vset $vio $P_START 0            ;# re-arm the edge detector
    set v 0
    for {set i 0} {$i < 40} {incr i} {
        set v [vget $vio $P_STATUS]
        if {($v >> 16) & 1} break   ;# done_sticky
        after 20
    }
    return [list [expr {$v & 0xFFFF}] [expr {($v >> 16) & 1}] \
                 [expr {($v >> 17) & 1}] [expr {($v >> 18) & 1}] \
                 [expr {($v >> 19) & 1}] [expr {($v >> 20) & 1}] \
                 [expr {($v >> 21) & 1}]]
}

# One raw archive line per transaction (the required first-hand record).
proc tx_line {tag phyad regad r} {
    lassign $r rd done busy rstn mdio ssl pbad
    puts [format "TX %s phyad=%02d regad=%02d rd=%04X done=%d busy=%d rstn=%d mdio=%d ssl=%d pbad=%d" \
          $tag $phyad $regad $rd $done $busy $rstn $mdio $ssl $pbad]
    return $r
}

# --- output-path proof before trusting the scan (same as probe_phy.tcl) ---
vset $vio $P_PHYAD 5
set rb [get_property OUTPUT_VALUE $P_PHYAD]
puts "WRITE_CHECK phyad set to 5, reads back <$rb>"
vset $vio $P_PHYAD 0

# --- idle status: position sanity for OLD bits (mdio idle high, rstn high, busy low) ---
set v [vget $vio $P_STATUS]
lassign [list [expr {$v & 0xFFFF}] [expr {($v >> 16) & 1}] [expr {($v >> 17) & 1}] \
         [expr {($v >> 18) & 1}] [expr {($v >> 19) & 1}] [expr {($v >> 20) & 1}] \
         [expr {($v >> 21) & 1}]] rd0 d0 b0 r0 m0 s0 p0
puts [format "IDLE_STATUS rd=%04X done=%d busy=%d rstn=%d mdio=%d ssl=%d pbad=%d" \
      $rd0 $d0 $b0 $r0 $m0 $s0 $p0]

# ============================ ARM J-A: full scan ============================
puts "ARM_J_A_BEGIN"
set found {}
set ssl_sum 0
set pbad_sum 0
set noresp {}
for {set a 0} {$a < 32} {incr a} {
    set r2 [tx_line "A_r2" $a 2 [mdio_read $a 2]]
    lassign $r2 id1 done1 busy1 rstn1 mdio1 ssl1 pbad1
    incr ssl_sum $ssl1
    incr pbad_sum $pbad1
    if {!$done1} { lappend noresp [format "a%02d_r2" $a] }
    set r3 [tx_line "A_r3" $a 3 [mdio_read $a 3]]
    lassign $r3 id2 done2 busy2 rstn2 mdio2 ssl2 pbad2
    incr ssl_sum $ssl2
    incr pbad_sum $pbad2
    if {!$done2} { lappend noresp [format "a%02d_r3" $a] }
    if {$id1 == 0xFFFF && $id2 == 0xFFFF} {
        puts [format "PHYID %2d -- silent (bus pulled up, 0xFFFF)" $a]
    } else {
        puts [format "PHYID %2d -- PHYID1=%04X PHYID2=%04X  (id = %04X%04X)  mdio_idle=%d" \
              $a $id1 $id2 $id1 $id2 $mdio1]
        lappend found $a
    }
}
puts "ARM_J_A_ANSWERED [join $found {,}]"
puts "ARM_J_A_NO_RESPONSE [join $noresp {,}]"
puts "ARM_J_A_SSL_SUM=$ssl_sum"
puts "ARM_J_A_PBAD_SUM=$pbad_sum"
puts "ARM_J_A_END"

# ================== ARM J-B: interleaved freshness (same stdout) =============
puts "ARM_J_B_BEGIN"
set jb_seq [list [list 1 2] [list 7 2] [list 0 2] [list 7 2] [list 0 2] [list 1 2] [list 31 2]]
set jb_rd {}
foreach pair $jb_seq {
    lassign $pair a g
    set r [tx_line "B" $a $g [mdio_read $a $g]]
    lappend jb_rd [format "%04X" [lindex $r 0]]
}
puts "ARM_J_B_RD [join $jb_rd { }]"
puts "ARM_J_B_END"

# ==================== ARM J-D: new-bit reading (ssl/pbad) ====================
# Already logged per-record above (ssl=/pbad= columns). Summary only:
puts "ARM_J_D_BEGIN"
puts "ARM_J_D_NOTE every TX line above carries ssl= and pbad=; production arm expects 0"
puts "ARM_J_D_END"

disconnect_hw_server
puts "PROBE_MDIO_V2_DONE"
