#!/usr/bin/env python3
"""decode_w98_w99.py -- 解码 0x3D-B2 的紧凑诊断字 (W71, 32 位)。

用法:
  python decode_w98_w99.py 0x<W71>                # 单个值
  python decode_w98_w99.py <samples.txt>          # 从样本文件抓 W71=... 逐行解码

位序 (与 rtl/tcp_tx_frame.v 的 o_dbg_tx/dbg_word 同步):
  [1:0] rx_state  [2] recv_first  [3] rx_flush  [4] fifo_full
  [5] bank_rdy[0] [6] bank_rdy[1] [7] s_axis_tvalid [8] s_axis_tready
  [9] m_axis_tvalid [10] m_axis_tready [11] wnd_open [12] tx_blk_sid
  [13] acks_ok [14] st_ok [15] svc [16] ring_eval [17] scan_now
  [18] retx_active [19] ack_pend_r [20] ackq_empty [21] ctrl_slot_busy
  [22] tx_is_ctrl [25:23] tx_state [29:26] start_id [30] spare [31] fifo_empty_rx
"""
import re, sys

RX = {0: "RX_IDLE", 1: "RX_RING", 2: "RX_FIN", 3: "RX_FLUSH"}
TX = {0: "T_IDLE", 1: "T_HDR", 2: "T_PAY", 3: "T_TAIL", 4: "T_DONE"}

SINGLES = [
    (2, "recv_first"), (3, "rx_flush"), (4, "fifo_full"),
    (5, "bank_rdy0"), (6, "bank_rdy1"), (7, "s_axis_tvalid"),
    (8, "s_axis_tready"), (9, "m_axis_tvalid"), (10, "m_axis_tready"),
    (11, "wnd_open"), (12, "tx_blk_sid"), (13, "acks_ok"), (14, "st_ok"),
    (15, "svc"), (16, "ring_eval"), (17, "scan_now"), (18, "retx_active"),
    (19, "ack_pend_r"), (20, "ackq_empty"), (21, "ctrl_slot_busy"),
    (22, "tx_is_ctrl"), (30, "spare"), (31, "fifo_empty_rx"),
]

def dec(v):
    out = [f"rx_state={RX.get(v & 3, '?')}",
           f"tx_state={TX.get((v >> 23) & 7, '?')}",
           f"start_id={(v >> 26) & 0xF}"]
    out += [f"{n}={(v >> b) & 1}" for b, n in SINGLES]
    return " ".join(out)

def main():
    if len(sys.argv) != 2:
        print(__doc__); return
    arg = sys.argv[1]
    if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", arg):
        print(dec(int(arg, 0))); return
    txt = open(arg, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"W71=(\S+)", txt):
        try:
            print(dec(int(m.group(1), 0)))
        except ValueError:
            pass

if __name__ == "__main__":
    main()
