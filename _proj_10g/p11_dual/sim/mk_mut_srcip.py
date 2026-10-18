#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""mk_mut_srcip.py — G5 变异件生成器 (错源 IP 变异必须红)

把 rtl/tcp_tx_frame.v 复制到目标目录, 并**定向**破坏 per-connection 源 IP 的
三处用途 (IP 校验和种子 / 控制帧种子 / 头字源 IP), 让 G5 的 src-IP/csum 断言
必然红。替换点全部锚在 P11 引入的文本上, 任一处找不到 = 生成器硬失败 (防止
上游改名后变异件悄悄变成"原样副本")。
"""
import sys, os, re

def main():
    if len(sys.argv) != 3:
        print("usage: mk_mut_srcip.py <in_tcp_tx_frame.v> <out.v>")
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    s = open(src, encoding='utf-8', newline='').read()
    crlf = '\r\n' in s
    if crlf:
        s = s.replace('\r\n', '\n')

    subs = [
        ("wire [31:0] csum_sip = PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip;",
         "wire [31:0] csum_sip = cfg_src_ip;   // MUTANT"),
        ("wire [31:0] csum_sip_ctrl = PER_CONN_SRC_IP ? ctrl_lip : cfg_src_ip;",
         "wire [31:0] csum_sip_ctrl = cfg_src_ip;   // MUTANT"),
        ("wire [31:0] h_lip     = h_ctrl ? ctrl_lip     : f_lip[tx_bank];   // P11: 源 IP",
         "wire [31:0] h_lip     = cfg_src_ip;   // MUTANT"),
        ("3'd3: m_axis_tdata <= {ip_csum_r, lip_r, dip_r[31:16]};",
         "3'd3: m_axis_tdata <= {ip_csum_r, cfg_src_ip, dip_r[31:16]};   // MUTANT"),
        ("                                                PER_CONN_SRC_IP ? ctrl_lip : cfg_src_ip);",
         "                                                cfg_src_ip);   // MUTANT"),
        ("ip_csum_r <= ip_csum_calc(total_len_r, id_cap, dip_r, lip_r);",
         "ip_csum_r <= ip_csum_calc(total_len_r, id_cap, dip_r, cfg_src_ip);   // MUTANT"),
    ]
    n = 0
    for old, new in subs:
        if old not in s:
            print("MK_MUT_SRCIP: anchor missing: %s" % old[:70])
            return 3
        s = s.replace(old, new, 1)
        n += 1
    if crlf:
        s = s.replace('\n', '\r\n')
    open(dst, 'w', encoding='utf-8', newline='').write(s)
    print("MK_MUT_SRCIP_OK subs=%d out=%s" % (n, dst))
    return 0

if __name__ == '__main__':
    sys.exit(main())
