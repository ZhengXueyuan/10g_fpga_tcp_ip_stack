#=============================================================================
# check_cfgdiff_teeth.tcl -- 构建脚本 XDMA 回读断言的**排练 + 牙口自检** (不出位流, 不改树)
#=============================================================================
# 为什么: `board/build_p7b_ku5p.tcl` 的 XDMA 块里那段"与冻结参照转储逐行 diff"是本次
#   改造**最重的一条判据** (CONF §2.1 的决定性判据: MM 参照 vs 本次 只差 2 行)。
#   它跑在一个 34 分钟的构建里 —— 不能只靠"到时候看看"。
#   ⇒ 本脚本把那段代码**从句点里原样取出来** (文本提取 `proc p7b_cfg_dump` ..
#   `set xdma_cfg_mine`, 与构建脚本同源, 无副本漂移), 然后在本目录用**真参照件**排练:
#     T1 牙口: cfg_st vs cfg_mm 的差 = 恰 {Component_Name, xdma_axi_intf_mm}? (CONF §2.1 复核)
#     T2 排练: 以 cfg_st 为底、只把 Component_Name 改成 xdma_0 (模拟我们构建的 dump)
#              ⇒ vs ST 参照 = 1 行 / vs MM 参照 = 2 行 (与构建脚本断言逐字相同的判据)
#     T3 负对照 (该红时红): 在 T2 的底稿上**篡改一个无关键** (CONFIG.BASEADDR)
#              ⇒ 必须**多检出**那一行 (证明断言真的会红, 不是恒绿)
#   判据: T1/T2/T3 全过 => `P9CFGDIFF_TEETH = OK`; 否则打印差集并 exit 1。
#=============================================================================
set script_dir [file dirname [file normalize [info script]]]
set rr         [file dirname [file dirname [file dirname $script_dir]]]
set build_tcl  ${rr}/board/build_p7b_ku5p.tcl
set ref_dir    ${rr}/_proj_10g/notes/p8_axis_conf_20261011/work
set fails 0

puts "P9CFGDIFF_BUILD_TCL = $build_tcl"
puts "P9CFGDIFF_REF_DIR   = $ref_dir"

# ---- 1. 从句点里提取 procs (文本切片; 与构建脚本同源) ----
set fh [open $build_tcl r] ; set bt [read $fh] ; close $fh
set i0 [string first "proc p7b_cfg_dump" $bt]
set i1 [string first "set xdma_cfg_mine" $bt]
if {$i0 < 0 || $i1 < 0 || $i1 <= $i0} { puts "P9CFGDIFF_EXTRACT_FAIL i0=$i0 i1=$i1" ; exit 1 }
set snippet [string range $bt $i0 [expr {$i1 - 1}]]
puts "P9CFGDIFF_SNIPPET_LINES = [llength [split $snippet \n]]"
eval $snippet

# ---- 2. 造两份"我方的 dump" ----
set st_src  ${ref_dir}/cfg_st_post_gen.txt
set mm_src  ${ref_dir}/cfg_mm_post_gen.txt
set mine    ${script_dir}/rehearsal_mine.txt
set mine_bad ${script_dir}/rehearsal_mine_bad.txt

set fh [open $st_src r] ; set sttxt [read $fh] ; close $fh
set fh [open $mine w] ; puts -nonewline $fh [string map {"CONFIG.Component_Name = xdma_st" "CONFIG.Component_Name = xdma_0"} $sttxt] ; close $fh
set fh [open $mine_bad w] ; puts -nonewline $fh [string map {"CONFIG.Component_Name = xdma_st" "CONFIG.Component_Name = xdma_0" \
                                                              "CONFIG.BASEADDR = 0x00001000" "CONFIG.BASEADDR = 0xDEAD0000"} $sttxt] ; close $fh

# ---- 3. T1: 两份参照之间的关系 (CONF §2.1 的复核) ----
set d1 [p7b_cfg_diff_keys $mm_src $st_src]
puts "P9CFGDIFF_T1_keys = [llength $d1] ; {[join $d1 { }]}"
if {[llength $d1] != 2} { incr fails ; puts "P9CFGDIFF_T1_FAIL (期望 2)" }
foreach k $d1 { if {[lsearch -exact {CONFIG.Component_Name CONFIG.xdma_axi_intf_mm} $k] < 0} { incr fails ; puts "P9CFGDIFF_T1_UNEXPECTED $k" } }

# ---- 4. T2: 排练 (与构建脚本逐字相同的两条判据) ----
set d2s [p7b_cfg_diff_keys $st_src $mine]
set d2m [p7b_cfg_diff_keys $mm_src $mine]
puts "P9CFGDIFF_T2_vs_ST_keys = [llength $d2s] ; {[join $d2s { }]}"
puts "P9CFGDIFF_T2_vs_MM_keys = [llength $d2m] ; {[join $d2m { }]}"
if {[llength $d2s] != 1} { incr fails ; puts "P9CFGDIFF_T2_ST_FAIL" }
if {[llength $d2m] != 2} { incr fails ; puts "P9CFGDIFF_T2_MM_FAIL" }

# ---- 5. T3: 负对照 (篡改无关键必须被检出) ----
set d3s [p7b_cfg_diff_keys $st_src $mine_bad]
puts "P9CFGDIFF_T3_vs_ST_keys = [llength $d3s] ; {[join $d3s { }]}"
if {[lsearch -exact $d3s "CONFIG.BASEADDR"] < 0} { incr fails ; puts "P9CFGDIFF_T3_FAIL (篡改未被检出 = 断言无牙)" }

if {$fails == 0} { puts "P9CFGDIFF_TEETH = OK (T1/T2/T3 全过)" } else { puts "P9CFGDIFF_TEETH = FAIL ($fails)" }
puts "P9CFGDIFF_DONE"
exit
