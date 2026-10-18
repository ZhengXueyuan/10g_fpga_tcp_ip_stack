# P11 · P2-甲 实施轮 红队审查 FINDINGS

> **TL 代落（2026-10-18 11:0x）**：本件 = 实施红队审查 agent 的完整 FINDINGS 原文（平台拒写 `.md`），由 TL 转录；未改结论。TL 抽核见文末 §TL 抽核。

审查对象：`967e974e`（81 files +4461/−201，工作树与 HEAD 一致，无未提交已跟踪改动）。核心 RTL 主链（N-6、三 producer 选口、RX merge、slow 源 IP 提取、HLS 双 IP）**未发现会静默错的实现缺陷**；但发现 **1 个板级轮硬阻断（读侧链未同步）**、**1 个新跨口死锁风险**、**1 个门无牙（maccnt 只有"无混合值"、无活性）**，以及多处设计件/报告与实物不符。

---

## 一、分级 FINDINGS

### 【高】F-1 读侧 0x2C 链未同步：J6/TCPREG 台架在新位流上必然 `J6_GEOM_FAIL`，gate4 夹具会假红/拒跑
- **事实**：
  - `_proj_10g/notes/p7b_affinity/j6_r6fix.sh:81-104` 的 `GEOM_TIERS` **没有 `88|0x0000002C` 档**（顶端仍是 `"83|0x0000002B|..."`，见 `:82`）；`_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh:76-99` 同。默认值已改 `NW=88 / EXPECT_BID=0x2C`（`j6:75-76`、`tcpreg:69-70`），但档表没加 ⇒ 循环匹配不到 ⇒ `:114-121` 走 `J6_GEOM_FAIL … exit 3`。
  - `_proj_pcie/p7b_gate4_accept.sh:131/:137` 仍 `EXPECT_BID=…0x2B / SNAP_WORDS=…83`；`_proj_pcie/p7b_gate4_selftest.sh:37/:217` 仍 83/0x2B；`_proj_pcie/p7b_gate4_livefake.sh:146` 仍 `{83:"0x0000002B",…}.get(nw,"0x0000002B")`；`_proj_10g/notes/p7b_gate4_3/final_state.sh:33` 仍 0x2B；`_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py:57-58` 仍 `NW_FIX=83 / BID_FIX=0x2B`（其 `:76` 的几何门会 `exit 3` + 零文件）。
  - `_proj_pcie/p7b_gate4_negctrl.sh` **内部自相矛盾**：`:74` 造 `BID 0x0000002B`、`:80` `for i<83` 只造 83 字，而 `:156` 的 `shift1` 已用 `awk -v NW=88`。
  - 设计件 N-5 只列了 4 个文件（`DESIGN_v2r1.md:724-739`），而 `apply_readside_bid1c.py` 自己的 `DEFAULT_SPECS`（`:2540-2575`）**断言上述全部文件**（含 `TIER_TOP`：档表第一行必须是现役档）。TL 抽核 #8 只核了 `NW/EXPECT_BID` 两行，**没有核"几何表"**，而设计 N-5 原文对这两个文件写的是"`NW=88 / EXPECT_BID=0x2C` / **几何表**"。
- **后果**：板级轮一旦用 `j6_r6fix.sh`/`tcpreg_j6.sh` 取 W51..W55，会在**入口身份门 exit 3**（响亮但阻断）；gate4 夹具按 0x2B/83 造数 ⇒ 对 0x2C 板是假红或直接拒绝运行。若有人把 `p7b_gate4_negctrl.sh` 当负对照跑，BID 与 NW 不一致会让"反例红"变成"身份假红"，负对照无判别力。
- **建议修法**：① 两个台架 `GEOM_TIERS` 顶端插入 `"88|0x0000002C|61 62|P11 P2-甲 双口+双 IP (88 字 / BID 0x2C; W83..W87 = TX 双口帧数/classify 总帧/ch0 FIFO ovf/ch0 MAC TX; 未实现地址 0x190)"`；② 6 个 gate4/夹具文件全部 88/0x2C 同步（`p7b_gate4_negctrl.sh` 的 `:74/:80` 必须与 `:156` 同代）；③ 跑一次 `apply_readside_bid1c.py --bid 0x2C --assert`（当前磁盘状态下它会在上述文件报 FAIL）。
- **判据/门**：`apply_readside_bid1c.py --assert`（含 `assert_tables(88)`/`assert_defaults(0x2C)`，其中 `TIER_TOP` 覆盖 j6/tcpreg）+ `j6_r6fix.sh`/`tcpreg_j6.sh` 在缺省值下 `J6_GEOM_OK NW=88 BID=0x2C`。

