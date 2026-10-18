# P11 P2 build 0x2C directed STA -- READ-ONLY on the post-route dcp.
# Run AFTER the build completes (never concurrently with a build).
# Directed -from/-to queries only; the top-200 list is a cross-check, not the oracle (#66).
set here [file dirname [file normalize [info script]]]
set R [file normalize [file join $here ".." ".." ".." ".."]]
set DCP "$R/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp"
set OUT "$here/STA_DIRECTED_0x2C.txt"
puts "P11BUILD0x2C-STA open $DCP"
open_checkpoint $DCP
set fh [open $OUT w]
puts $fh "# P11 P2 build 0x2C directed STA (post-route dcp)  [clock format [clock seconds]]"
puts $fh "# dcp = $DCP"
puts $fh "# NOTE:纸面/历史对照另存; 本文件只记录本次 dcp 的读数。"

proc fam_from {fh tag pattern {extra ""}} {
    set cells {}
    if {$extra eq ""} {
        set cells [get_cells -hier -quiet -filter "NAME =~ *$pattern*"]
    } else {
        set cells [get_cells -hier -quiet -filter "NAME =~ *$pattern*" ]
    }
    if {![llength $cells]} {
        puts $fh [format "%-46s NO_CELL" $tag]
        return
    }
    set p {}
    catch { set p [get_timing_paths -from $cells -delay_type max -max_paths 1 -sort_by slack] }
    if {![llength $p]} {
        puts $fh [format "%-46s cells=%-5d NO_PATH_OUT" $tag [llength $cells]]
        return
    }
    puts $fh [format "%-46s cells=%-5d slack=%s  %s -> %s" $tag [llength $cells] \
        [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}
proc fam_to {fh tag pattern} {
    set cells [get_cells -hier -quiet -filter "NAME =~ *$pattern*"]
    if {![llength $cells]} {
        puts $fh [format "%-46s NO_CELL" "${tag}-TO"]
        return
    }
    set p {}
    catch { set p [get_timing_paths -to $cells -delay_type max -max_paths 1 -sort_by slack] }
    if {![llength $p]} {
        puts $fh [format "%-46s cells=%-5d NO_PATH_IN" "${tag}-TO" [llength $cells]]
        return
    }
    puts $fh [format "%-46s cells=%-5d slack=%s  %s -> %s" "${tag}-TO" [llength $cells] \
        [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}

# --- global + DP-domain (g_hw.clk_out0) worst paths --------------------------
set gp [get_timing_paths -delay_type max -max_paths 1 -sort_by slack]
puts $fh "# GLOBAL worst_setup_slack = [get_property SLACK $gp]"
if {[llength $gp]} {
    puts $fh "# GLOBAL start = [get_property STARTPOINT_PIN $gp]"
    puts $fh "# GLOBAL end   = [get_property ENDPOINT_PIN $gp]"
}
puts $fh "\n# --- timing groups present ---"
catch { puts $fh [join [lsort [get_property GROUPS [get_timing_paths -delay_type max -max_paths 1]]] " "] }
set dp_paths {}
catch { set dp_paths [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 10 -sort_by slack] }
puts $fh "\n# --- DP group (g_hw.clk_out0) top10 by slack ---"
set i 0
foreach p $dp_paths {
    incr i
    puts $fh [format "DP%02d slack=%s  %s -> %s" $i [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
}

# --- DESIGN_v2r1 §5.3 directed families --------------------------------------
puts $fh "\n# --- directed families: worst setup path FROM the family ---"
fam_from $fh "u_tcp_tx/f_lip_reg"        "u_tcp_tx/f_lip_reg"
fam_from $fh "u_tcp_tx/ctrl_lip_reg"     "u_tcp_tx/ctrl_lip_reg"
fam_from $fh "u_rx_merge"                "u_rx_merge/"
fam_from $fh "u_tx_udp_arb"              "u_tx_udp_arb/"
fam_from $fh "u_tx_udp_arb_p1"           "u_tx_udp_arb_p1/"
fam_from $fh "u_tx_arb"                  "u_tx_arb/"
fam_from $fh "u_tx_arb_p1"               "u_tx_arb_p1/"
fam_from $fh "u_hls"                     "u_hls/"
fam_from $fh "u_maccnt_ch0rx"            "u_maccnt_ch0rx/"
fam_from $fh "u_maccnt_ch0tx"            "u_maccnt_ch0tx/"

# hold_b_reg[1248..1407] = the five new snapshot words (P11 P2) in the p7bdp bundle
set hb_all [get_cells -hier -quiet -filter "NAME =~ *u_snap_p7bdp/hold_b_reg*"]
set hb_sel {}
foreach c $hb_all {
    set nm [get_property NAME $c]
    if {[regexp {hold_b_reg\[(\d+)\]} $nm -> idx]} {
        if {$idx >= 1248 && $idx <= 1407} { lappend hb_sel $c }
    }
}
puts $fh [format "%-46s cells=%-5d (all u_snap_p7bdp/hold_b_reg = %d)" "u_snap_p7bdp/hold_b_reg[1248..1407]" [llength $hb_sel] [llength $hb_all]]
if {[llength $hb_sel]} {
    set p {}
    catch { set p [get_timing_paths -from $hb_sel -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $p]} {
        puts $fh [format "%-46s cells=%-5d slack=%s  %s -> %s" "u_snap_p7bdp/hold_b_reg[1248..1407]" [llength $hb_sel] \
            [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
    }
    # also look INTO these cells (catch side must not be the new word's consumer)
    set pin {}
    catch { set pin [get_timing_paths -to $hb_sel -delay_type max -max_paths 1 -sort_by slack] }
    if {[llength $pin]} {
        puts $fh [format "%-46s cells=%-5d slack=%s  %s -> %s" "u_snap_p7bdp/hold_b_reg[1248..1407]-TO" [llength $hb_sel] \
            [get_property SLACK $pin] [get_property STARTPOINT_PIN $pin] [get_property ENDPOINT_PIN $pin]]
    }
} else {
    puts $fh "u_snap_p7bdp/hold_b_reg[1248..1407]        NO_CELL_IN_RANGE"
}

# cam_rd_dip -> u_tcp_tx/*csum*  (the N-6 combinational CAM read cone)
set camsrc [get_cells -hier -quiet -filter "NAME =~ *cam_rd_dip*"]
set csnk  [get_cells -hier -quiet -filter "NAME =~ *u_tcp_tx/*csum*"]
puts $fh [format "%-46s src_cells=%-5d snk_cells=%d" "cam_rd_dip -> u_tcp_tx/*csum*" [llength $camsrc] [llength $csnk]]
set p {}
catch { set p [get_timing_paths -from $camsrc -to $csnk -delay_type max -max_paths 1 -sort_by slack] }
if {[llength $p]} {
    puts $fh [format "%-46s slack=%s  %s -> %s" "cam_rd_dip -> u_tcp_tx/*csum*" \
        [get_property SLACK $p] [get_property STARTPOINT_PIN $p] [get_property ENDPOINT_PIN $p]]
} else {
    puts $fh "cam_rd_dip -> u_tcp_tx/*csum*                   NO_PATH"
}

# --- directed families: worst setup path INTO the family (sink check) --------
puts $fh "\n# --- directed families: worst setup path INTO the family ---"
foreach f {u_tcp_tx/f_lip_reg u_tcp_tx/ctrl_lip_reg u_rx_merge/ u_tx_udp_arb/ u_tx_udp_arb_p1/ u_tx_arb/ u_tx_arb_p1/ u_hls/ u_maccnt_ch0rx/ u_maccnt_ch0tx/} {
    fam_to $fh $f $f
}

# --- top-200 cross-check: does any directed family appear there? -------------
set topf "$here/TOP200_0x2C.rpt"
report_timing -delay_type max -max_paths 200 -sort_by slack -file $topf
set txt [read [open $topf r]]
puts $fh "\n# top200 scan for directed families (occurrences; heuristic only):"
foreach f {f_lip_reg ctrl_lip_reg cam_rd_dip u_rx_merge u_tx_udp_arb u_tx_arb u_snap_p7bdp/hold_b_reg u_hls u_maccnt} {
    puts $fh [format "%-28s %d" $f [regexp -all -- $f $txt]]
}
close $fh
puts "P11BUILD0x2C-STA done -> $OUT"
exit
