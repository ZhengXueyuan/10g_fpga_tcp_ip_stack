#!/bin/bash
# p2b_snap_0x31.sh -- round-local wrapper around p7b_snap.sh.
#   Default identity = 0x31 (P11 P3 C4); geometry = 85 words / UNIMPL 0x184
#   (same as 0x2D backstop-2). Explicit env overrides still win.
exec env NW=${NW:-85} EXPECT_BID=${EXPECT_BID:-0x00000031} UNIMPL_ADDR=${UNIMPL_ADDR:-0x184} \
    bash /tmp/p7b_biz/p7b_snap.sh "$@"
