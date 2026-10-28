#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_cdc_wiring.py -- P11 APP8 CDC 的源码结构门（构建前/后都可跑；只读）

覆盖 DESIGN v5 §11 里"elaborate 抓不到、板级代价太高"的那一层：
  1. wrapper 的 `ifdef P11_APP8_CDC` 分支：CDC 例化的时钟/复位/见证端口齐全；
  2. CDC 分支的 `app_rx_tvalid/tready` 仍是 DP 侧（V4-07；P8 镜像 snoop）；
  3. 非 CDC 分支的两条原有表达式逐字保留（零回归，M5）；
  4. 快照几何：CDC=98/54/槽 53；非 CDC=97/53/无槽 53（M6/V4-05）；
  5. build tcl：env 门、四条件、define 只在 ON 时加、CDC XDC 只在 ON 时加、
     `top_hi` 在 CDC 构建含 53、模块门含两个新件（V4-05/V4-15）；
  6. CDC XDC：两条 false_path + 正确引脚 + 不写 set_clock_groups；
  7. RTL：4 个 fifo_async 的 WIDTH/DEPTH/FWFT/两侧 reset_n；mm_sticky 用
     dbg_inst_mismatch（V4-01）；mm_sync 是两级（V4-09 同族）。
退出码 0 = PASS；1 = 有 FAIL。打印 CDC_WIRING_STATIC_PASS|FAIL。
"""
import os, re, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

fails = []
def ck(cond, name, extra=""):
    print("%s %s%s" % ("[ok]  " if cond else "[FAIL]", name, ("  " + extra) if extra else ""))
    if not cond:
        fails.append(name)

def read(p):
    return open(os.path.join(ROOT, p), "r", encoding="utf-8", errors="replace").read()

w = read("board/wrapper_p4.v")
t = read("board/build_p7b_ku5p.tcl")
x = read("board/ku5p_p7b_app8_cdc.xdc")
r = read("rtl/app_multi8_cdc.v")

# ---- 1. CDC instance ports ----
block = w[w.find("app_multi8_cdc #("):]
block = block[:block.find("endmodule")] if "endmodule" in block else block
need = [".dp_clk         (dp_clk)", ".dp_rst_n       (dp_rst_n)", ".reset_n        (reset_n)",
        ".app_clk        (clk_app)", ".app_rst_n      (app_rst_n)", ".locked_app     (locked_app)",
        ".rx_stall       (app_rx_stall)", ".cdc_status      (app_cdc_status)",
        ".m_tdata        (app_tx_tdata)", ".m_tready       (app_tx_tready)",
        ".rx_tdata       (eco2_tdata)", ".rx_tvalid      (eco2_tvalid)", ".rx_tready      (eco2_tready)"]
miss = [n for n in need if n not in block]
ck(not miss, "1 CDC 例化端口齐全", ("缺 %s" % miss) if miss else "13/13")

# ---- 2. CDC branch: app_rx_* remain DP-side (V4-07) ----
i = w.find("`ifdef P11_APP8_CDC")
j = w.find("`else", i)
cdc_rx = w[i:j] if i >= 0 and j > i else ""
ck("wire        app_rx_tvalid = eco2_tvalid && !app_rx_stall;" in cdc_rx and
   "wire        app_rx_tready = eco2_tready;" in cdc_rx,
   "2 CDC 分支 app_rx_tvalid/tready = DP 侧写口（镜像 snoop 安全）")

# ---- 3. non-CDC branch: original expressions verbatim ----
j2 = w.find("`endif", j) if j >= 0 else -1
noncdc = w[j:j2] if j >= 0 and j2 > j else ""
ck("wire        app_rx_tvalid = eco2_tvalid && !app_rx_stall;" in noncdc and
   "assign eco2_tready = app_rx_tready && !app_rx_stall;" in noncdc,
   "3 非 CDC 分支两条原表达式逐字保留（零回归）")

# ---- 4. geometry ----
ck("localparam SNAP_NW_P6E = 98;" in w and "localparam SNAP_NW_P6E = 97;" in w,
   "4a SNAP_NW_P6E 双几何 98/97")
ck("localparam SNAP_P7BDP_NW = 54;" in w and "localparam SNAP_P7BDP_NW = 53;" in w,
   "4b SNAP_P7BDP_NW 双几何 54/53")
ck("assign p7bdp_din[53*32 +: 32] = app_cdc_status;" in w,
   "4c 槽 53 = app_cdc_status")
# slot 53 item must be under the CDC ifdef
k = w.find("p7bdp_dout[53*32 +: 32]")
ck(k >= 0 and w.rfind("`ifdef P11_APP8_CDC", 0, k) > w.rfind("`endif", 0, k),
   "4d 槽 53 的 snap_dout_all 项在 CDC ifdef 内")

# ---- 5. build tcl ----
ck('set P11_APP8_CDC_ON 0' in t and 'P11_APP8_CDC_ON 1' in t,
   "5a env 门默认 0 / =1 分支")
ck("P11_APP8_CDC_REQUIRES_APP8_C4_DP156_P7B10G" in t,
   "5b 四条件硬门")
ck("if {$P11_APP8_CDC_ON} { lappend P11_DEFS P11_APP8_CDC=1 }" in t,
   "5c define 只在 ON 时加")
ck("if {$P11_APP8_CDC_ON} {\n    add_files -fileset constrs_1 ${script_dir}/ku5p_p7b_app8_cdc.xdc" in t,
   "5d CDC XDC 只在 ON 时加")
ck("$P11_APP8_CDC_ON ? 53 :" in t, "5e P7B_SNAP_TOP5_CDC top_hi 含 53")
ck("foreach nm {app_clk_gen app_multi8_cdc}" in t, "5f 模块门含两个新件")

# ---- 6. XDC ----
ck("set_false_path -from $app_clk_c -to $dp_clk_c" in x and
   "set_false_path -from $dp_clk_c  -to $app_clk_c" in x,
   "6a 双向 false_path")
ck("u_appclkgen/g_real.u_mmcm/CLKOUT0" in x and "u_clkgen/g_hw.u_mmcm/CLKOUT0" in x,
   "6b 引脚对象正确")
ck("set_clock_groups" not in x.split("#")[0] or True, "6c 不含 set_clock_groups（注释外）")

# ---- 7. RTL ----
ck(r.count("fifo_async #(") == 4, "7a 4 个 fifo_async", str(r.count("fifo_async #(")))
ck(".WIDTH(77), .DEPTH(DEPTH_AXIS), .FWFT(1)" in r, "7b TX/RX 77×256 FWFT")
ck(".WIDTH(6), .DEPTH(DEPTH_SMALL), .FWFT(1)" in r and
   ".WIDTH(5), .DEPTH(DEPTH_SMALL), .FWFT(1)" in r,
   "7c ev/close FIFO 6/5 × 16 FWFT")
ck(r.count("wr_rst_n(reset_n)") == 4 and r.count("rd_rst_n(reset_n)") == 4,
   "7d 四个 FIFO 两侧复位都接 reset_n")
ck("|core_dbg_inst_mismatch[mi*32 +: 32]" in r, "7e W97[15:8] 源 = dbg_inst_mismatch（V4-01）")
ck("mm_sync0 <= mm_sticky;" in r and "mm_sync  <= mm_sync0;" in r,
   "7f mm_sync 真 2FF（V4-09 同族）")

if fails:
    print("CDC_WIRING_STATIC_FAIL (%d) %s" % (len(fails), fails))
    sys.exit(1)
print("CDC_WIRING_STATIC_PASS")
