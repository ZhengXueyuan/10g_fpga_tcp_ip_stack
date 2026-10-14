# probe_phy.tcl -- drive the VIO MDIO master on the KU5P board over JTAG.
#
# Usage (from the Windows box):
#   vivado -mode batch -source probe_phy.tcl [-tclargs <bitfile>]
#
# Programs the probe bitstream through the peer box's hw_server, then reads the
# RTL8211E identification registers from every clause-22 PHY address.
#
# Two things that cost real time to discover and are easy to trip over again:
#
# 1. The probes file (.ltx) must be associated with the hw_device. Without it
#    Vivado still finds the VIO *core* in the fabricated design but enumerates
#    zero probes -- get_hw_probes returns an empty list and [Labtools 27-1974]
#    warns about a design/probes mismatch. The .ltx carries the probe names and
#    bit offsets.
#
# 2. Vivado names the probes after the CONNECTED NETS, not after probe_outN.
#    So they show up as vio_start / vio_phyad / vio_regad / vio_wr_data /
#    vio_probe_in. Both spellings are looked up below so this keeps working if a
#    future synthesis run names them the other way.
#
# VIO bit map (must match mdio_vio_top.v):
#   probe_out0[0]   start       probe_in0[15:0] rd_data
#   probe_out1[0]   op          probe_in0[16]   done_sticky
#   probe_out1[1]   force_rst   probe_in0[17]   busy
#   probe_out2[4:0] phyad       probe_in0[18]   eth_rstn
#   probe_out3[4:0] regad       probe_in0[19]   mdio_i
#   probe_out4[15:0] wr_data
#
# Reading only needs start/phyad/regad: every VIO output comes up 0 out of
# configuration, which is already "op=read, force_rst=deasserted". Writes and
# forced resets are the only operations that need the ambiguous 2-bit port.

set here [file normalize [file dirname [info script]]]
set bit  [lindex $argv 0]
if {$bit eq ""} {
    set bit [file join $here pj_mdio mdio_prj.runs impl_1 mdio_vio_top.bit]
}
if {![file exists $bit]} { error "bitstream not found: $bit" }
set ltx [file rootname $bit].ltx
puts "BIT $bit"

open_hw_manager
connect_hw_server -url 192.168.0.38:3121
current_hw_target [lindex [get_hw_targets] 0]
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
puts "DEVICE $dev"

set_property PROGRAM.FILE $bit $dev
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
    set_property FULL_PROBES.FILE $ltx $dev
    puts "PROBES $ltx"
} else {
    puts "WARNING: no .ltx next to $bit -- VIO probes will not be enumerable"
}
program_hw_devices $dev
refresh_hw_device $dev

set vio [lindex [get_hw_vios -of_objects $dev] 0]
if {$vio eq ""} { error "no VIO found on $dev -- does the bitstream contain it?" }
puts "VIO $vio"

# Resolve a probe by any of its possible names.
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

# Two API details that cost time to find:
#   * commit_hw_vio and refresh_hw_vio both want the hw_vio CORE. Passing a probe
#     to refresh_hw_vio raises [Labtoolstcl 44-186].
#   * INPUT_VALUE comes back as a STRING in the probe's own radix, which is HEX
#     by default -- so it reads as "c0000", not as a number, and any arithmetic
#     on it fails with "can't use non-numeric string as operand of >>". Convert
#     using INPUT_VALUE_RADIX rather than assuming decimal.
# Writing needs the value zero-padded to the probe's radix width: a 5-bit probe
# at radix HEX wants two characters, so plain "5" is rejected with
# [Designutils 20-1474] ("value [5] has [1] value characters, required [2]").
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

# One clause-22 read. Returns {data done busy rstn mdio}.
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
                 [expr {($v >> 17) & 1}] [expr {($v >> 18) & 1}] [expr {($v >> 19) & 1}]]
}

# --- prove the output path works before trusting the scan ---
vset $vio $P_PHYAD 5
set rb [get_property OUTPUT_VALUE $P_PHYAD]
puts "WRITE_CHECK phyad set to 5, reads back <$rb>"
vset $vio $P_PHYAD 0

# --- link status ---
set v [vget $vio $P_STATUS]
puts [format "STATUS rstn=%d mdio=%d busy=%d done=%d rd=%04X" \
      [expr {($v >> 18) & 1}] [expr {($v >> 19) & 1}] [expr {($v >> 17) & 1}] \
      [expr {($v >> 16) & 1}] [expr {$v & 0xFFFF}]]

# --- scan every PHY address for identification registers ---
puts "PHYID_BEGIN"
set found 0
for {set a 0} {$a < 32} {incr a} {
    lassign [mdio_read $a 2] id1 done1 busy1 rstn1 mdio1
    if {!$done1} {
        puts [format "PHYID %2d -- no response (timeout)" $a]
        continue
    }
    lassign [mdio_read $a 3] id2 done2 busy2 rstn2 mdio2
    if {$id1 == 0xFFFF && $id2 == 0xFFFF} {
        puts [format "PHYID %2d -- silent (bus pulled up, 0xFFFF)" $a]
    } else {
        puts [format "PHYID %2d -- PHYID1=%04X PHYID2=%04X  (id = %04X%04X)  mdio_idle=%d" \
              $a $id1 $id2 $id1 $id2 $mdio1]
        incr found
    }
}
puts "PHYID_FOUND $found"
puts "PHYID_END"

disconnect_hw_server
puts "DONE"
