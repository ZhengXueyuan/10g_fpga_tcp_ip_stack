# Unit harness for the ROM log gate block extracted from board/build_p7b_ku5p.tcl.
# This does NOT run Vivado; it feeds synthetic synth logs to the real gate code.
# Env: BLOCK_FILE, SYNTH_LOG, HLS_DAT_COPIED
proc sec {s} { puts "SEC $s" }
set synth_log $::env(SYNTH_LOG)
set hls_dat_copied [expr {int($::env(HLS_DAT_COPIED))}]
source $::env(BLOCK_FILE)
puts "HARNESS_END"