### 【高】F-2 `rx_merge2` 无半帧看门狗：任一口停钟/复位导致"无 tlast 的半帧"会把**另一口 RX 一起永久锁死**
- **事实**：`rtl/rx_merge2.v:60-111` 的 `busy` 只在 `m_tvalid && m_tready && m_tlast` 释放（`:86/:97-99`），**没有超时/中止路径**；`busy` 期间只服务 `sel` 口（`:75-76`），另一口 `tready=0`。上游 `mac_rx_10g` 只在"有新 /S/ 碎片"或"FIFO 满"时产生 `TERM`（`_proj_10g/p7b_mac/rtl/mac_rx_10g.v:353-374`，`push_keep=0/push_last=1`）；**若链路断开/`rx_clk_out_0` 停钟、或 PCS `user_rx_reset_0` 使 MAC 中途复位**，已推入 `u_rxcdc_ch0` 的半帧没有后续字、也没有 TERM，merge 的 `sel_tvalid` 变 0 后 `busy` 永久为 1 ⇒ ch1（现役口）也再不被服务。P1 已把 S-4/S-5（LOS/停钟）登记为**未测**（`p9_board_p1_20261018` §3-4/5）。
- **后果**：单口物理链路抖动/拔插可能造成**整块 RX 数据面静默停摆**（W0/W79 同时不动，W83/W84 仍可能动 ⇒ 误判成"流量停了"）；只能重烧/复位恢复。这是 P2 相对 P1 新引入的跨口耦合后果，设计件 §3.2/§6.3 未登记。
- **建议修法**：在 `rx_merge2` 加"`busy && !sel_tvalid` 持续 N 拍（N ≥ 一个最大帧的拍数，如 4096）⇒ 释放 `busy`、`stat_abort++`、不产生帧计数"的看门狗；或用 head 的 `tuser`(SOP) 门 + 超时组合。若选择不修，必须在设计件/板级前置里显式登记"停钟楔死 + 只能复位恢复"，并加板级负对照（拉 LOS/断钟后另一口仍可收）。
- **判据/门**：G2 新增臂——p1 注入 1 帧但**不发 tlast**，保持 ≥N 拍，断言 `stat_abort` 增且 p0 的帧在 ≤N+帧长 拍内仍能出来。

### 【高】F-3 maccnt_sync 门无活性：`dst_val` 恒 0/恒 0xFF 也能 PASS，W86 高半/W87 可能是死仪表
- **事实**：`_proj_10g/p11_dual/sim/tb_p11_dual.v:294-325` 的臂 C 只统计 `good_dst !== 0 && good_dst !== 0xFF`（`:297`）与裸 2FF 的混合值（`:298`）。**没有**设计 N-4 明文要求的两条：`"源域计数 +1 → 目的域在 ≤N 拍后 dst_val+1"` 与 `"源域停在常值 → 目的域不重复增加"`（`DESIGN_v2r1.md:494`、`:718` G6 行）。源激励恰好在 0x00/0xFF 之间来回，因此 `dst_val` 若被卡在 0（或 0xFF，或根本没有更新），`good_bad` 恒 0 ⇒ 门绿。
- **后果**：W86[31:16]（ch0 RX FIFO ovf）与 W87（ch0 MAC TX）在板上可能恒 0/恒 0xFFFF 而所有门全绿；P2-2 的 ch0 对账会读到一个恒常量，判据静默失效。
- **建议修法**：臂 C 改为**斜坡计数**（0..N 单调，不是 00/FF 跳变），断言 `dst_val` 在 ≤32 个 dst 拍内追到某个中间值的**精确值**；再令 `src_val` 冻结 ≥100 拍，断言 `dst_val` 不重复变化/不递增；保留逐位错开的裸 2FF 负控。
- **判据/门**：G6 臂 C 的终止行（新增两条断言名），并附一次"`maccnt` 输出被强制常 0 ⇒ 门必红"的变异。

### 【中】F-4 W86/W87 类"ovf"计数器语义是"AXIS 反压拍数"，不是"丢字数"；设计件"应恒 0 / 可作修正项"不成立
- **事实**：`rtl/fifo_async.v:184,191` 的 `ovf_pulse_w = wr_en && full_r`；而 wrapper 的 `wr_en` 是**原始 tvalid**（`board/wrapper_p4.v:1084` `wr_en(ch0_rx_tvalid)`、`:3331` `wr_en(txsrc1_tvalid)`），`tready` 只是 `~full`（`:1039`、`:3339`）。AXIS 生产者在 `tready=0` 时**保持 tvalid 不变**（`mac_rx_10g.v:507` `tvalid=!empty`；`tcp_tx_frame`/arb 同理）⇒ 每一拍"有字但 full"都 +1，**而该字并未丢失**（下拍仍会重试）。设计件 §3.4 的"`u_rxcdc_ch0.ovf_cnt` 在 tready 门控下**应恒 0**（只作安全网）"（`DESIGN_v2r1.md:424`）与 P2-2 把 `sat16(ch0_txcdc_ovf)` 当"字级修正项"（`:697`）都与该语义不符。
- **后果**：ch0 只要有正常反压，W86 低 16 位几毫秒内饱和到 0xFFFF；P2-2 的 `ΔW84 − Δpeer_p0 ≤ sat16(ovf)+abort+33` 变成恒真的松上界 ⇒ **ch0 对账无判别力**；W86 高半也不可能"恒 0"。不会改变硬件行为，但会让板级判据静默失效（"绿在松判据"）。
- **建议修法**：把这类计数器改名为 `*_stall_cycles`，板级修正项改用"MAC `stat_drop`（W82/W4）+ txcdc 占用峰值"或新增"真正的丢字计数"（只有当生产者在 full 时**放弃**该字才 +1，本设计里不存在）；或在 P2-2 里删掉该项、改用"取窗前静默 + `INFLIGHT_MAX_FRAMES`"并把 W86 只当健康指示。
- **判据/门**：板级 B-6：ch0 单独灌流时 `ΔW86[15:0]` 与该口反压拍数对照（应相等，证明它是拍数不是丢字）；同时用"故意制造 MAC 丢帧"的负对照看 W82 是否动。

