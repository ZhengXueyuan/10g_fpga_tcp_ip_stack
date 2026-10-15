# q_0x28.tcl - P9 E12 观测计数器 (BID 0x28) 定向时序查询 (后布线)
#   本件 = **q_0x27.tcl 的副本** (查询面/坑回避全沿用), 把"本刀主角族"换成本刀面:
#     ⭐ 本刀 = `rtl/app_pattern.v` 的**四只纯观测计数器** (实例 `u_app` 内):
#       · stat_up_ev / stat_sw_req / stat_sw_apply / stat_up_pend (各 32 FF)
#       · 出口: 4 根出端口 → wrapper 的 `app_up_ev/app_sw_req/app_sw_apply/app_up_pend`
#         → `biz_w71..biz_w74` → `p7bdp_din[31..34]` → `u_snap_p7bdp` (dp 域)
#         → `u_snap_dp` (pcie 域) → 快照 W71..W74。
#   核心判据面 = **这四个计数器锥有没有进 DP 域 / 全局 WNS 的报告面**
#     (预期: 远离 —— 纯观测 4×32 FF + 常量门; **若进 ⇒ 逐个打出来**)。
#   ⚠️ #90: 网名 ≠ RTL 信号 (归并产物) ⇒ 每个纯线族都把 from/to 两侧 pin 打出来核驱动/负载。
#   ⚠️ #92: 若某族网名未存活 ⇒ 那条定向查询**结构性缺席**, 只能写"未观测到"。
#   对照面 (逐字沿用 0x27 脚本, 供跨代并列):
#     · 全局 setup top-5 · DP 域 g_hw.clk_out0 setup top-10/50 · DPWNS
#     · 参考族: u_tcp_tx (0x1D/0x26/0x27 轮最差族宿主) / u_tcp_rx / ctrl_tcpcsum /
#       u_app_udp 老族 / tcb / u_fifo_a / u_fifo_b / mac_rx / u_snap_p7bdp / u_snap_dp
#   用法: vivado -mode batch -nojournal -nolog -source q_0x28.tcl -tclargs <routed.dcp> <outdir>
#   ⚠️ 同一份脚本对 0x27 归档 dcp / 0x28 新 dcp 各跑一次 ⇒ 两代读数直接并列
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
  # ⭐ 本刀核心: 每个族都在 **DP 组**里单独查一遍 from/to (进前 10 就会被这里抓住)
  set pf2 [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -from $cells]
  if {[llength $pf2] > 0} {
    set p [lindex $pf2 0]
    puts "F $tag dp_from slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "F $tag dp_from NOPATH" }
  set pt2 [get_timing_paths -group g_hw.clk_out0 -delay_type max -max_paths 1 -sort_by slack -quiet -to $cells]
  if {[llength $pt2] > 0} {
    set p [lindex $pt2 0]
    puts "F $tag dp_to slack=[get_property SLACK $p] lvl=[get_property LOGIC_LEVELS $p] sp=[get_property STARTPOINT_PIN $p] ep=[get_property ENDPOINT_PIN $p]"
  } else { puts "F $tag dp_to NOPATH" }
}

# ---------- 2a) ⭐ 本刀面: E12 四计数器 + u_app 全族 ----------
fam e12_up_ev    {*u_app/stat_up_ev*}
fam e12_sw_req   {*u_app/stat_sw_req*}
fam e12_sw_apply {*u_app/stat_sw_apply*}
fam e12_up_pend  {*u_app/stat_up_pend*}
fam e12_u_app    {*u_app/*}
# ---------- 2b) 参考族 (跨代并列: 本刀把这些族挤动了吗) ----------
fam ref_tcp_tx   {*u_tcp_tx*}
fam ref_fifo_a   {*u_tcp_tx/u_fifo_a/*}
fam ref_tcp_rx   {*u_tcp_rx*}
fam ref_tcbcsum  {*ctrl_tcpcsum_reg*}
fam ref_app_udp  {*u_app_udp*}
fam ref_udp_tx   {*u_udp_tx*}
fam ref_tcb      {*u_tcb*}
fam ref_fifo_b   {*u_fifo_b/*}
fam ref_mac_rx   {*u_mac_rx*}
# ---------- 2c) 快照边界族 (E12 四字要穿过这两级 CDC) ----------
fam ref_snap_p7bdp {*u_snap_p7bdp*}
fam ref_snap_dp    {*u_snap_dp*}

# ---------- 3) ⭐ 纯线族: E12 四计数器出口链 + 事件线 → pins → from/to ----------
#    ⚠️ #90: 网名归并 ⇒ 每个族都把 from/to 两侧的 pin 名打出来 (驱动/负载人工核)
foreach nfam {stat_up_ev stat_sw_req stat_sw_apply stat_up_pend app_up_ev app_sw_req app_sw_apply app_up_pend biz_w71 biz_w72 biz_w73 biz_w74 ev_up ev_same_act ev_other_act sw_apply} {
  set mnets [get_nets -hier -quiet -filter "NAME =~ *${nfam}*"]
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

# ---------- 4) ⭐ 报告面命中: 四计数器/u_app 在 DP top10/top50 里出现几次 ----------
#    核心判据 = 这四个计数器锥有没有进 DP/WNS **报告面** (预期: 0 命中)
foreach f {dp_top10 dp_top50 global_top5} {
  if {[file exists $out/${f}.rpt]} {
    set fh [open $out/${f}.rpt r]
    set txt [read $fh]
    close $fh
    foreach pat {u_app stat_} {
      set hits 0
      foreach ln [split $txt "\n"] { if {[string match "*${pat}*" $ln]} { incr hits } }
      puts "R ${f} pat=${pat} hits=${hits}"
    }
  } else { puts "R ${f} MISSING" }
}

# ---------- 5) 全 cell 清单 (限 30/族; 处理网名归并) ----------
foreach spec {{*u_app/stat_up_ev* 40} {*u_app/stat_sw_req* 40} {*u_app/stat_sw_apply* 40} {*u_app/stat_up_pend* 40} {*u_app/ev_up* 12} {*u_app/up_pend_r* 12}} {
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
