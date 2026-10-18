    ('_proj_pcie/p6e_snap_check.sh',
     r'''#       `0x11C` (word 71) 真正未实现 ✓ (上限 119 字); 红线 = **绝不能挑 ≥0x200**。
SNAP_WORDS=${SNAP_WORDS:-88}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 88 ⇒ 0x190 (P11 P2-甲 起; 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0xEC —— 读旧位流须显式覆盖)
snap_addr(){ printf '0x%X' $(( 0x20 + 4*$1 )); }                          # word 号 → 字节地址''',
     r'''#       `0x11C` (word 71) 真正未实现 ✓ (上限 119 字); 红线 = **绝不能挑 ≥0x200**。
SNAP_WORDS=${SNAP_WORDS:-85}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 85 ⇒ 0x184 (0x2D backstop-2 起; 88 ⇒ 0x190 (0x2D 首跑/0x2C); 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0xEC —— 读旧位流须显式覆盖)
snap_addr(){ printf '0x%X' $(( 0x20 + 4*$1 )); }                          # word 号 → 字节地址''', 1),
    ('_proj_pcie/p6e_snap_check.sh',
     r''' #    ⚠️ 名字**同源** = `_proj_pcie/p7b_biz/p7b_snap.sh` 的 `NAME[]`([65]..[69]);
 #       真值源 = `board/wrapper_p4.v` 的装配段注释。表长必须 == SNAP_WORDS (88),
 #       否则循环把它们打成 `<无标签>` (2026-10-10 加固轮: 本表原只到 W64; M1 再补 W70;''',
     r''' #    ⚠️ 名字**同源** = `_proj_pcie/p7b_biz/p7b_snap.sh` 的 `NAME[]`([65]..[69]);
 #       真值源 = `board/wrapper_p4.v` 的装配段注释。表长必须 == SNAP_WORDS (85),
 #       否则循环把它们打成 `<无标签>` (2026-10-10 加固轮: 本表原只到 W64; M1 再补 W70;''', 1),
    ('_proj_pcie/p6e_snap_check.sh',
     r''' # ---- P11 P2-甲 (2026-10-18) 新增 5 字 (83 → 88 字窗口; 双口数据面 + 双板 IP) ----
 "w83_tx_p0_frames  (TX port0/ch1 帧数; arb 输出 tlast)"''',
     r''' # ---- P11 P2-甲 (2026-10-18) 新增 5 字 (83 → 88 字窗口; 双口数据面 + 双板 IP) ----
 #   ⛔ 0x2D backstop-2 (2026-10-18): 删 W85/W86/W87 (classify 总帧 / ch0 FIFO ovf /
 #      ch0 MAC TX) ⇒ 窗口 85 字, 顶端只剩 W84/W83。标签项也删除 (表长必须 == 85)。
 "w83_tx_p0_frames  (TX port0/ch1 帧数; arb 输出 tlast)"''', 1),
    ('_proj_pcie/p6e_snap_check.sh',
     r''' "w83_tx_p0_frames  (TX port0/ch1 帧数; arb 输出 tlast)"
 "w84_tx_p1_frames  (TX port1/ch0 帧数; arb 输出 tlast)"
 "w85_cls_frames    (rx_classify 总帧数 fast+slow, [31:0] 截断)"
 "w86_ch0_fifo_ovf  ({ch0 RX cdc ovf(16), ch0 txcdc ovf(16)} 饱和)"
 "w87_ch0_mac_tx    ({ch0 MAC abort(16), frames(16)} 饱和; 低半仅活动指示)" )
for (( i = 0; i < SNAP_WORDS; i++ )); do''',
     r''' "w83_tx_p0_frames  (TX port0/ch1 帧数; arb 输出 tlast)"
 "w84_tx_p1_frames  (TX port1/ch0 帧数; arb 输出 tlast)" )
for (( i = 0; i < SNAP_WORDS; i++ )); do''', 1),
    ('_proj_pcie/p7b_biz/p7b_snap.sh',
     r'''#!/bin/bash
# p7b_snap.sh -- 板侧快照窗口取数器 (**现役 = 88 字 / BID 0x2D**; 标题原文 = "板侧 **63** 字
#   快照窗口的取数器 (P7b Stage C: BID=10 / SNAP_NW=63)" —— 那一代已过时, 见下逐代订正)''',
     r'''#!/bin/bash
# p7b_snap.sh -- 板侧快照窗口取数器 (**现役 = 85 字 / BID 0x2D**; 标题原文 = "板侧 **63** 字
#   快照窗口的取数器 (P7b Stage C: BID=10 / SNAP_NW=63)" —— 那一代已过时, 见下逐代订正)''', 1),
    ('_proj_pcie/p7b_biz/p7b_snap.sh',
     r'''#   ⭐ F-21 (2026-10-18): 身份 0x2C → **0x2D** (W83..W87 改经 p7bdp CDC; 字长/未实现地址不变)。
#   ⭐ P11 P1 ch0 bring-up (2026-10-18): **字长 76 → 83** (W76..W82 = ch0 PCS/LOS/计数)''',
     r'''#   ⭐ F-21 (2026-10-18): 身份 0x2C → **0x2D** (W83..W87 改经 p7bdp CDC; 字长/未实现地址不变)。
#   ⛔ 0x2D backstop-2 (2026-10-18): **字长 88 → 85** —— 构建 backstop 删 W85/W86/W87
#      (classify 总帧 / ch0 FIFO ovf / ch0 MAC TX); 保留 W83/W84。未实现地址 **0x190 → 0x184**
#      (公式 `0x20+4*NW+16` 不变; MIR 四字随 NW 自动落到 0x174..0x180)。
#      ⚠️ 读 0x2D 首跑/backstop-1 归档位流须显式 `NW=88 UNIMPL_ADDR=0x190` (或 `NW=86`... )。
#   ⭐ P11 P1 ch0 bring-up (2026-10-18): **字长 76 → 83** (W76..W82 = ch0 PCS/LOS/计数)''', 1),
    ('_proj_pcie/p7b_biz/p7b_snap.sh',
     r'''#      (0x200 在 7 位译码下回绕到 word 0 = MAGIC ⇒ 假 FAIL)。
NW=${NW:-88}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*NW + 16 )))}   # 88 ⇒ 0x190 (P11 P2-甲 起; 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)
EXPECT_BID=${EXPECT_BID:-0x0000002D}''',
     r'''#      (0x200 在 7 位译码下回绕到 word 0 = MAGIC ⇒ 假 FAIL)。
NW=${NW:-85}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*NW + 16 )))}   # 85 ⇒ 0x184 (0x2D backstop-2 起; 88 ⇒ 0x190 (0x2D 首跑/0x2C); 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)
EXPECT_BID=${EXPECT_BID:-0x0000002D}''', 1),
    ('_proj_pcie/p7b_biz/p7b_snap.sh',
     r'''# ⭐ P11 P2-甲 (2026-10-18): W83..W87 (p7bdp 槽 39..43; b 域 = dp_clk)
[83]=tx_p0_frames   [84]=tx_p1_frames   [85]=cls_frames
[86]=ch0_fifo_ovf   [87]=ch0_mac_tx
)''',
     r'''# ⭐ P11 P2-甲 (2026-10-18): W83..W87 (p7bdp 槽 39..43; b 域 = dp_clk)
# ⛔ 0x2D backstop-2 (2026-10-18): W85/W86/W87 已删 (不可读) ⇒ 只保留 W83/W84。
[83]=tx_p0_frames   [84]=tx_p1_frames
)''', 1),
    ('_proj_pcie/p7b_gate4_negctrl.sh',
     r'''# ---- 造一块**规范**快照文本 ---------------------------------------------------
# 几何: **88 字 (W0..W87)** —— P11 F-21 修复 (2026-10-18, BID=0x2D / 未实现 0x190);
#       (原句: "76 字 (W0..W75) —— p9 孤儿修复 (2026-10-17, BID=0x2A / 未实现 0x160)" = 历史代, 逐字保留于下)''',
     r'''# ---- 造一块**规范**快照文本 ---------------------------------------------------
# 几何: **85 字 (W0..W84)** —— 0x2D backstop-2 (2026-10-18, BID=0x2D / 未实现 0x184);
#       (原句: "88 字 (W0..W87) —— P11 F-21 修复 (2026-10-18, BID=0x2D / 未实现 0x190)" = 历史代, 逐字保留于下)
#       (原句: "76 字 (W0..W75) —— p9 孤儿修复 (2026-10-17, BID=0x2A / 未实现 0x160)" = 历史代, 逐字保留于下)''', 1),
    ('_proj_pcie/p7b_gate4_negctrl.sh',
     r'''                0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
                0 0 0 0 0)   # W51..W87 (M1: W70 = app_rx_mirror.drop_bytes; E12: W71..W74 = 换流门四观测计数器; p9 孤儿修复: W75 = app_ctrl.stat_orphan; P11 P2-甲: W83..W87 = 双口 TX 帧/classify/ovf/MAC TX)
    local i; for (( i = 0; i < 88; i++ )); do printf 'W%d 0x%X\n' "$i" "${V[$i]}"; done
    echo "UNIMPL 0xffffffff"''',
     r'''                0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
                0 0)   # W51..W84 (0x2D backstop-2: W85..W87 已删)
    local i; for (( i = 0; i < 85; i++ )); do printf 'W%d 0x%X\n' "$i" "${V[$i]}"; done
    echo "UNIMPL 0xffffffff"''', 1),
    ('_proj_pcie/p7b_gate4_negctrl.sh',
     r'''awk '/^W[0-9]+ /{ split($1,a,"W"); idx=a[2]; val[idx]=$2; n++; next } { print }' "$S/s2.txt" > "$S/m_off_b.txt"
shift1(){ awk -v NW=88 '/^W[0-9]+ /{ split($1,a,"W"); idx=a[2]+1; if(idx>NW-1) idx=0; printf "W%d %s\n", idx, $2; next } { print }' "$1" > "$2"; }
shift1 "$S/s1.txt" "$S/m_off_a.txt"; shift1 "$S/s2.txt" "$S/m_off_b.txt"''',
     r'''awk '/^W[0-9]+ /{ split($1,a,"W"); idx=a[2]; val[idx]=$2; n++; next } { print }' "$S/s2.txt" > "$S/m_off_b.txt"
shift1(){ awk -v NW=85 '/^W[0-9]+ /{ split($1,a,"W"); idx=a[2]+1; if(idx>NW-1) idx=0; printf "W%d %s\n", idx, $2; next } { print }' "$1" > "$2"; }
shift1 "$S/s1.txt" "$S/m_off_a.txt"; shift1 "$S/s2.txt" "$S/m_off_b.txt"''', 1),
    ('_proj_pcie/p7b_gate4_accept.sh',
     r'''#    WU 二轮 / Build 2 = `EXPECT_BID=0x00000009 SNAP_WORDS=63`。
SNAP_WORDS=${SNAP_WORDS:-88}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 88 ⇒ 0x190 (P11 P2-甲 起; 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x128/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)
# ⚠️ 未实现地址的**公式 M1 起变了**: 旧 = `0x20 + 4*SNAP_WORDS` (63/65/66/67/70 字各代成立);''',
     r'''#    WU 二轮 / Build 2 = `EXPECT_BID=0x00000009 SNAP_WORDS=63`。
SNAP_WORDS=${SNAP_WORDS:-85}
UNIMPL_ADDR=${UNIMPL_ADDR:-$(printf '0x%X' $(( 0x20 + 4*SNAP_WORDS + 16 )))}   # 85 ⇒ 0x184 (0x2D backstop-2 起; 88 ⇒ 0x190 (0x2D 首跑/0x2C); 83 ⇒ 0x17C (P11 P1); 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B); 70 字及更早 = 0x138/0x12C/0x128/0x124/0x11C/0x114/0xEC —— 读旧位流须显式覆盖)
# ⚠️ 未实现地址的**公式 M1 起变了**: 旧 = `0x20 + 4*SNAP_WORDS` (63/65/66/67/70 字各代成立);''', 1),
    ('_proj_pcie/p7b_gate4_accept.sh',
     r'''  local tg="$1" st="${2:-}" ; local -n W="$3"
  if [ "$SNAP_WORDS" -lt 88 ]; then
    res SKIP "B_CH0" "$tg ch0 束本代有效性 (SNAP_STATUS[7])" "P2 几何才有" "SNAP_WORDS=$SNAP_WORDS < 88 ⇒ 该代无 ch0 束"; return 0
  fi''',
     r'''  local tg="$1" st="${2:-}" ; local -n W="$3"
  if [ "$SNAP_WORDS" -lt 85 ]; then
    res SKIP "B_CH0" "$tg ch0 束本代有效性 (SNAP_STATUS[7])" "现役 85 字档才有" "SNAP_WORDS=$SNAP_WORDS < 85 ⇒ 按旧代几何跳过 (保守策略, 与 88 字时代同形)"; return 0
  fi''', 1),
    ('_proj_pcie/p7b_gate4_selftest.sh',
     r'''#      "扩窗弄坏了工具"而不是"判据没跟上" (同族教训见 P7B_GATE4_CRITERIA_CLOSEOUT.md)。
SW=${SNAP_WORDS:-88}
LAST_A=$(printf '0X%X' $(( 0x20 + 4*(SW-1) )))   # 末字地址  (65 ⇒ 0X120)''',
     r'''#      "扩窗弄坏了工具"而不是"判据没跟上" (同族教训见 P7B_GATE4_CRITERIA_CLOSEOUT.md)。
SW=${SNAP_WORDS:-85}
LAST_A=$(printf '0X%X' $(( 0x20 + 4*(SW-1) )))   # 末字地址  (65 ⇒ 0X120)''', 1),
    ('_proj_pcie/p7b_gate4_selftest.sh',
     r'''# ⚠️ 假字表的**尾段随几何走** (W61..W65 与"未实现地址"的坑位):
#   SW ≥ 83 (2026-10-18 P11 P1 ch0 bring-up 起) ⇒ 0x150..0x168 也是窗口内的真字''',
     r'''# ⚠️ 假字表的**尾段随几何走** (W61..W65 与"未实现地址"的坑位):
#   SW ≥ 85 (2026-10-18 0x2D backstop-2 起) ⇒ 窗口末字 = W84 @0x170, MIR 四字 = 0x174..0x180,
#     未实现地址 = **0x184**; W85..W87 **已删** (不在假字表里);
#   SW ≥ 83 (2026-10-18 P11 P1 ch0 bring-up 起) ⇒ 0x150..0x168 也是窗口内的真字''', 1),
    ('_proj_pcie/p7b_gate4_selftest.sh',
     r'''  0X190) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (88 字; = 0x20+4*SW+16)'
elif [ "$SW" -ge 83 ]; then''',
     r'''  0X190) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (88 字; = 0x20+4*SW+16)'
elif [ "$SW" -ge 85 ]; then
  FAKE_TAIL='  0X114) V=1234;;  # W61 app_ctrl.stat_wu (次数; 非 0 才像真板)
  0X118) V=0;;     # W62 app_ctrl.rx_occ_bytes (17 位 ⇒ 高位恒 0)
  0X11C) V=0;;     # W63 app_pattern.stat_frmwait_cyc (停滞拍数; 0 = 无停顿)
  0X120) V=0;;     # W64 app_pattern.stat_bp_cyc (背压拍数)
  0X124) V=0;;     # W65 mac_tx_10g.stat_tx_idle (S_IDLE 拍数; 0 = 空载, 建 D 新增)
  0X128) V=0;;     # W66 tcp_tx_frame.stat_winstall (窗口门停顿拍数, 建 E 新增)
  0X12C) V=0;;     # W67 tcp_tx_frame.stat_winstall_cap (板帽侧等窗拍数, 建 F 新增)
  0X130) V=0;;     # W68 tcp_rx.stat_ack_adv (推进 snd_una 的 ACK 次数, 建 F 新增)
  0X134) V=0;;     # W69 tcp_tx_frame.o_win_at_winstall (等窗拍操作点锁存, 建 F 新增)
  0X138) V=0;;     # W70 app_rx_mirror.drop_bytes (载荷镜像拒收字节数, M1 新增; 真字)
  0X13C) V=0;;     # W71 app_pattern.stat_up_ev (换流门观测; P9 E12)
  0X140) V=0;;     # W72 app_pattern.stat_sw_req (P9 E12)
  0X144) V=0;;     # W73 app_pattern.stat_sw_apply (P9 E12)
  0X148) V=0;;     # W74 app_pattern.stat_up_pend (P9 E12)
  0X14C) V=0;;     # W75 app_ctrl.stat_orphan (孤儿回收计数; p9 孤儿修复)
  0X150) V=0;;     # W76 ch0_pcs_status (P11 P1)
  0X154) V=0;;     # W77 ch0_pcs_evt
  0X158) V=0;;     # W78 ch0_los_mode
  0X15C) V=0;;     # W79 ch0_rx_frames
  0X160) V=0;;     # W80 ch0_rx_bytes
  0X164) V=0;;     # W81 ch0_rx_crc_err
  0X168) V=0;;     # W82 ch0_rx_drop
  0X16C) V=0;;     # W83 tx_p0_frames (P11 P2-甲; 0x2D backstop-2 保留)
  0X170) V=0;;     # W84 tx_p1_frames (保留)
  0X184) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (85 字; = 0x20+4*SW+16; MIR 0x174..0x180)'
elif [ "$SW" -ge 83 ]; then''', 1),
    ('_proj_pcie/p7b_gate4_selftest.sh',
     r'''  # ⚠️ 假板子的 BID 必须与 p6e_snap_check.sh 的 EXPECT_BID **同代** (否则正例的判据 1.2 假 FAIL,
  #    而"正例必须 0 FAIL"是本脚本的断言⑤)。现役 = **0x2D** (P11 F-21 修复 88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 ch0 bring-up 83 字 —— ⛔ 2026-10-15 同步轮: 原 0x27 = 换流门 R5 /
  #    0x26 = RFC seq 修复 / 0x25 = F-3 修复 / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时''',
     r'''  # ⚠️ 假板子的 BID 必须与 p6e_snap_check.sh 的 EXPECT_BID **同代** (否则正例的判据 1.2 假 FAIL,
  #    而"正例必须 0 FAIL"是本脚本的断言⑤)。现役 = **0x2D** (0x2D backstop-2 85 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 ch0 bring-up 83 字 / 0x2D 首跑 88 字 —— ⛔ 2026-10-15 同步轮: 原 0x27 = 换流门 R5 /
  #    0x26 = RFC seq 修复 / 0x25 = F-3 修复 / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时''', 1),
    ('_proj_pcie/p7b_gate4_livefake.sh',
     r'''        + [20000000, 151800000, 0, 0x2000100C, vcc, 0, 0, 0, 0, 0, 0, 0, 0, 0, freecnt(lat)] \
        + [0] * 37          # W51..W87 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 + p9 孤儿 + P11 P1 + P11 P2-甲 新增字 (accept 只要求窗口齐全 + 无 0xffffffff)
        #   ⛔ 2026-10-10 (构建 F): 16 -> **19** —— 构建 F 的远端请求是 70 字 (`for i in seq 0 69`),''',
     r'''        + [20000000, 151800000, 0, 0x2000100C, vcc, 0, 0, 0, 0, 0, 0, 0, 0, 0, freecnt(lat)] \
        + [0] * 34          # W51..W84 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 + p9 孤儿 + P11 P1 + P11 P2-甲 保留字 (0x2D backstop-2: W85..W87 已删; accept 只要求窗口齐全 + 无 0xffffffff)
        #   ⛔ 2026-10-10 (构建 F): 16 -> **19** —— 构建 F 的远端请求是 70 字 (`for i in seq 0 69`),''', 1),
    ('_proj_pcie/p7b_gate4_livefake.sh',
     r'''    #      兜底值同改 0x20 (当时的现役代)。⚠️ 本字典**按 NW 索引** ⇒ 读 0x1F 归档位流时须配套回改。
    bid = {88: "0x0000002D", 83: "0x0000002B", 76: "0x0000002A", 75: "0x00000029", 71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x0000002D")
    out("SNAP_BEGIN"); out("TLATCH %.9f %.9f" % (t0, t1)); out("GEN %d %d" % (g0, g1))''',
     r'''    #      兜底值同改 0x20 (当时的现役代)。⚠️ 本字典**按 NW 索引** ⇒ 读 0x1F 归档位流时须配套回改。
    #   ⛔ 2026-10-18 0x2D backstop-2: **85 字槽 = 0x2D** (现役); 88 字槽仍是 0x2D 的
    #      首跑/backstop-1 几何 (历史档, 保留)。本字典按 NW 索引 ⇒ 首键 = 现役 NW。
    bid = {85: "0x0000002D", 88: "0x0000002D", 83: "0x0000002B", 76: "0x0000002A", 75: "0x00000029", 71: "0x00000027", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x0000002D")
    out("SNAP_BEGIN"); out("TLATCH %.9f %.9f" % (t0, t1)); out("GEN %d %d" % (g0, g1))''', 1),
    ('_proj_pcie/p6e_snap_selftest_fix2.sh',
     r'''  0X168) V=0x00000000;;                                       # W82 ch0_rx_drop                                       # W75 app_ctrl.stat_orphan (76 字起; p9 孤儿修复)
  0X17C) V=0xffffffff;;                                       # 未实现地址 (76 字; = 0x20+4*SW+16)
  *)    V=0x00000000;;''',
     r'''  0X168) V=0x00000000;;                                       # W82 ch0_rx_drop                                       # W75 app_ctrl.stat_orphan (76 字起; p9 孤儿修复)
  0X184) V=0xffffffff;;                                       # 未实现地址 (0x2D backstop-2: 85 字; = 0x20+4*SW+16)
                                                              # (0X17C 现在是 MIR_CTRL 真字 ⇒ 由默认 0 覆盖)
  *)    V=0x00000000;;''', 1),
    ('_proj_10g/notes/p7b_gate4_3/final_state.sh',
     r'''BID=$(rd 0x04)
echo "MAGIC=$(rd 0x00) BID=$BID MARKER=$(rd 0x14) UNIMPL=$(rd 0x190) gen=$(( (s >> 16) & 0xffff ))"
# ⚠️ UNIMPL 地址跟窗口宽度走 (公式 = 0x20+4*NW+16; M1 起快照末字后接 MIR 四字):''',
     r'''BID=$(rd 0x04)
echo "MAGIC=$(rd 0x00) BID=$BID MARKER=$(rd 0x14) UNIMPL=$(rd 0x184) gen=$(( (s >> 16) & 0xffff ))"
# ⚠️ UNIMPL 地址跟窗口宽度走 (公式 = 0x20+4*NW+16; M1 起快照末字后接 MIR 四字):''', 1),
    ('_proj_10g/notes/p7b_gate4_3/final_state.sh',
     r'''# ⚠️ UNIMPL 地址跟窗口宽度走 (公式 = 0x20+4*NW+16; M1 起快照末字后接 MIR 四字):
#    **88 字 (P11 P2-甲, 2026-10-18 起) ⇒ 0x190** (word 100); 83 字 (P11 P1) ⇒ 0x17C
#    76 字 (p9 孤儿修复) = 0x160 (word 88); 75 字 (P9 E12) = 0x15C (word 87);''',
     r'''# ⚠️ UNIMPL 地址跟窗口宽度走 (公式 = 0x20+4*NW+16; M1 起快照末字后接 MIR 四字):
#    **85 字 (0x2D backstop-2, 2026-10-18 起) ⇒ 0x184** (word 97); 88 字 (0x2D 首跑/0x2C) ⇒ 0x190
#    (原句保留: 88 字 = P11 P2-甲 起); 83 字 (P11 P1) ⇒ 0x17C
#    76 字 (p9 孤儿修复) = 0x160 (word 88); 75 字 (P9 E12) = 0x15C (word 87);''', 1),
    ('_proj_10g/notes/p7b_gate4_3/final_state.sh',
     r'''#    判据语义不变 (仍是"读回值必须 == 期望值"), 只是期望值可注入。
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # ⛔ 2026-10-18 P11 F-21 修复 (88 字); 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复
EXPECT_BID_N=$(printf '%s' "$EXPECT_BID" | tr 'A-F' 'a-f')''',
     r'''#    判据语义不变 (仍是"读回值必须 == 期望值"), 只是期望值可注入。
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # ⛔ 2026-10-18 P11 F-21 修复 / 0x2D backstop-2 (85 字); 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复
EXPECT_BID_N=$(printf '%s' "$EXPECT_BID" | tr 'A-F' 'a-f')''', 1),
    ('_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py',
     r'''形态与真读数**逐字同形** (`reg_rw` 打 `0x..`; `ethtool -S` 打 "键 十进制"):
  快照 : SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W87 / UNIMPL / SNAP_END
         ⚠️ 几何 = **88 字 / BID 0x2D** (P11 F-21 修复, 2026-10-18 同步轮从 0x2C 同步; 几何同 0x2C)
            ⛔ 2026-10-17 p9 孤儿修复 同步: 上一行原写 "几何 = 75 字 / BID 0x29 (0x29 拆刀)";''',
     r'''形态与真读数**逐字同形** (`reg_rw` 打 `0x..`; `ethtool -S` 打 "键 十进制"):
  快照 : SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W84 / UNIMPL / SNAP_END
         ⚠️ 几何 = **85 字 / BID 0x2D** (0x2D backstop-2, 2026-10-18 同步轮从 88 字/0x190 同步;
         删 W85..W87 ⇒ 未实现地址 0x184 / MIR 0x174..0x180)
            ⛔ 2026-10-17 p9 孤儿修复 同步: 上一行原写 "几何 = 75 字 / BID 0x29 (0x29 拆刀)";''', 1),
    ('_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py',
     r'''# ⛔ 2026-10-10 构建 E 同步轮 (本夹具落后两代): 上一句保留 (它是 63 字那一代的历史实测) ——
# 现应读作 "不同代 ⇒ 假红": 本夹具现 = **88 字 / BID 0x2D**, accept 默认也已是 88 字 / BID 0x2D
# (`_geo_guard` 守着)。本轮订正经过: 63 字/BID 0xA (Stage C) → 65 字/BID 0x17 (构建 C) →''',
     r'''# ⛔ 2026-10-10 构建 E 同步轮 (本夹具落后两代): 上一句保留 (它是 63 字那一代的历史实测) ——
# 现应读作 "不同代 ⇒ 假红": 本夹具现 = **85 字 / BID 0x2D**, accept 默认也已是 85 字 / BID 0x2D
# (`_geo_guard` 守着)。本轮订正经过: 63 字/BID 0xA (Stage C) → 65 字/BID 0x17 (构建 C) →''', 1),
    ('_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py',
     r'''# (`_geo_guard` 守着)。本轮订正经过: 63 字/BID 0xA (Stage C) → 65 字/BID 0x17 (构建 C) →
# 66 字/0x18 (构建 D) → 67 字/0x19 (构建 E) → 70 字/0x1A (构建 F) → 70 字/0x1C (缺陷刀) → 70 字/0x1D (persist 刀) → 70 字/0x1E (snd_wnd 守卫) → 71 字/0x1F (M1 镜像窗) → 71 字/0x20 (P8 镜像 8 B/拍) → 71 字/0x21 (P8-STG 16 B 弹性暂存) → 71 字/0x22 (P9 XDMA MM→AXIS) → 71 字/0x23 (P9 D4 clr 口径修正) → 71 字/0x24 (P9 URAM 板内缓冲) → 71 字/0x25 (F-3 修复) → 71 字/0x26 (RFC seq 修复) → 71 字/0x27 (换流门 R5) → 75 字/0x28 (P9 E12 观测计数器) → 75 字/0x29 (0x29 拆刀) → 76 字/0x2A (p9 孤儿修复) → 83 字/0x2B (P11 P1 ch0 bring-up, 未实现地址 0x160 → 0x17C) → **88 字/0x2D (P11 F-21 修复, 几何同 0x2C, 未实现地址 0x190)**。
NW_FIX = 88                # 快照字数 (W0..W87; P11 P2-甲 起 —— 原 83 (P11 P1) / 76 (p9 孤儿修复) / 75 (P9 E12) / 71 (M1) / 70)
BID_FIX = 0x0000002D       # 位流身份 (P11 F-21 修复) —— ⛔ 2026-10-18: 原值 0x2C (P2-甲未烧板) / 0x2B (P11 P1)''',
     r'''# (`_geo_guard` 守着)。本轮订正经过: 63 字/BID 0xA (Stage C) → 65 字/BID 0x17 (构建 C) →
# 66 字/0x18 (构建 D) → 67 字/0x19 (构建 E) → 70 字/0x1A (构建 F) → 70 字/0x1C (缺陷刀) → 70 字/0x1D (persist 刀) → 70 字/0x1E (snd_wnd 守卫) → 71 字/0x1F (M1 镜像窗) → 71 字/0x20 (P8 镜像 8 B/拍) → 71 字/0x21 (P8-STG 16 B 弹性暂存) → 71 字/0x22 (P9 XDMA MM→AXIS) → 71 字/0x23 (P9 D4 clr 口径修正) → 71 字/0x24 (P9 URAM 板内缓冲) → 71 字/0x25 (F-3 修复) → 71 字/0x26 (RFC seq 修复) → 71 字/0x27 (换流门 R5) → 75 字/0x28 (P9 E12 观测计数器) → 75 字/0x29 (0x29 拆刀) → 76 字/0x2A (p9 孤儿修复) → 83 字/0x2B (P11 P1 ch0 bring-up, 未实现地址 0x160 → 0x17C) → **85 字/0x2D (0x2D backstop-2, 未实现地址 0x184; 88 字/0x190 = 0x2D 首跑/backstop-1 几何)**。
NW_FIX = 85                # 快照字数 (W0..W84; 0x2D backstop-2 起 —— 88 (0x2D 首跑) / 83 (P11 P1) / 76 (p9 孤儿修复) / 75 (P9 E12) / 71 (M1) / 70)
BID_FIX = 0x0000002D       # 位流身份 (P11 F-21 修复) —— ⛔ 2026-10-18: 原值 0x2C (P2-甲未烧板) / 0x2B (P11 P1)''', 1),
    ('_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py',
     r'''def snap_words(lat, w20, vcc):
    """**88 字 (W0..W87)**; lat = 该块锁存的时刻 (秒) ⇒ 三个域自由计数由它算出。
    W51..W66 (P7B-BIZ/WU/构建 C/D/E 新增字) 全填 0 —— accept 只要求"窗口齐全 + 无 0xffffffff 混入"''',
     r'''def snap_words(lat, w20, vcc):
    """**85 字 (W0..W84)**; lat = 该块锁存的时刻 (秒) ⇒ 三个域自由计数由它算出。
    W51..W66 (P7B-BIZ/WU/构建 C/D/E 新增字) 全填 0 —— accept 只要求"窗口齐全 + 无 0xffffffff 混入"''', 1),
    ('_proj_10g/notes/p7b_affinity/j6_r6fix.sh',
     r'''#        现在 63 字档的字表 = `5 53 54 61 62`; 61 字旧档 (W61/W62 不存在) 自动退回 `5 53 54`。
#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-88}` (P11 P2-甲 双口+双 IP; 更早 p9 孤儿修复=76 / P9 E12=75 / M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export** (原先那个 `NW=${NW:-61}` **没 export**,
#        只用于打印标签, 取数器仍用自己默认值 ⇒ "文档里的覆盖办法"在本脚本里**是失效的**,''',
     r'''#        现在 63 字档的字表 = `5 53 54 61 62`; 61 字旧档 (W61/W62 不存在) 自动退回 `5 53 54`。
#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-85}` (0x2D backstop-2; 更早 88 = 0x2D 首跑 / P2-甲 双口+双 IP / p9 孤儿修复=76 / P9 E12=75 / M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export** (原先那个 `NW=${NW:-61}` **没 export**,
#        只用于打印标签, 取数器仍用自己默认值 ⇒ "文档里的覆盖办法"在本脚本里**是失效的**,''', 1),
    ('_proj_10g/notes/p7b_affinity/j6_r6fix.sh',
     r'''#      现在: 档表是唯一来源, 失败提示与档位元数据都由它派生。
NW=${NW:-88}
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 P11 F-21 修复 (88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)
export NW EXPECT_BID        # ⚠️ 必须 export: 取数器 p7b_snap.sh 读的是**它自己的环境**''',
     r'''#      现在: 档表是唯一来源, 失败提示与档位元数据都由它派生。
NW=${NW:-85}
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 0x2D backstop-2 (85 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)
export NW EXPECT_BID        # ⚠️ 必须 export: 取数器 p7b_snap.sh 读的是**它自己的环境**''', 1),
    ('_proj_10g/notes/p7b_affinity/j6_r6fix.sh',
     r'''GEOM_TIERS=(
  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"''',
     r'''GEOM_TIERS=(
  "85|0x0000002D|61 62|0x2D backstop-2 (2026-10-18) 85 字 / BID 0x2D (W85/W86/W87 已删; W83/W84 = 每口 TX 帧数保留; MIR 0x174..0x180; 未实现地址 0x184)"
  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"''', 1),
    ('_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh',
     r'''#        现在 63 字档的字表 = `5 53 54 61 62`; 61 字旧档 (W61/W62 不存在) 自动退回 `5 53 54`。
#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-88}` (P11 P2-甲 双口+双 IP; 更早 p9 孤儿修复=76 / P9 E12=75 / M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export** (原先那个 `NW=${NW:-61}` **没 export**,
#        只用于打印标签, 取数器仍用自己默认值 ⇒ "文档里的覆盖办法"在本脚本里**是失效的**,''',
     r'''#        现在 63 字档的字表 = `5 53 54 61 62`; 61 字旧档 (W61/W62 不存在) 自动退回 `5 53 54`。
#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-85}` (0x2D backstop-2; 更早 88 = 0x2D 首跑 / P2-甲 双口+双 IP / p9 孤儿修复=76 / P9 E12=75 / M1 镜像窗=71 / 构建 F=70 / E=67 / P7B-A7=66 / 原 63) 且 **export** (原先那个 `NW=${NW:-61}` **没 export**,
#        只用于打印标签, 取数器仍用自己默认值 ⇒ "文档里的覆盖办法"在本脚本里**是失效的**,''', 1),
    ('_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh',
     r'''#      构建抬到 65 ⇒ **默认跑必然 J6_GEOM_FAIL + exit 3** (新位流测不了)。现在档表是唯一来源。
NW=${NW:-88}
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 P11 F-21 修复 (88 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)
export NW EXPECT_BID        # ⚠️ 必须 export: 取数器 p7b_snap.sh 读的是**它自己的环境**''',
     r'''#      构建抬到 65 ⇒ **默认跑必然 J6_GEOM_FAIL + exit 3** (新位流测不了)。现在档表是唯一来源。
NW=${NW:-85}
EXPECT_BID=${EXPECT_BID:-0x0000002D}   # 2026-10-18 0x2D backstop-2 (85 字; 原 0x2C = P2-甲未烧板 / 0x2B = P11 P1 / 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀)
export NW EXPECT_BID        # ⚠️ 必须 export: 取数器 p7b_snap.sh 读的是**它自己的环境**''', 1),
    ('_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh',
     r'''GEOM_TIERS=(
  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"''',
     r'''GEOM_TIERS=(
  "85|0x0000002D|61 62|0x2D backstop-2 (2026-10-18) 85 字 / BID 0x2D (W85/W86/W87 已删; W83/W84 = 每口 TX 帧数保留; MIR 0x174..0x180; 未实现地址 0x184)"
  "88|0x0000002D|61 62|P11 F-21 修复 (2026-10-18) 88 字 / BID 0x2D (W83..W87 改经 p7bdp CDC; 几何同 0x2C: W83/W84 = 每口 TX 帧数 / W85 = classify 总帧 / W86 = ch0 FIFO ovf / W87 = ch0 MAC TX; 未实现地址 0x190)"''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''  5  * 新增项落在**最上面**(MSB), 且槽号 <-> 字号的映射与 `p7bdp_din` / `ch0snap_din` 的
     显式 assign 一致 (P11 P1: 顶端 4 项是 ch0 束槽 3..0, 其下才是 p7bdp 槽 38..26)
  6  `p7bdp_din` 的驱动项数 = SNAP_P7BDP_NW (generate 12 项 + 显式 assign 6 项)''',
     r'''  5  * 新增项落在**最上面**(MSB), 且槽号 <-> 字号的映射与 `p7bdp_din` / `ch0snap_din` 的
     显式 assign 一致 (0x2D backstop-2: 顶端 2 项 = p7bdp 槽 40..39 = W84/W83; 其下 4 项是
     ch0 束槽 3..0, 再下才是 p7bdp 槽 38..26)
  6  `p7bdp_din` 的驱动项数 = SNAP_P7BDP_NW (generate 12 项 + 显式 assign 6 项)''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''    #      (din 侧仍是 `w87_dp..w83_dp`), 其下才是 P1 的 ch0 束 4 项 + p7bdp 槽 38..26 (13 项)。
    #   ⛔ P11 F-21 修复 (2026-10-18): 0x2C 的装配曾把顶端 5 项直连 `w8x_snap = w8x_dp`''',
     r'''    #      (din 侧仍是 `w87_dp..w83_dp`), 其下才是 P1 的 ch0 束 4 项 + p7bdp 槽 38..26 (13 项)。
    #   ⛔ 0x2D backstop-2 (2026-10-18): **W85/W86/W87 已删** ⇒ 顶端只剩 **W84/W83 = 槽 40..39**
    #      (din 侧 `w84_dp/w83_dp`); 下方 P1 的 4+13 项逐项未动。
    #   ⛔ P11 F-21 修复 (2026-10-18): 0x2C 的装配曾把顶端 5 项直连 `w8x_snap = w8x_dp`''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''    #      ⇒ 本判据的期望必须是 p7bdp 槽 43..39 (原写 `w%d_snap` = 0x2C 的缺陷形态, 已订正)。
    nnew_top = 22                             # W87..W66 (p7bdp 43..39 = 5 + ch0 槽 3..0 = 4 + p7bdp 38..26 = 13)
    np11_top = 5                              # 本轮新增的 p7bdp 槽 43..39 项数
    nch0_top = 4                              # 顶端 ch0 束项数 (= SNAP_CH0_NW, W82..W79)''',
     r'''    #      ⇒ 本判据的期望必须是 p7bdp 槽 43..39 (原写 `w%d_snap` = 0x2C 的缺陷形态, 已订正)。
    #   ⛔ 0x2D backstop-2 (2026-10-18): W85/W86/W87 已删 ⇒ 顶端只保留 **W84/W83**
    #      (p7bdp 槽 40..39 = 2 项); 其下仍是 P1 的 ch0 束 4 项 + p7bdp 槽 38..26 (13 项)
    #      ⇒ 顶端段合计 2 + 4 + 13 = **19 项** (原 22)。
    nnew_top = 19                             # W84..W66 (p7bdp 40..39 = 2 + ch0 槽 3..0 = 4 + p7bdp 38..26 = 13)
    np11_top = 2                              # 本轮保留的 p7bdp 槽 40..39 项数 (W84/W83)
    nch0_top = 4                              # 顶端 ch0 束项数 (= SNAP_CH0_NW, W82..W79)''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''    ck(topn == want_top,
       "5a 最上面 %d 项 = W%d..W%d 的 p7bdp 槽 %s + ch0 槽 %s + p7bdp 槽 %s (P11 F-21)"
       % (nnew_top, 87, 87 - np11_top + 1,
          "/".join("%d" % (pdp - 1 - i) for i in range(np11_top)),''',
     r'''    ck(topn == want_top,
       "5a 最上面 %d 项 = W%d..W%d 的 p7bdp 槽 %s + ch0 槽 %s + p7bdp 槽 %s (P11 F-21 / 0x2D backstop-2)"
       % (nnew_top, 84, 84 - np11_top + 1,
          "/".join("%d" % (pdp - 1 - i) for i in range(np11_top)),''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''           "(ch0snap_din 第 %d 项 = '%s', 期望 '%s')" % (din_idx, got[:40], src_name))
    # W83..W87: p7bdp 槽 39..43, RHS = 本轮新增的 5 条具名线
    for k, slot, src_name in ((83, 39, "w83_dp"), (84, 40, "w84_dp"),
                              (85, 41, "w85_dp"), (86, 42, "w86_dp"),
                              (87, 43, "w87_dp")):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+\:\s*32\]\s*=\s*%s\s*;" % (slot, src_name)''',
     r'''           "(ch0snap_din 第 %d 项 = '%s', 期望 '%s')" % (din_idx, got[:40], src_name))
    # W83/W84: p7bdp 槽 39/40, RHS = 两条具名线 (0x2D backstop-2 保留; W85..W87 已删, 不再断言)
    for k, slot, src_name in ((83, 39, "w83_dp"), (84, 40, "w84_dp")):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+\:\s*32\]\s*=\s*%s\s*;" % (slot, src_name)''', 1),
    ('_proj_10g/notes/p7b_biz_win/check_window.py',
     r'''        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+\:\s*32\]\s*=\s*%s\s*;" % (slot, src_name)
        ck(re.search(pat, src0) is not None, "5c 槽号映射 W%d (P11 P2-甲)" % k,
           "(p7bdp_din[%d*32 +: 32] = %s)" % (slot, src_name))''',
     r'''        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+\:\s*32\]\s*=\s*%s\s*;" % (slot, src_name)
        ck(re.search(pat, src0) is not None, "5c 槽号映射 W%d (P11 P2-甲 / 0x2D 保留)" % k,
           "(p7bdp_din[%d*32 +: 32] = %s)" % (slot, src_name))''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''    //   (另一半 = check_window.py 的装配静态核对)。
    localparam integer NW = 88;  // = wrapper 的 SNAP_NW_P6E (P11 P1; 原 76 = p9 孤儿修复 / 75 = P9 E12 / 71 = M1)
    // ⭐ p9 孤儿修复 (2026-10-17): MIR 地址**由 NW 派生** (不再写死; 每代自动跟随)''',
     r'''    //   (另一半 = check_window.py 的装配静态核对)。
    localparam integer NW = 85;  // = wrapper 的 SNAP_NW_P6E (0x2D backstop-2; 原 88 = 0x2D 首跑 / 83 = P11 P1 / 76 = p9 孤儿修复 / 75 = P9 E12 / 71 = M1)
    // ⭐ p9 孤儿修复 (2026-10-17): MIR 地址**由 NW 派生** (不再写死; 每代自动跟随)''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''    // ⭐ p9 孤儿修复 (2026-10-17): MIR 地址**由 NW 派生** (不再写死; 每代自动跟随)
    localparam [31:0] MIR_STATUS_A = 32'h20 + NW*4;       // 0x150 @NW=76 (快照末字后第一格; +16 是 UNIMPL)
    localparam [31:0] MIR_DATA_A   = MIR_STATUS_A + 4;    // 0x154
    localparam [31:0] MIR_CTRL_A   = MIR_STATUS_A + 8;    // 0x158
    localparam [31:0] MIR_DMA_A    = MIR_STATUS_A + 12;   // 0x15C
    localparam [31:0] UNIMPL_A     = MIR_STATUS_A + 16;   // 0x160
''',
     r'''    // ⭐ p9 孤儿修复 (2026-10-17): MIR 地址**由 NW 派生** (不再写死; 每代自动跟随)
    localparam [31:0] MIR_STATUS_A = 32'h20 + NW*4;       // 0x174 @NW=85 (快照末字后第一格; +16 是 UNIMPL)
    localparam [31:0] MIR_DATA_A   = MIR_STATUS_A + 4;    // 0x178
    localparam [31:0] MIR_CTRL_A   = MIR_STATUS_A + 8;    // 0x17C
    localparam [31:0] MIR_DMA_A    = MIR_STATUS_A + 12;   // 0x180
    localparam [31:0] UNIMPL_A     = MIR_STATUS_A + 16;   // 0x184
''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        axil_rd(32'h20 + (NW-1)*4, v, resp);
        chk("5a 末字 (0x20+4*(NW-1) = 0x138 @NW=71) 读得到", v, code_of(NW-1));
        chkresp("5b 末字 rresp = OKAY", resp, 2'b00);''',
     r'''        axil_rd(32'h20 + (NW-1)*4, v, resp);
        chk("5a 末字 (0x20+4*(NW-1) = 0x170 @NW=85) 读得到", v, code_of(NW-1));
        chkresp("5b 末字 rresp = OKAY", resp, 2'b00);''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        axil_rd(32'h20 + NW*4 + 16, v, resp);
        chk("6a 未实现地址 (0x20+4*NW+16 = 0x160 @NW=76) 回 0", v, 32'h0000_0000);
        chkresp("6b 未实现地址 rresp = SLVERR", resp, 2'b10);''',
     r'''        axil_rd(32'h20 + NW*4 + 16, v, resp);
        chk("6a 未实现地址 (0x20+4*NW+16 = 0x184 @NW=85) 回 0", v, 32'h0000_0000);
        chkresp("6b 未实现地址 rresp = SLVERR", resp, 2'b10);''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        chk("11g 写 0x3 后: capture_on==1 且 unf 已清", {v[18], v[16]}, 2'b10);
        // ---- 未实现地址边界 (期 B: 0x148 → 0x14C) ----
        axil_rd(UNIMPL_A, v, resp);''',
     r'''        chk("11g 写 0x3 后: capture_on==1 且 unf 已清", {v[18], v[16]}, 2'b10);
        // ---- 未实现地址边界 (0x2D backstop-2: @NW=85 ⇒ 0x184) ----
        axil_rd(UNIMPL_A, v, resp);''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        axil_rd(UNIMPL_A, v, resp);
        chk("11h 读 0x160 (未实现) 回 0", v, 32'h0000_0000);
        chkresp("11h2 读 0x160 rresp = SLVERR", resp, 2'b10);
        axil_wr(UNIMPL_A, 32'hDEAD_0000, 4'hF, resp);''',
     r'''        axil_rd(UNIMPL_A, v, resp);
        chk("11h 读 0x184 (未实现) 回 0", v, 32'h0000_0000);
        chkresp("11h2 读 0x184 rresp = SLVERR", resp, 2'b10);
        axil_wr(UNIMPL_A, 32'hDEAD_0000, 4'hF, resp);''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        axil_wr(UNIMPL_A, 32'hDEAD_0000, 4'hF, resp);
        chkresp("11i 写 0x160 = SLVERR (白名单仍只有 0x08/0x18/0x144)", resp, 2'b10);
        // ---- ⭐ 期 B: MIR_DMA_CNT (0x148) 的"地址↔值"映射 + bit3 (dma_en) 写读回 ----
        axil_rd(MIR_DMA_A, v, resp);''',
     r'''        axil_wr(UNIMPL_A, 32'hDEAD_0000, 4'hF, resp);
        chkresp("11i 写 0x184 = SLVERR (白名单仍只有 SCRATCH/TRIGGER/MIR_CTRL)", resp, 2'b10);
        // ---- ⭐ 期 B: MIR_DMA_CNT (0x2D backstop-2: @NW=85 ⇒ 0x180) 的"地址↔值"映射 + bit3 (dma_en) 写读回 ----
        axil_rd(MIR_DMA_A, v, resp);''', 1),
    ('_proj_10g/notes/p7b_biz_win/tb_biz_win.v',
     r'''        axil_rd(MIR_DMA_A, v, resp);
        chk("11j MIR_DMA_CNT @0x15C 读回 tie-off 常数 (地址映射对)", v, 32'hD0C0_015C);
        chkresp("11k MIR_DMA_CNT rresp = OKAY (它是**已实现**字)", resp, 2'b00);''',
     r'''        axil_rd(MIR_DMA_A, v, resp);
        chk("11j MIR_DMA_CNT @0x180 读回 tie-off 常数 (地址映射对)", v, 32'hD0C0_015C);
        chkresp("11k MIR_DMA_CNT rresp = OKAY (它是**已实现**字)", resp, 2'b00);''', 1),
    ('_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat',
     r'''REM run_tb_biz_win.bat -- P7B-BIZ per-word readback gate for the snapshot window
REM   DUT: _proj_pcie/rtl/axi_regs.v with SNAP_NW=83 (the wrapper's SNAP_NW_P6E;
REM        76 = p9 orphan fix / 75 = P9 E12 / 71 = M1 were earlier generations).
REM   TB : _proj_10g/notes/p7b_biz_win/tb_biz_win.v''',
     r'''REM run_tb_biz_win.bat -- P7B-BIZ per-word readback gate for the snapshot window
REM   DUT: _proj_pcie/rtl/axi_regs.v with SNAP_NW=85 (the wrapper's SNAP_NW_P6E;
REM        88 = 0x2D first run / 83 = P11 P1 / 76 = p9 orphan fix / 75 = P9 E12 / 71 = M1
REM        were earlier generations).
REM   TB : _proj_10g/notes/p7b_biz_win/tb_biz_win.v''', 1),
    ('_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat',
     r'''REM   (P7B-WU round) => like its sibling (run_xvlog_wrapper.bat) this gate was DEAD (exit 92).
findstr /C:"SNAP_NW_P6E = 88" "%ROOT%\board\wrapper_p4.v" >NUL || ( echo [FINGERPRINT FAIL] wrapper is not 83-word & exit /b 92 )
''',
     r'''REM   (P7B-WU round) => like its sibling (run_xvlog_wrapper.bat) this gate was DEAD (exit 92).
REM 2026-10-18 (0x2D backstop-2): fingerprint 88 -> 85 (W85..W87 deleted).
findstr /C:"SNAP_NW_P6E = 85" "%ROOT%\board\wrapper_p4.v" >NUL || ( echo [FINGERPRINT FAIL] wrapper is not 85-word & exit /b 92 )
''', 1),
    ('_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat',
     r'''REM   only the expected value is bumped.
findstr /C:"SNAP_NW_P6E = 88" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 83-word version & exit /b 92 )
''',
     r'''REM   only the expected value is bumped.
findstr /C:"SNAP_NW_P6E = 85" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 85-word version & exit /b 92 )
''', 1),
    ('sim/p5wu_p1p2/run_xvlog_wrapper63.bat',
     r'''set TXF=%ROOT%\rtl\tcp_tx_frame.v
findstr /C:"SNAP_NW_P6E = 88" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 76-word version & exit /b 92 )
if not exist "%TXF%" ( echo [PATHGUARD FAIL] no rtl\tcp_tx_frame.v under %ROOT% & exit /b 93 )''',
     r'''set TXF=%ROOT%\rtl\tcp_tx_frame.v
findstr /C:"SNAP_NW_P6E = 85" "%SRCFILE%" >NUL || ( echo [FINGERPRINT FAIL] source is not the 85-word version & exit /b 92 )
if not exist "%TXF%" ( echo [PATHGUARD FAIL] no rtl\tcp_tx_frame.v under %ROOT% & exit /b 93 )''', 1),
    ('_proj_10g/p7b_chain/sim/tb_p7b_chain.v',
     r'''        u_dut.u_pcie_xdma.axil_read(32'h168, v); chk("P1 W82 ch0 drop",   v === 32'hA5A50082, "forced mac_rx_ch0.stat_drop");
        // ---- P11 P2-甲: 几何 88 字 / 非 DUAL tie-off (N-10) ----
        u_dut.u_pcie_xdma.axil_read(32'h16C, v);''',
     r'''        u_dut.u_pcie_xdma.axil_read(32'h168, v); chk("P1 W82 ch0 drop",   v === 32'hA5A50082, "forced mac_rx_ch0.stat_drop");
        // ---- P11 P2-甲: 几何 85 字 (0x2D backstop-2) / 非 DUAL tie-off (N-10) ----
        //   ⛔ 0x2D backstop-2 (2026-10-18): W85/W86/W87 已删, 顶端只保留 W84/W83;
        //      MIR 四字 = 0x174/0x178/0x17C/0x180; 未实现地址 = 0x184。
        u_dut.u_pcie_xdma.axil_read(32'h16C, v);''', 1),
    ('_proj_10g/p7b_chain/sim/tb_p7b_chain.v',
     r'''        chk("P11 W84 TX port1 frames = 0 (non-DUAL tie-off)", v === 32'h00000000, "W84 @0x170");
        u_dut.u_pcie_xdma.axil_read(32'h174, v);
        chk("P11 W85 classify total frames", v === (u_dut.cls_stat_fast + u_dut.cls_stat_slow),
            "W85 = (fast+slow)[31:0] (真源, 两种构建都在)");
        u_dut.u_pcie_xdma.axil_read(32'h178, v);
        chk("P11 W86 ch0 FIFO ovf = 0 (non-DUAL tie-off)", v === 32'h00000000, "W86 @0x178");
        u_dut.u_pcie_xdma.axil_read(32'h17C, v);
        chk("P11 W87 ch0 MAC TX = 0 (non-DUAL tie-off)", v === 32'h00000000, "W87 @0x17C");
        u_dut.u_pcie_xdma.axil_read(32'h180, v); chk("P11 MIR_STATUS @0x180", v[22:19] === 4'd4, "MIR block auto-shifted by SNAP_NW=88");
        u_dut.u_pcie_xdma.axil_read(32'h190, v);
        chk("7b 0x190 reads 0 no wrap",
            (v === 32'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2'd2),''',
     r'''        chk("P11 W84 TX port1 frames = 0 (non-DUAL tie-off)", v === 32'h00000000, "W84 @0x170");
        u_dut.u_pcie_xdma.axil_read(32'h174, v); chk("P11 MIR_STATUS @0x174", v[22:19] === 4'd4, "MIR block auto-shifted by SNAP_NW=85");
        u_dut.u_pcie_xdma.axil_read(32'h184, v);
        chk("7b 0x184 reads 0 no wrap",
            (v === 32'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2'd2),''', 1),
    ('_proj_10g/p7b_chain/sim/tb_p7b_chain.v',
     r'''            (v === 32'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2'd2),
            "axi_regs decode; 88-word bound (P11 2026-10-18: 0x190 = 0x20+4*88+16; 原 83 字/0x17C)");
''',
     r'''            (v === 32'h00000000) && (u_dut.u_pcie_xdma.last_rresp === 2'd2),
            "axi_regs decode; 85-word bound (0x2D backstop-2: 0x184 = 0x20+4*85+16; 原 88 字/0x190)");
''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''# -*- coding: utf-8 -*-
"""check_snap_top5_wired.py — P11 F-21 静态结构门 (源码面).
''',
     r'''# -*- coding: utf-8 -*-
"""check_snap_top5_wired.py — P11 F-21 静态结构门 (源码面; 0x2D backstop-2 = TOPN 2).
''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''  `p7bdp_din[39..43]` 成死逻辑 (布后 `u_snap_p7bdp/hold_b_reg` 槽 39..43
  = 0 个寄存器)。修法 = 顶部 5 项只读 `p7bdp_dout[43..39]` ⇒ 必须经过
  `snap_cdc` 的 hold_b 相干锁存。''',
     r'''  `p7bdp_din[39..43]` 成死逻辑 (布后 `u_snap_p7bdp/hold_b_reg` 槽 39..43
  = 0 个寄存器)。修法 = 顶部项只读 `p7bdp_dout[...]` ⇒ 必须经过
  `snap_cdc` 的 hold_b 相干锁存。''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''
本脚本断言 (全部为**源码结构**, 不依赖综合/布局):''',
     r'''
⭐ 0x2D backstop-2 (2026-10-18): W85/W86/W87 已从快照删除 ⇒ 顶端只剩
  **TOPN = 2** 项 (W84/W83 = p7bdp 槽 40/39)。本门随之把期望从 43..39 收窄到
  40..39; 旧的 5 项 (88 字) 形态会因第 3 项不是 ch0 束而**红** (负控仍有牙)。

本脚本断言 (全部为**源码结构**, 不依赖综合/布局):''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''本脚本断言 (全部为**源码结构**, 不依赖综合/布局):
  1. `snap_dout_all` 顶部 5 项 = `p7bdp_dout[43..39]` (顺序 43,42,41,40,39);
  2. 源码 (去注释后) 无 `w8x_snap` 线, 也无 `assign w8x_snap = w8x_dp` 直连;''',
     r'''本脚本断言 (全部为**源码结构**, 不依赖综合/布局):
  1. `snap_dout_all` 顶部 TOPN=2 项 = `p7bdp_dout[40..39]` (顺序 40,39);
  2. 源码 (去注释后) 无 `w8x_snap` 线, 也无 `assign w8x_snap = w8x_dp` 直连;''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''  2. 源码 (去注释后) 无 `w8x_snap` 线, 也无 `assign w8x_snap = w8x_dp` 直连;
  3. 输入侧仍完整: `p7bdp_din[39..43] = w83_dp..w87_dp` (5 条);
  4. N-10 语义仍在: 两处非 DUAL 分支的 `w83_dp..w87_dp` 常量 tie-off
     (W85 仍真) —— 只做存在性断言, 不解释 ifdef 组合。
''',
     r'''  2. 源码 (去注释后) 无 `w8x_snap` 线, 也无 `assign w8x_snap = w8x_dp` 直连;
  3. 输入侧仍完整: `p7bdp_din[39..40] = w83_dp/w84_dp` (2 条);
  4. N-10 语义仍在: 两处非 DUAL 分支的 `w83_dp/w84_dp` 常量 tie-off
     (各 2 处 = 32'd0) —— 只做存在性断言, 不解释 ifdef 组合。
''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''
ITEMS_WANT = ["p7bdp_dout[43*32 +: 32]", "p7bdp_dout[42*32 +: 32]",
              "p7bdp_dout[41*32 +: 32]", "p7bdp_dout[40*32 +: 32]",
              "p7bdp_dout[39*32 +: 32]"]
''',
     r'''
TOPN = 2                     # 0x2D backstop-2: W84/W83 (p7bdp 槽 40/39)
ITEMS_WANT = ["p7bdp_dout[40*32 +: 32]", "p7bdp_dout[39*32 +: 32]"]
''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''
    # 1) 顶部 5 项
    try:''',
     r'''
    # 1) 顶部 TOPN 项
    try:''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''        return 1
    got = items[:5]
    ok1 = got == ITEMS_WANT''',
     r'''        return 1
    got = items[:TOPN]
    ok1 = got == ITEMS_WANT''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''    ok1 = got == ITEMS_WANT
    print("%s [1] snap_dout_all 顶部 5 项 = %s" % ("[ok]" if ok1 else "[FAIL]", got))
    if not ok1:''',
     r'''    ok1 = got == ITEMS_WANT
    print("%s [1] snap_dout_all 顶部 %d 项 = %s" % ("[ok]" if ok1 else "[FAIL]", TOPN, got))
    if not ok1:''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''        print("      期望 = %s" % ITEMS_WANT)
        fails.append("top5")
''',
     r'''        print("      期望 = %s" % ITEMS_WANT)
        fails.append("top%d" % TOPN)
''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''
    # 3) p7bdp_din[39..43] = w83_dp..w87_dp
    miss = []''',
     r'''
    # 3) p7bdp_din[39..40] = w83_dp/w84_dp
    miss = []''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''    miss = []
    for slot in range(39, 44):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+:\s*32\]\s*=\s*w%d_dp\s*;" % (slot, slot + 44)''',
     r'''    miss = []
    for slot in range(39, 39 + TOPN):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+:\s*32\]\s*=\s*w%d_dp\s*;" % (slot, slot + 44)''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''    ok3 = not miss
    print("%s [3] p7bdp_din[39..43] = w83_dp..w87_dp (缺 %s)"
          % ("[ok]" if ok3 else "[FAIL]", miss if miss else "无"))
    if not ok3:''',
     r'''    ok3 = not miss
    print("%s [3] p7bdp_din[39..%d] = w83_dp/w84_dp (缺 %s)"
          % ("[ok]" if ok3 else "[FAIL]", 38 + TOPN, miss if miss else "无"))
    if not ok3:''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''
    # 4) N-10 tie-off 存在性 (非 DUAL 两支: w83/w84/w86/w87 = 0; w85 真)
    zero_hits = {k: len(re.findall(r"wire\s*\[31:0\]\s+w%d_dp\s*=\s*32'd0\s*;" % k, code))''',
     r'''
    # 4) N-10 tie-off 存在性 (非 DUAL 两支: w83/w84 = 0; W85..W87 已删, 不再检查)
    zero_hits = {k: len(re.findall(r"wire\s*\[31:0\]\s+w%d_dp\s*=\s*32'd0\s*;" % k, code))''', 1),
    ('_proj_10g/p7b_chain/sim/check_snap_top5_wired.py',
     r'''    zero_hits = {k: len(re.findall(r"wire\s*\[31:0\]\s+w%d_dp\s*=\s*32'd0\s*;" % k, code))
                 for k in (83, 84, 86, 87)}
    w85_hits = len(re.findall(
        r"wire\s*\[31:0\]\s+w85_dp\s*=\s*\(\{1'b0,\s*cls_stat_fast\}\s*\+\s*\{1'b0,\s*cls_stat_slow\}\)\s*;",
        code))
    # 两处非 DUAL 分支 (DUAL+非 APP_MODE 的内层 else + 非 DUAL 的外层 else) ⇒ 常量 0 各 2 次;
    # W85 为真值有 **3** 处 (DUAL+APP_MODE / 内层 else / 外层 else)。
    ok4 = all(v == 2 for v in zero_hits.values()) and w85_hits == 3
    print("%s [4] N-10 tie-off: zero_hits=%s w85_true_hits=%d (期望 2/2/2/2 与 3)"
          % ("[ok]" if ok4 else "[FAIL]", zero_hits, w85_hits))
    if not ok4:''',
     r'''    zero_hits = {k: len(re.findall(r"wire\s*\[31:0\]\s+w%d_dp\s*=\s*32'd0\s*;" % k, code))
                 for k in (83, 84)}
    # 两处非 DUAL 分支 (DUAL+非 APP_MODE 的内层 else + 非 DUAL 的外层 else) ⇒ 常量 0 各 2 次。
    ok4 = all(v == 2 for v in zero_hits.values())
    print("%s [4] N-10 tie-off: zero_hits=%s (期望 83/84 各 2)"
          % ("[ok]" if ok4 else "[FAIL]", zero_hits))
    if not ok4:''', 1),
    ('sim/p6e_pcie/tb_p6e_pcie_wrapper.v',
     r'''        //    ⚠️ 红线不变 (7 位译码 ⇒ 绝不能挑 ≥0x200)。
        u_dut.u_pcie_xdma.axil_read(32'h190, v);
        chk("9  unimpl 0x190 => rresp=SLVERR", {30'd0, u_dut.u_pcie_xdma.last_rresp}, 32'd2);
''',
     r'''        //    ⚠️ 红线不变 (7 位译码 ⇒ 绝不能挑 ≥0x200)。
        u_dut.u_pcie_xdma.axil_read(32'h184, v);
        chk("9  unimpl 0x184 => rresp=SLVERR", {30'd0, u_dut.u_pcie_xdma.last_rresp}, 32'd2);
''', 1),
    ('sim/p6e_pcie/tb_p6e_pcie_wrapper.v',
     r'''        //        (历史: 期 A 0x13C → 期 B 0x14C → **P9 E12 0x15C**)
        u_dut.u_pcie_xdma.axil_read(32'h190, v);
        chk("M1-5a 0x190 rresp = SLVERR", {30'd0, u_dut.u_pcie_xdma.last_rresp}, 32'd2);
        u_dut.u_pcie_xdma.axil_read(32'h16C, v);''',
     r'''        //        (历史: 期 A 0x13C → 期 B 0x14C → **P9 E12 0x15C**)
        u_dut.u_pcie_xdma.axil_read(32'h184, v);
        chk("M1-5a 0x184 rresp = SLVERR", {30'd0, u_dut.u_pcie_xdma.last_rresp}, 32'd2);
        u_dut.u_pcie_xdma.axil_read(32'h16C, v);''', 1),