#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p9_dissect_0x29: 单比特拆刀 -- 恰两行编辑 (board/wrapper_p4.v)
  (1) :2185  .PERSIST_EN(1'b1) -> 1'b0   (persist 关闭; 0x28 内容其余不动)
  (2) :4377  32'h00000028 -> 32'h00000029 + 行尾注释换代
逐行锚点显式、各断言 n=1; 字节级 CRLF 保持。
"""
import hashlib, sys
P = r"D:\repo\XCKU5PMini\udp_hls_10g\board\wrapper_p4.v"
b = open(P, "rb").read()
sha0 = hashlib.sha256(b).hexdigest()
crlf0 = b.count(b"\r\n"); lone0 = b.count(b"\n") - crlf0

A1_OLD = b"    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b1)) u_tcp_tx ("
A1_NEW = b"    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b0)) u_tcp_tx ("
A2_OLD = "        .BUILD_ID_V (32'h00000028),     // \u26a0\ufe0f \u6bcf\u6b21\u6539\u52a8\u81ea\u589e (\u524d\u7f6e\u95f8\u8bfb\u8fd9\u4e00\u9879\u8ba4\u4f4d\u6d41; E12 \u89c2\u6d4b\u8ba1\u6570\u5668 = 0x28)".encode("utf-8")
A2_NEW = "        .BUILD_ID_V (32'h00000029),     // \u26a0\ufe0f \u6bcf\u6b21\u6539\u52a8\u81ea\u589e (\u524d\u7f6e\u95f8\u8bfb\u8fd9\u4e00\u9879\u8ba4\u4f4d\u6d41; PERSIST_EN \u62c6\u5200\uff08persist\uff1d\u5173\uff1b0x28 \u5185\u5bb9\uff09= 0x29)".encode("utf-8")

assert b.count(A1_OLD) == 1, "A1 anchor n=%d" % b.count(A1_OLD)
assert b.count(A2_OLD) == 1, "A2 anchor n=%d" % b.count(A2_OLD)
mode = sys.argv[1] if len(sys.argv) > 1 else "--dry-run"
if mode == "--apply":
    b2 = b.replace(A1_OLD, A1_NEW, 1).replace(A2_OLD, A2_NEW, 1)
    crlf1 = b2.count(b"\r\n"); lone1 = b2.count(b"\n") - crlf1
    assert lone1 == 0 and crlf1 == crlf0, "CRLF 损伤 crlf %d->%d lone %d->%d" % (crlf0, crlf1, lone0, lone1)
    open(P, "wb").write(b2)
    print("APPLY OK")
print("sha_before", sha0)
print("crlf", crlf0, "loneLF", lone0)