### 【中】F-5 `apply_readside_bid1c.py` 的 0x2C 阶段不可重放、且会改错历史注释；`--rehearse` 未演练的实际风险被低估
- **事实**：`_to_2c()`（`apply_readside_bid1c.py:693-727`）把 EDITS_2B 的新侧文本机械替换：`'P11 P1'→'P11 P2-甲'`、`'0x17C'→'0x190'`、`'83 字'→'88 字'` 等。对 EDITS_2B 的 UNIMPL 注释（`:526/:541/:559` 的 `'# 83 ⇒ 0x17C (P11 P1 起; 76 ⇒ 0x160 …'`）会生成 **`'# 83 ⇒ 0x190 (P11 P2-甲 起; …'`**（83 字 ≠ 0x190），即改写 P1 历史事实；而**磁盘上实际是手写的正确两代注释**（`_proj_pcie/p6e_snap_check.sh:73`、`p7b_snap.sh:88` 均保留 `83 ⇒ 0x17C (P11 P1)`，并另有 P2-甲 行）。EDITS_2C 也没有生成磁盘上新增的 P2-甲 表头/标签行（如 `p7b_snap.sh:5/:187`、`p6e_snap_check.sh:382-386` 的部分注释）。
- **后果**：① 从 0x2B 树重放 `--bid 0x2C` 会得到与现磁盘不同的文本（历史注释被改错），违反 N-5"0x2C 阶段不得改历史注释的逐字原文"；② "单一来源/链式同步"的可重放保证不成立（现在磁盘是手改+脚本，两者不一致）；③ 从未真正 `--rehearse`，`assert_tables/assert_defaults` 的 0x2C 面没有一次执行证据。
- **建议修法**：二选一——(a) 把 0x2C 阶段的 EDITS 改成与磁盘逐字一致的**显式增量**（不要用 `_to_2c` 机械替换），并加 `--bid 0x2C --assert` 的 CI 门；(b) 先把哨兵重置到 0x2B，在 worktree 里 `--rehearse --bid 0x2C` 一次，按差异修 `_to_2c`，再归档排练日志。
- **判据/门**：`apply_readside_bid1c.py --bid 0x2C --rehearse` 的逐文件 diff 为空 + `--assert` 全 OK。

