# 构建脚本 Tcl 完整性检查 (info complete: 括号/引号/续行平衡) —— 不执行构建
set sd [file dirname [file normalize [info script]]]
set f  ${sd}/../../../board/build_p7b_ku5p.tcl
set fh [open $f r]; set t [read $fh]; close $fh
puts "P9BUILDTCL_FILE = $f"
puts "P9BUILDTCL_LINES = [llength [split $t \n]]"
puts "P9BUILDTCL_COMPLETE = [info complete $t]"
# 逐段定位: 若整体不完整, 找第一个不完整的行累积点
if {![info complete $t]} {
    set acc ""
    set n 0
    foreach line [split $t \n] {
        incr n
        append acc $line "\n"
        if {[info complete $acc] && [string trim $line] ne "" && ![string match "*\\" $line]} { set acc "" }
    }
    puts "P9BUILDTCL_LAST_OPEN_AROUND_LINE = $n"
}
puts "P9BUILDTCL_DONE"
exit
