#!/usr/bin/env python3
"""decode_w98_w99.py -- 解码 0x3D 的 W98/W99 TX 卡死定位束。

用法: python decode_w98_w99.py 0x<W98> 0x<W99>
或:   从 samples5 行里自动抓 W98=/W99= 并解码 (给一个文件路径)。
字段位序 = rtl/tcp_tx_frame.v 的 o_dbg_tx assign (0x3D)。
"""
import re, sys

RX = {0: "RX_IDLE", 1: "RX_RING", 2: "RX_FIN", 3: "RX_FLUSH"}
TX = {0: "T_IDLE", 1: "T_HDR", 2: "T_PAY", 3: "T_TAIL", 4: "T_DONE"}

def bits(v):
    return [(v >> i) & 1 for i in range(32)]

def dec_a(v):
    b = bits(v)
    names = [
        (1, "recv_first"), (3, "rx_bank"), (4, "tx_bank"),
        (5, "bank_rdy[0]"), (6, "bank_rdy[1]"), (7, "fifo_empty_rx"),
        (8, "fifo_empty_tx"), (9, "fifo_full"), (10, "s_axis_tvalid"),
        (11, "s_axis_tready"), (12, "m_axis_tvalid"), (13, "m_axis_tready"),
        (14, "ack_pend_r"), (15, "ackq_empty"), (16, "svc"), (17, "ring_eval"),
        (18, "scan_now"), (19, "retx_active"), (20, "ctrl_slot_busy"),
        (21, "ctrl_tx_pend"), (23, "wnd_open"), (24, "tx_blk_sid"),
        (25, "st_ok"), (26, "acks_ok"), (27, "rx_flush"),
    ]
    out = [f"rx_state={RX.get(v & 3, '?')}", f"start_id={(v >> 28) & 0xF}"]
    out += [f"{n}={b[i]}" for i, n in names]
    return " ".join(out)

def dec_b(v):
    b = bits(v)
    out = [f"tx_state={TX.get((v >> 29) & 7, '?')}", f"thcnt={(v >> 26) & 7}",
           f"tx_is_probe={b[25]}", f"tx_is_ctrl={b[24]}", f"probe_sel={b[23]}",
           f"ps_stage_rdy={b[22]}", f"ps_stage_estab={b[21]}",
           f"retx_begin={b[20]}", f"retx_deny={b[19]}", f"ring_start={b[18]}",
           f"pay_load={b[17]}", f"replay_left={(v >> 12) & 0xF}",
           f"retx_id={(v >> 8) & 0xF}", f"svc_id={(v >> 4) & 0xF}",
           f"ctrl_id={v & 0xF}"]
    return " ".join(out)

def main():
    if len(sys.argv) == 3:
        print("W98:", dec_a(int(sys.argv[1], 0)))
        print("W99:", dec_b(int(sys.argv[2], 0)))
        return
    if len(sys.argv) == 2:
        txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
        for m in re.finditer(r"W98=(\S+)\s+W99=(\S+)", txt):
            a, b2 = m.group(1), m.group(2)
            try:
                print("W98:", dec_a(int(a, 0)))
                print("W99:", dec_b(int(b2, 0)))
            except ValueError:
                continue
        return
    print(__doc__)

if __name__ == "__main__":
    main()