### 【中】F-6 构建 tcl 缺设计要求的两个硬门：HLS 源/网表哈希归档、synth 日志 `black box`/`8-3491` 0 命中
- **事实**：`board/build_p7b_ku5p.tcl` 无 `HLS_SRC_HASH`/`HLS_NET_HASH`（全文件 grep 无 HASH/sha256/md5），而 `DESIGN_v2r1.md:745/:766` 明确要求记双哈希；模块解析只做 `IS_BLACKBOX`（`:307-321`），**没有** synth run 日志的 `black box`/`8-3491` grep，而 N-3 原文写"**这条日志 grep 才是硬门**；不得只凭 n≥1 判已解析"。TL 抽核已点名，但它是构建脚本级缺陷，不是"说明性债务"。
- **后果**：HLS 网表被换/没换无法从构建归档追溯；`IS_BLACKBOX` 若在 2025.2 对某形态不生效（或模块被优化成黑盒但 `get_cells` 找不到），构建会安静出位流。
- **建议修法**：构建脚本内 `file hash`/`sha256sum` 记 `HLS_SRC_HASH`（hls/src + run_hls.tcl）与 `HLS_NET_HASH`（slowstack_prj/.../verilog/*.v+.dat）；synth 后 `grep` run log（`synth_1/runme.log`）`black box|8-3491` 必须 0，否则 `exit 1`；两者都写进构建报告。
- **判据/门**：构建报告含 `HLS_SRC_HASH=`/`HLS_NET_HASH=` 行；`P7B_BLACKBOX_LOG_HITS=0`。

### 【中】F-7 H-1 的"新端口无 Z"断言未实现
- **事实**：设计 G1 要求 `findstr "peer_my_ip" | findstr "VRFC 10-3645"` 为空 + 运行时 `$isunknown`（`DESIGN_v2r1.md:713`）。实施轮的门脚本/矩阵里**没有**这两个断言（`grep -rn "10-3645\|isunknown\|peer_my_ip" sim/p4gates/ _proj_10g/p11_dual/sim/*.bat` 只命中 `implicit_gate.bat` 的注释与无关文件）。当前 9 个 active 例化点确实都接了常量（`tb_app_udp.v:316`、`tb_app_udp_rate.v:165`；其余 7 点只走参数、无新端口），所以**当前无 Z**，但门不在。
- **后果**：未来新增/复制 TB 漏接 `peer_my_ip` 时会得到 Z，`cfg_sync` 变 X ⇒ `deny` X ⇒ 该 TB 的 TX 全灭，且现有门不报"未接"（10-3645 是 xelab warning，矩阵未对它做定向断言；项目自己的笔记还明确说裸 10-3645 有大量良性命中，必须定向查）。
- **建议修法**：在 G1 或 G5 的 bat 里加 `findstr /C:"peer_my_ip" xelab.log | findstr /C:"VRFC 10-3645"` 为空的定向门；并在 `tb_app_udp` 加 `$isunknown(u_cfg.o_port)` / `$isunknown(u_cfg.cfg_sync)` 的运行期断言。
- **判据/门**：上述两个断言行的 PASS 行。

### 【中】F-8 非 DUAL 构建引入 3 个隐式网（`rx_p0_tvalid`、`tx_p0_frames`、`tx_p1_frames`），而项目"隐式网 5 键"门抓不到
- **事实**：
  - `rx_p0_tvalid` 声明在 `` `ifdef DUAL_SFP_A `` 内（`wrapper_p4.v:938-945`），却在 DP 分支**无条件**赋值 `:1156 assign rx_p0_tvalid = ~rx_fifo_empty;` 并在 `:1158`（`ifndef DUAL`）使用 ⇒ 非 DUAL 构建里是**隐式 1 位网**（功能上恰好正确，因为就是 1 位）。
  - `tx_p0_frames`/`tx_p1_frames` 声明在 DUAL 内（`:2976`），非 DUAL 分支 `:3357-3359` 对其赋 `32'd0` ⇒ 隐式 **1 位**网接收 32 位常量（截断，本分支无消费者，功能无害）。
  - 矩阵的隐式门键是 `VRFC 10-2989`/`8-11241`/`10-3091 1位`/`8-36`（`run_tb_p11_dual.bat`/`run_elab_4combo.bat`），对"连续赋值给未声明网的 1 位/截断"**结构上不触发**；矩阵 24/24 全绿即为证据。
- **后果**：当前无功能影响（`rx_p0_tvalid` 1 位正确；`tx_p0_frames` 分支无用），但违反坑 24 的硬规则；将来有人把 `rx_p0_tvalid` 改成多位、或把 `tx_p0_frames` 接到快照，就是**静默截断**。这是"门盲"而非本刀功能错。
- **建议修法**：把 `rx_p0_tvalid` 声明移出 `ifdef DUAL_SFP_A`（或非 DUAL 分支改 `assign rx_tvalid = ~rx_fifo_empty;` 不经过它）；`tx_p0_frames/tx_p1_frames` 声明移出 DUAL 或非 DUAL 分支删除赋值；并把"连续赋值目标未声明"加入隐式门（xelab 前后加 `default_nettype none` 的 lint 编译是最便宜的自检）。
- **判据/门**：非 DUAL 的 elaborat/综合日志 `default_nettype` 相关 0 命中，或 `grep -n "rx_p0_tvalid" wrapper` 的声明在 ifdef 外。

### 【中】F-9 G7/G6 都没有编"真实构建宏组合"（DUAL + SFP2_MODE_A）
- **事实**：真实构建 9 宏 = `APP_MODE DEV_USP PCIE_OBS DP_156MHZ P7B_10G UDP_TX_OVL TCP_TX_OVL SFP2_MODE_A DUAL_SFP_A`（`build_p7b_ku5p.tcl:286`）。G7 的 DUAL 正控 `c8 = B P7P PCS DU`（`run_elab_4combo.bat:57`）**不含 `S0=-d SFP2_MODE_A`**；G6 的 DEFS（`run_tb_p11_dual.bat:12`）也不含 `SFP2_MODE_A`。⇒ 组合 `DUAL+SFP2_MODE_A`（唯一会烧的组合）**一次都没有 elaborate/仿真过**。
- **后果**：若 `SFP2_MODE_A_DEF` 与 DUAL 有编译期交互（哪怕只是 W78[31] 常量），门看不到；构建轮才会第一次编它。设计 G7 原文写"c8 = DUAL+P7B+A+DP+APP 正控"，这里的 A 有歧义（APP_MODE 还是 SFP2_MODE_A）——**设计件本身没把"构建组合"钉死**。
- **建议修法**：把 c8 改为 `%B% %P7% %PCS% %S0% %DU%`（= 真构建组合），另保留一个去掉 `SFP2_MODE_A` 的 DUAL 正控；G6 的 DEFS 加 `-d SFP2_MODE_A` 重跑一次（或明确登记"G6 不覆盖 SFP2_MODE_A"）。
- **判据/门**：elab 输出新增 `[ELAB c13] ... %S0% %DU% OK`；G6 日志头部 DEFS 含 SFP2_MODE_A。

### 【中】F-10 归档的 `gates/g5_run.log` 是**全红旧跑**（`SRCIP_GATE_FAIL`），与报告结论矛盾且无任何标注
- **事实**：`gates/g5_run.log` 内容 = 三臂全 FAIL（`SRCIP ovl UNEXPECTED-PASS` / `def UNEXPECTED-PASS` / `mut UNEXPECTED-PASS`）+ `SRCIP_GATE_FAIL`；而同目录 `xsim_ovl.log`/`xsim_def.log`/`xsim_mut.log`（08:24:55–08:25:03）是 PASS/PASS/FAIL，矩阵日志 `:310` 也是 `SRCIP_GATE_PASS`。`g5_run.log` 在 sim 目录的 mtime 是 08:14（早于最终跑），是**被后续跑取代的失败件**，但被原样复制进 `gates/` 存档、报告/§4 没有解释这次全红的原因（哪个 bat/TB 缺陷修的、改了什么）。
- **后果**：任何按"gates/ 是门原始日志"读的外部复核者会得到与报告相反的 G5 结论；更危险的是它提示 G5 的 bat 曾把三臂都跑成红（疑似当时三臂都用了 mutant 或 TB 期望错），而这个"修复"没有被记录，无法判断最终绿是"门修好了"还是"判据放宽了"。
- **建议修法**：删除或重命名为 `g5_run.SUPERSEDED_fail_0814.log` 并写明"已由 08:24 跑取代、原因=…"；或重跑一次 `run_tb_tcp_tx_srcip.bat > gates/g5_run.log` 得到与最终一致的 PASS 件；在 REPORT §3 增一条"G5 首跑全红的实施缺陷与修法"。
- **判据/门**：`gates/` 内每个门的"最终跑"日志与报告/RESULT 行逐字一致；无未标注的 FAIL 件。

### 【中】F-11 `slow_tx_adp` 的源 IP/VLAN 提取逻辑没有按 `PER_PORT` 门控（设计说单口不例化）
- **事实**：设计 §2.7（`DESIGN_v2r1.md:370`）写"`PER_PORT=0` ⇒ **提取逻辑/ side FIFO 不例化**"；实现里 `bpos/src_sr/etype_r/src_ip_lat/ip_seen/vlan_seen` 及其更新块（`rtl/slow_tx_adp.v:68-76`、`:214-232`）**无条件存在于 T_DATA 路径**，只有 `o_port`/side FIFO 走 `PER_PORT`（`:126-172`）。综合可能把死链剪掉，但**未验证**；这些寄存器读的输入是 HLS 字节流，剪枝前会真实占用面积/改变布局。
- **后果**：非 DUAL（默认/回归）构建可能多带一份 6 位计数器 + 40 位移位 + 比较器在慢路径上；0x2B 余量只有 0.75%，任何未预期增量都吃余量。功能上无变化（`o_port=0`），所以不会静默错，但违反"单口零代价"的设计承诺。
- **建议修法**：把提取状态声明与更新块整体包 `generate if (PER_PORT)`（或 `ifdef`）；构建轮核对非 DUAL 的 `slow_tx_adp` 资源/时序与 0x2B 基线一致。
- **判据/门**：综合后 `slow_tx_adp` 的 FF/LUT 与非 DUAL 基线差 ≤ 噪声；或 RTL 文本 `PER_PORT` 内包裹。

### 【低】F-12 G3 的"端口反转变异红"不是真变异
- **事实**：`_proj_10g/p11_dual/sim/tb_tx_split.v:144-152` 的臂 D 只是**重复**了一次正常 `send_frame(0,…)` 并断言 `n0==4 && n1==0`，注释写"wire inversion would trip this"——**没有构造交叉接线的 DUT/TB**。报告 §4 写"D 交叉接线判据"是过度声称。
- **后果**：G3 没有证据表明"端口反接"这一缺陷形态会被判据抓住（逻辑上会，但未演示）；G3 本身也不在矩阵（登记债）。
- **建议修法**：在 TB 里用 `defparam`/`generate`/第二份接线把 d0/d1 对调，断言同一激励下 `n0/n1` 判据必红；或删掉"变异"字样、如实写"未做变异"。

### 【低】F-13 G6 未实现设计要求的"每帧 o_port 与帧头源 IP 一致"断言；UDP 侧该一致性完全无门
- **事实**：设计 H-6/G6 行（`DESIGN_v2r1.md:718`）要求"断言每口 W83/W84、**每帧 `o_port` 与帧头源 IP 一致**、跨口不串、端口反转变异红"。`tb_p11_dual.v` 臂 A 只查物理通道与源 IP=IP_A（`:339-347`），臂 B 的 force 帧（`:242-246`）**不含 IP 头**，无法做该一致性；全 TB 无语义上的 `o_port ↔ 源 IP` 逐帧断言（`tx_demux2` 的 `stat_port_change` 只抓帧内翻转）。TCP 侧由 G5、慢路径侧由 G4 各自做了单元级一致性；**UDP app 侧没有任何"peer_my_ip→o_src_ip/o_port"一致性门**。
- **后果**：UDP `udp_tx_cfg` 的 `peer_my_ip_r → o_src_ip/o_port` 只有在 G6 臂 A 的 HLS 路径和 B1/B2 的 force 路径间接覆盖，`utx_port` 与实际源 IP 的一致性没有被验证；若 M-11 的 mux 写错（例如 `o_port` 用了 `peer_ip_r` 而不是 `peer_my_ip_r`），现有门不一定红。
- **建议修法**：G6 臂 B 的 UDP 帧改为带最小 IPv4/UDP 头的真实帧（经 `udp_tx_frame` 正常通路），断言 `o_src_ip == IP_A/IP_B` 与 `utx_port` 对应；或新增一个 `udp_tx_cfg` 单元门（含 IP_B 帧 → o_src_ip=IP_B/o_port=1 与反向）。

### 【低】F-14 G6 忽略仿真模型 `Error: [Unisim RAMB36E2-11] Memory Collision`
- **事实**：`gates/xsim_p11dual.log:31` 有 `Error: [Unisim RAMB36E2-11] Memory Collision at time 4598.401 ns … tb_p11_dual.u_dut.u_slow_rx.u_ff`，而 bat 只查 `P11_DUAL TB PASS`（`run_tb_p11_dual.bat:45-48`），xsim 仍返回 0，门绿。
- **后果**：G6 门对仿真模型级"读可能被破坏"的 Error 无牙；该碰撞落在 HLS 慢路径的 frame FIFO 上，`u_slow_rx` 是臂 A（HLS 握手）的必经之路，若碰撞位置变化可能让臂 A 偶发假绿/假红。也可能指向 `slow_rx_adp` 的既有读-写同拍隐患（非 P11 引入）。
- **建议修法**：bat 增加 `findstr /C:"Unisim" /C:"Error:" /C:"Critical"` 为 0 的硬门（至少对 `Error:`），或定位该碰撞是否良性（慢路径 FIFO 的空读/写同拍）并登记。

### 【低】F-15 G5 的变异件不覆盖 N-6 的**精确**形态（`lip_r` 同沿误用）
- **事实**：`mk_mut_srcip.py` 把 `csum_sip = cam_rd_dip` 等改为 `cfg_src_ip`；它**没有**构造"把默认体 `csum_init_val` 改成 `lip_r`"的 N-6 变异（那才是设计点名的缺陷）。臂 3（上一帧 IP_A → 当前控制帧 IP_B）确实能抓该 bug（若用 `lip_r`，TCP 校验和会按 IP_A，TB 的 `check_frame` 用 `e_sip=IP_B` 会红），但"变异必红"的证据不覆盖这个形态。
- **后果**：门有判别力（靠真实 DUT 通过来间接证明），但"变异必红"这一条对 N-6 不成立；若将来有人引入 `lip_r` 变体，门的红/绿要靠臂 3 的 checksum 断言，而该断言目前是"真实 DUT 通过"，不是"变异必红"。
- **建议修法**：给 `mk_mut_srcip.py` 加第 7 条替换：把默认体 `wire [31:0] csum_sip = PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip;` 改成 `... lip_r ...`（或加一个专门 `N6_MUT` 臂），断言臂 3 必红。

### 【低】F-16 `P7B_BIZ_WINDOW.md:77` 的 W79 语义未按 N-14 同步
- **事实**：`_proj_10g/notes/P7B_BIZ_WINDOW.md:77` 仍写 `W79 = ch0 好帧数（tlast && tcrs && !terr）`；N-14 要求改为"**merge 输入 FIFO 接受的好帧数**（`tready=~ch0_fifo_full`）"，且设计 §5.1 P2-4 把该口径写进判据。该文件自 P1 提交 `a3ac6db3` 后未再改。
- **后果**：板级 P2-4 读 W79 时若按旧口径理解，会把"FIFO 满丢的帧"算进/算不进，和 W85 的守恒判断错位；这是文档级静默错。

### 【低】F-17 HLS 基线失败（3 条）的见证偏弱，且失败点正在本轮改过的 TCP 文件里
- **事实**：`gates/base_out.txt`（07:12:27）只有 3 条 FAIL 与段落名，**没有** `P11_SUMMARY`、没有源/二进制哈希、也没有改前树的重建记录；TL 明说"未独立重跑改前树"。3 条失败都在 `layer_tcp.cpp` 的握手路径（`got SYN-ACK` / multi-MSS），而本轮恰好改了 `cfg_write/tcp_find/local_ip`。报告声称"老测试目的端口与 `TCP_PORT_ECHO=8080` 不一致"，但未给出该结论的证据行。
- **后果**：当前 3 条失败被当作"基线既有"而不修；若其中任一条其实是本轮改动引入，HLS 双 IP 的握手回归就会被漏掉（csim 的 P11 用例又恰好绕开了这几条失败形态）。
- **建议修法**：构建前用 `git worktree` 从 `967e974e^` 重建改前树跑一次三臂 csim，与 `base_out.txt` 对照；或至少记录改前源哈希 + 二进制哈希；把"3 条失败的具体原因（端口/判据）"写成一行可复核的证据。

### 【低】F-18 `maccnt_sync` 的采样节流与设计不符（`src_tick=1` vs "每 256 拍"）
- **事实**：设计 §3.4 写"采样节流 = 每 256 个 `dp_clk` 取一次"（`DESIGN_v2r1.md:472`），实现 `wrapper_p4.v:4872/:4877` 两处都 `.src_tick(1'b1)`；协议安全（busy 串行化），但 CDC toggling 频度高一个数量级，且设计件与实际不一致。功能上不丢事件/不改变快照值（只是更新更频繁），属于低。

### 【低】F-19 `rx_merge2` 的复位域与 FIFO 不同源（`dp_rst_n` vs `reset_n`），是 F-3 同类的新实例
- **事实**：`u_rx_merge` 的 `.rst_n(dp_rst_n)`（`wrapper_p4.v:1180`），而两路 FIFO 的 `rd_rst_n=reset_n`（`:1087`、`:1141`，注释 `:830-832` 明确"FIFO 两侧绝不接 dp_rst_n"）。MMCM 失锁重锁（F-3，已知未修）时 merge 状态清零而 FIFO 指针不重置 ⇒ merge 可能从半个帧开始；下游 `vlan_strip` 的 `RESYNC_EN`（`:862-865`）会等到 SOP 才放行，可能吸收掉该错位，但**没有针对 merge 的专门论证**。P1 S-4/S-5 未测。

### 【低】F-20 构建脚本在 Vivado ERROR 时 bat 退出码仍 0 的既有坑仍未在本构建链上加硬门
- **事实**：本工程 OPEN_ITEMS §0-51 已登记"Vivado 报 ERROR 时 bat 退出码仍 0"；`board/build_p7b_ku5p.tcl` 的末尾（`p7b_ku5p_timing.rpt` 等之后）仍靠 `P7B_VERDICT` 文本行，bat 侧若只查 rc 会假绿。构建轮必须把 `P7B_VERDICT=OK`/`SYNTH_FAIL` 等文本作为硬判据（不是本刀引入，登记为构建前置）。

---

## 二、与设计件不符项（设计件本身/实施逐条）

| # | 设计件位置与原文 | 实物 | 说明 |
|---|---|---|---|
| D-1 | `DESIGN_v2r1.md:424`："`u_rxcdc_ch0.ovf_cnt` 在 `tready` 门控下**应恒 0**（只作安全网）" | 实际是"有字被 full 拒的拍数"（F-4），正常反压即增长 | **设计件本身错**：把"拒写尝试"当"溢出丢字" |
| D-2 | `DESIGN_v2r1.md:697` P2-2：`sat16(ch0_txcdc_ovf)` 作字级修正项 | 同上，会饱和 ⇒ 修正项无判别力 | 判据设计与仪器语义不符 |
| D-3 | `DESIGN_v2r1.md:494` / `:718`：G6 必须有 maccnt"源+1→dst+1"与"常值不重复增加" | TB 只有"无混合值"+裸 2FF 负控 | 实施漏了设计明文要求的两条 |
| D-4 | `DESIGN_v2r1.md:724-739` N-5 读侧清单：4 个文件 + check_window + j6/tcpreg | 另有 6 个 `DEFAULT_SPECS` 文件（gate4_accept/selftest/livefake/negctrl/final_state/gen_inputs）未同步；j6/tcpreg 的**几何表**未加 88 档 | **设计件清单本身不完整**；实施按不完整清单落地 |
| D-5 | `DESIGN_v2r1.md:713` G1："`VRFC 10-3645`+`peer_my_ip` 联合断言 + `$isunknown`" | 无 | 实施漏 |
| D-6 | `DESIGN_v2r1.md:370` §2.7："`PER_PORT=0` ⇒ 提取逻辑/side FIFO 不例化" | 提取寄存器/更新块无条件存在 | 实施与设计不符（是否被综合剪枝未证） |
| D-7 | `DESIGN_v2r1.md:718` G6："断言每帧 `o_port` 与帧头源 IP 一致" | 臂 A 只查物理通道；臂 B 的 force 帧无 IP 头；UDP 侧无一致性门 | 实施漏；设计未明确"force 帧无 IP 头时如何做" |
| D-8 | `DESIGN_v2r1.md:745/:766` §5.3：记 `HLS_SRC_HASH`/`HLS_NET_HASH`；N-3："synth 日志 grep 才是硬门" | build tcl 两样都没有 | 实施漏 |
| D-9 | `DESIGN_v2r1.md:716` G3："端口反转变异红" | TB 无变异，只重复正例 | 报告"交叉接线判据"过度声称 |
| D-10 | `P7B_BIZ_WINDOW.md` N-14 要求 W79 标签同步 | `:77` 未改 | 实施漏（文档） |
| D-11 | 设计 §5.2 G7 "c8 = DUAL+P7B+A+DP+APP" | c8 无 `SFP2_MODE_A`，真构建组合从未 elab | **设计件措辞歧义**（A = APP_MODE 还是 SFP2_MODE_A）+ 实施按歧义落地 |
| D-12 | 设计 §3.4 "采样节流 = 每 256 dp_clk" | `src_tick=1'b1` | 实施偏离（协议安全，低） |
| D-13 | 报告 §4 G5 "三臂 `SRCIP_GATE_PASS`" | `gates/g5_run.log` 是全红 `SRCIP_GATE_FAIL`（08:14 旧跑） | **报告/归档证据不一致**（F-10）；最终 per-arm 日志与矩阵为绿，但这次全红的原因未记录 |

---

## 三、空判据 / 无牙清单（明确"看着绿但没验到"）

1. **G6 臂 C 的 maccnt 断言**：`good_bad==0` 不能区分"正确同步"与"dst_val 恒 0/恒 0xFF"（F-3）——**空判据（无活性判据）**。
2. **G6 臂 B 的"跨口不串"**：force 帧的 tag 检查是有效的；但**优先级**只在 G3 里用 `tx_arb` 的**副本**测，wrapper 里两根 `u_tx_udp_arb`/`u_tx_arb` 的接线优先级**没有门**（G6 臂 B 不并发三 producer）—— 优先级判据在 wrapper 面**空**。
3. **G3 臂 D**：不是变异，"端口反接必红"**无实验证据**（F-12）。
4. **G5 的 N-6 专项**：臂 3 有判别力（真实 DUT 通过），但"错源 IP 变异必红"的变异不覆盖 `lip_r` 同沿形态（F-15）——变异判据在 N-6 面**部分空**。
5. **H-1 的"无 Z"**：断言不存在；当前所有例化点都已接常量 ⇒ 该判据**不存在**（不是空绿，是根本没有）。
6. **P2-4 的 W86 高半"应恒 0"**：在正常反压下必然非 0 ⇒ 若把它当"必须 0"的健康判据，会**假红**；反过来若忽略它，则它**不携带丢帧信息**（F-4）。
7. **G7 c9–c12**：在未定义模块处中止，**不 elaborate 其余 DUAL 配置**；xvlog 能抓未声明名，但抓不到"1 位隐式网截断"（F-8 正是这种形态在 c1..c8 里溜过）——这四组对隐式网是**空判据**。

---

## 四、未测项（本轮未覆盖，不许当已答）

1. **HLS csynth/双 IP 网表**：未跑；`hls/slowstack_prj/.../verilog` 仍是 2026-09-20 的单 IP 网表（`udp_echo.v` mtime）。⇒ DUAL 构建若先不重综合，IP_B 的 ARP/ICMP/UDP/TCP 慢路径 **静默不通**；G6 臂 A 的 IP_B 握手未测（已登记）。
2. **`tcp_tx_frame` 的 `cam_rd_id` 在 `start_ack/ring_start` 的实际 mux**：G5 用常量 CAM、忽略 DUT 的 `cam_rd_id` ⇒ 若 mux 选错连接，G5 看不到（现有 assign 已核，但门未测）。
3. **rx_merge2 的停钟/半帧楔死**（F-2）、**公平性/丢帧率**（设计 §7.4）、**TERM 帧计数语义**（`stat_frames0/1` 把 TERM 也算一帧）。
4. **maccnt_sync 的物理 CDC/时序**：只有 xsim 功能；无综合/STA（已登记）。
5. **`slow_tx_adp` 的 `SIDE_DEPTH=128` 在实际 board 长阻塞下**：G4 的 60 帧/480 字只是纸面构造；板级未测。
6. **UDP app 的 `peer_my_ip→o_src_ip/o_port` 一致性**、**M-11 的 `cfg_sync` 在 Z/换 peer 同拍**：只有 G5 的 tcp 面，UDP 面无门（F-13）。
7. **W83..W87 的板级读数**：未取（设计 §7.13/§7.14）。
8. **读侧 `apply_readside --bid 0x2C` 的 `--rehearse/--assert`**：未跑（F-5）；`p7b_gate4_negctrl.sh` 的"末字回绕"负对照在 NW=88 下未重跑。
9. **`tb_hls_dual_ip.v`**（设计 G8 的 xsim 定向臂）：未写/未跑（报告已登记）。
10. **P2-7 的 bit1（J8 TX_DIS）**：P1 只证 bit0；bit1 未复跑。
11. **构建本身的 WNS/资源/黑盒/HLS 哈希**：全部未测（本轮禁止构建）。
12. **HLS csim 的 3 条基线失败**：未独立在改前树复现（F-17）。

---

## 五、结论

**核心 RTL 未发现会静默错的实现缺陷**：N-6 两条体（默认体 `csum_init_val` 组合读 `cam_rd_dip`、OVL 控制帧用 `start_ack` 沿锁存的 `ctrl_lip` 并在 `start_ack+1` 装载）逐处与设计一致（`rtl/tcp_tx_frame.v:834-838,894-897,921-923,1241-1242,1361-1362,1394-1395,2074-2078,2339-2340,2468-2469,2521,2539`）；`lip_r/port_r` 只在锁存后 ≥1 拍的用途上出现，**没有**误用进 init 拍；三 producer 的 demux 输入已全部是生产者输出（`wrapper:3137-3169`，TCP 误接已在 08:51 修）；每口 arb 的 TCP>UDP>HLS 结构正确；`o_port` 在 tcp/udp/slow 三处帧内冻结；`DUAL_IP/IP_B` 在非 DUAL 折叠；`IP_A_5/IP_B_5` 在 ifdef 外；W86/W87 位域与 `sat16` 与设计一致；`SNAP_NW=88/UNIMPL=0x190/BID=0x2C` 与读侧标签顺序一致；HLS 的 `local_ip/tcp_find/cfg_write/RST 匹配/broadcast→IP0` 全部落点正确。

**但现阶段不应直接进入构建**——需先修：

1. **构建前置（阻断构建）**：先跑 `run_hls.tcl`（`-DBOARD_IP_DUAL=1`）并归档旧 `slowstack_prj` 网表；给 `build_p7b_ku5p.tcl` 补 `HLS_SRC_HASH`/`HLS_NET_HASH` 与 synth 日志 `black box`/`8-3491` 零命中硬门（F-6）；构建 bat 加"`P7B_VERDICT` 文本 + rc"双判据（F-20）。
2. **板级前置（不是综合阻断，但在同一轮收口前必须修）**：读侧 0x2C 链（F-1/F-5：j6/tcpreg 的 `GEOM_TIERS`、6 个 gate4/夹具文件、`gen_inputs.py` 的 `NW_FIX/BID_FIX`、`p7b_gate4_negctrl.sh` 内部一致）；否则板级轮会在 `J6_GEOM_FAIL`/夹具 `exit 3` 处空转。
3. **同批补门（F-3/F-9/F-15）**：maccnt 活性/常值两条断言；真构建组合 `DUAL+SFP2_MODE_A` 的 elab 正控；N-6 的 `lip_r` 变异；H-1 的 `peer_my_ip` 未接定向断言；G6 的 Unisim Error 硬门（F-14）。
4. **RTL 建议同批修（不修则书面临时接受）**：`rx_merge2` 的半帧看门狗（F-2）——这是新引入的跨口死锁面，板级一旦出现只能复位；`slow_tx_adp` 的 `PER_PORT` 门控（F-11）与隐式网（F-8）是廉价清理。
5. **判据口径（用户/判据所有者裁定）**：W86/W87 的 ovf 语义（F-4）与 P2-2 的 ch0 修正项——当前写法会让 ch0 对账变成松判据；"绿"不代表对账有效。

以上修完（1–3 必做，4–5 建议/待裁）即可进入构建；本报告**不下 PASS/FAIL 裁定**，也不声称时序已解决——所有时序/资源/板级读数仍为未测。

---

## TL 抽核（2026-10-18 11:0x，逐条回源）

| # | 抽核项 | 结果 |
|---|---|---|
| 1 | F-1：`GEOM_TIERS` 顶端仍是 `83|0x0000002B`、无 88 档 | ✓ 成立（`j6_r6fix.sh:81-82`、`tcpreg_j6.sh:76-77`）；gate4 系 6 文件默认值仍 83/0x2B（`p7b_gate4_accept.sh:131,137`、`selftest.sh:37,217`、`livefake.sh:146`、`final_state.sh:33`、`gen_inputs.py:58`、`negctrl.sh:74,80` vs `:156` NW=88） |
| 2 | F-2：`rx_merge2` 的 `busy` 只在 `frame_last` 释放、无超时路径 | ✓ 成立（`rtl/rx_merge2.v:86-99`，`p0/p1_tready` 在 busy 期间只放 sel 口） |
| 3 | F-3：G6 臂 C 只查"无混合值"、无活性/常值断言 | ✓ 成立（`tb_p11_dual.v:294-325`：只统计 `good_dst !== 0 && !== 0xFF` 与 `mut_bad>0`） |
| 4 | F-4：`fifo_async` 的 `ovf_pulse_w = wr_en && full_r` 是反压拍数 | ✓ 成立（`rtl/fifo_async.v:184,191`；AXIS 生产者在 full 时保持 tvalid ⇒ 该字下拍重试、不丢）；设计 §3.4/§5.1 的"应恒 0 / 可作修正项"不成立（D-1/D-2） |
| 5 | F-10：归档 `gates/g5_run.log` 是全红旧跑 | ✓ 成立（文件内容 `SRCIP_GATE_FAIL`；同目录 `xsim_{ovl,def,mut}.log` 与矩阵日志为 PASS/PASS/EXPECTED-FAIL；mtime 08:14 早于最终跑 08:24） |

**TL 附注**：F-1/F-2/F-3/F-4/F-10 五条抽核全部与原文一致；其余条目按"报告原文 + 文件:行号"采信，未逐条回源（红队给的行号密度高、结论方向与抽核一致）。**下一步 = 修复轮**（F-1/F-3/F-5/F-6/F-7/F-8/F-9/F-10/F-11/F-12/F-14/F-15/F-16/F-17/F-18/F-20 + 文档 D-1..D-13；F-2 看门狗与 F-4 判据口径作为设计修订项，登记待用户裁）。
