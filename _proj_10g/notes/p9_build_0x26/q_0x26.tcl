# q_0x26.tcl - RFC seq 修复 (BID 0x26) 定向时序查询 (后布线)
#   本件 = **q_0x24.tcl 的副本** (查询面/坑回避全沿用), 把"本刀主角族"换成本刀面:
#     ⭐ 本刀 = `rtl/tcp_rx.v` 的 `wire seq_lt = seq_diff[31]` (唯一功能改点 1 行, 真差口径)。
#   逐条定向 (= 设计 §7.1-4):
#     (i)  `ra_rcv_nxt / seq32 / seq_diff → seq_lt` 这条组合锥 — **纯线, 不是 cell**
#          ⇒ 走 `get_nets` + `get_pins -of_objects` 的 from/to (⚠️ 全局坑 #90: 网名 ≠ RTL 信号;
#            归并产物会让"看着像你那条线"的网其实是别的东西 ⇒ from/to 两侧都要打出来核驱动/负载)
#     (ii) `acc_l / ackresp_l / w6a_ok_l` (三个 D 端 latch) 的 -to 最差
#     (iii)`*u_tcp_rx*` 全实例在 **DP 组** 内的 from/to (离 DP WNS 多远) + 全时钟面 any_from/any_to
#   对照面 (逐字沿用, 供跨代并列):
#     · 全局 setup top-5 · DP 域 g_hw.clk_out0 setup top-10/50 · DPWNS
#     · 被本刀"可能挤动"的参考族: u_tcp_tx (0x1D 轮全局最差族宿主) / ctrl_tcpcsum /
#       u_app_udp 老族 / tcb rcv_nxt_r / u_fifo_b
#   用法: vivado -mode batch -source q_0x26.tcl -tclargs <routed.dcp> <outdir>
#   ⚠️ 同一份脚本对 0x25 / 0x26 两个 routed dcp 各跑一次 ⇒ 两代读数直接并列
#      (无拆刀 ⇒ 差异**只登记不归因**: 含本刀 + P&R 重排两项, 分不开)。
set dcp [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
open_checkpoint $dcp

# ---------- 0) 全局 setup top-5 ----------
catch {report_timing -delay_type max -max_paths 5 -sort_by slack -file $out/global_top5.rpt}
set gp [get_timing_paths -delay_type max -max_paths 5 -sort_by slack -quiet]
set i 0
foreach p $gp {
  incr i
  puts "G #$i slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
}
puts "G_DONE n=[llength $gp]"

# ---------- 1) DP 域 g_hw.clk_out0: setup 前 10 / 前 50 ----------
catch {report_timing -group g_hw.clk_out0 -delay_type max -max_paths 10 -sort_by slack -file $out/dp_top10.rpt}
catch {report_timing -group g_hw.clk_out0 -delay_type max -max_paths 50 -sort_by slack -file $out/dp_top50.rpt}
set dp [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 10 -sort_by slack -quiet]
set i 0
foreach p $dp {
  incr i
  puts "DP #$i slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
}
puts "DP_DONE n=[llength $dp]"
set dw [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet]
if {[llength $dw] > 0} {
  set p [lindex $dw 0]
  puts "DPWNS slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
} else { puts "DPWNS NOPATH" }

# ---------- 2) 族 from/to 最差 (cell 面) ----------
proc fam {tag pat} {
  set cells [get_cells -hier -quiet -filter "NAME =~ $pat"]
  puts "F $tag ncell=[llength $cells]"
  if {[llength $cells] == 0} { puts "F $tag NOCELL"; return }
  set pf [get_timing_paths -delay_type max -max_paths 1 -sort_by slack -quiet -from $cells]
  if {[llength $pf] > 0} {
    set p [lindex $pf 0]
    puts "F $tag from_worst slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "F $tag from_NOPATH" }
  set pt [get_timing_paths -delay_type max -max_paths 1 -sort_by slack -quiet -to $cells]
  if {[llength $pt] > 0} {
    set p [lindex $pt 0]
    puts "F $tag to_worst slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "F $tag to_NOPATH" }
}

# ---------- 2a) ⭐ 本刀三个 D 端 latch (acc_l/ackresp_l/w6a_ok_l = seq_lt 的三个消费者) ----------
fam rfc_accl     {*u_tcp_rx/acc_l_reg*}
fam rfc_ackresp  {*u_tcp_rx/ackresp_l_reg*}
fam rfc_w6a       {*u_tcp_rx/w6a_ok_l_reg*}
fam rfc_seql_cell {*seq_lt*}
fam rfc_u_tcp_rx  {*u_tcp_rx*}
# ---------- 2b) 参考族 (跨代并列: 本刀把这些族挤动了吗) ----------
fam ref_tcp_tx   {*u_tcp_tx*}
fam ref_tcbcsum  {*ctrl_tcpcsum_reg*}
fam ref_app_udp  {*u_app_udp*}
fam ref_udp_tx   {*u_udp_tx*}
fam ref_tcb      {*u_tcb*}
fam ref_fifo_b   {*u_fifo_b*}
fam ref_mac_rx   {*u_mac_rx*}
fam ref_app_pat  {*u_app/*}

# ---------- 3) ⭐ 纯线族: seq_lt / seq_diff / seq32 / ra_rcv_nxt → pins → from/to ----------
#    ⚠️ #90: 网名归并 ⇒ 每个族都把 from/to 两侧的 pin 名打出来 (驱动/负载人工核)
foreach nfam {seq_lt seq_diff seq32 ra_rcv_nxt} {
  set mnets [get_nets -hier -quiet -filter "NAME =~ *u_tcp_rx/${nfam}*"]
  puts "N ${nfam}_nets=[llength $mnets]"
  foreach n $mnets { puts "N   net=[get_property NAME $n]" }
  if {[llength $mnets] > 0} {
    set mpins [get_pins -quiet -of_objects $mnets]
    puts "N ${nfam}_pins=[llength $mpins]"
    set k 0
    foreach pp $mpins { incr k; if {$k <= 8} { puts "N   pin=[get_property NAME $pp] dir=[get_property DIRECTION $pp]" } }
    if {[llength $mpins] > 0} {
      set pf [get_timing_paths -delay_type max -max_paths 1 -sort_by slack -quiet -from $mpins]
      if {[llength $pf] > 0} { set p [lindex $pf 0]
        puts "N ${nfam} from_worst slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
      } else { puts "N ${nfam} from_NOPATH" }
      set pt [get_timing_paths -delay_type max -max_paths 1 -sort_by slack -quiet -to $mpins]
      if {[llength $pt] > 0} { set p [lindex $pt 0]
        puts "N ${nfam} to_worst slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
      } else { puts "N ${nfam} to_NOPATH" }
      # DP 组内 from/to
      set pf2 [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -from $mpins]
      if {[llength $pf2] > 0} { set p [lindex $pf2 0]
        puts "N ${nfam} dp_from slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
      } else { puts "N ${nfam} dp_from NOPATH" }
      set pt2 [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -to $mpins]
      if {[llength $pt2] > 0} { set p [lindex $pt2 0]
        puts "N ${nfam} dp_to slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
      } else { puts "N ${nfam} dp_to NOPATH" }
    }
  }
}

# ---------- 4) u_tcp_rx 在 DP 组内 from/to (它是不是 DP WNS 的宿主) ----------
set rx [get_cells -hier -quiet -filter {NAME =~ *u_tcp_rx*}]
puts "RX rx_cells=[llength $rx]"
if {[llength $rx] > 0} {
  set pf [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -from $rx]
  if {[llength $pf] > 0} { set p [lindex $pf 0]
    puts "RX rx_dp_from slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "RX rx_dp_from NOPATH" }
  set pt [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -to $rx]
  if {[llength $pt] > 0} { set p [lindex $pt 0]
    puts "RX rx_dp_to slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "RX rx_dp_to NOPATH" }
  set pf2 [get_timing_paths -delay_type max -max_paths 3 -sort_by slack -quiet -from $rx]
  set k 0
  foreach p $pf2 { incr k
    puts "RX rx_any_from #$k slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  }
  set pt2 [get_timing_paths -delay_type max -max_paths 3 -sort_by slack -quiet -to $rx]
  set k 0
  foreach p $pt2 { incr k
    puts "RX rx_any_to #$k slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  }
} else { puts "RX SKIP (no u_tcp_rx cells)" }

# ---------- 5) 全 cell 清单 (限 30/族; 处理网名归并) ----------
foreach spec {{*u_tcp_rx/acc_l_reg* 10} {*u_tcp_rx/ackresp_l_reg* 10} {*u_tcp_rx/w6a_ok_l_reg* 10} {*seq_lt* 20} {*seq_diff* 20} {*u_tcp_rx/seq_hi_r* 10}} {
  set pat [lindex $spec 0]
  set lim [lindex $spec 1]
  set cells [get_cells -hier -quiet -filter "NAME =~ $pat"]
  puts "E pat=$pat ncell=[llength $cells]"
  set k 0
  foreach c $cells {
    incr k
    if {$k <= $lim} { puts "E   cell=[get_property NAME $c] ref=[get_property REF_NAME $c]" }
  }
}
puts "N_DONE"
