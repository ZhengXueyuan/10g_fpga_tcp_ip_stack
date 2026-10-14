# F-3 设计件 · 证据索引（逐字引文 + 原始读数 + 矛盾点清单）

配套件：同目录 `DESIGN.md`。本文件只放**证据**，不放结论。
**全部 `file:line` 读于 2026-10-14（本轮现读）**；git HEAD = `d6f5efe7218bf8fddc87a57f214b67938e03ef5f`。

---

## 1. F-3 的一手描述（三处来源逐字对照）

### 1.1 `agent_docs/P6B_CDC_AUDIT.md`（一手 · 审计 + 实测）

**`P6B_CDC_AUDIT.md:40`（发现清单 F-3 行，逐字）**：

> | **F-3** | 🟡 **低-中**（复位不同源；未在链上实测） | 两个 CDC FIFO 的复位**只接板级 `reset_n`**，而数据面功能逻辑接 `dp_rst_n`（`clk_gen_p6b` 产生，**`locked` 参与**：`rst_async = (~locked_raw) | rst_ext`，`rtl/clk_gen_p6b.v:228`）。⇒ MMCM **失锁/重锁**时 DP 功能逻辑重启，而 FIFO 的**指针与内容保留**：DP 侧会在帧中重启。`vlan_strip` 以 `tuser` 认帧首（`rtl/vlan_strip.v:94-96,191`）⇒ 表现应为"丢一帧"而非脏数据，**但本审计未做链上实测**（诚实标注，见 §6）。 | 代码：`wrapper_p4.v:431,434,2206,2208`（四处 `rst_n`）+ `rtl/clk_gen_p6b.v:224-237` |

⚠️ 该行有两处**本轮现读已不再准确**：
- 行号 `vlan_strip.v:94-96,191` / `wrapper_p4.v:431,434,2206,2208` 是**旧版本**的
  （该件自己在 `:202-204` 的 §A.4 就警告过 `fifo_async.v` 被并行改动、行号需按新版本复核）。
  本轮现读：`vlan_strip.v` 的 `tuser` 用法在 **`:94`（`vlan_go`）/`:96`（`shifting`）/`:191`（S_SHIFT 的 tuser 恢复支）**；
  四处 FIFO 复位在 **`board/wrapper_p4.v:892,895,2776,2778`**。
- "**FIFO 的…内容保留**"这句**在硬件情形下不成立**（见 DESIGN.md §1.2：复位窗口内 DP 一直在排空 FIFO
  因为 `vlan_strip.s_axis_tready` 是组合量、不看 `rst_n`）。审计当时没测这一条。

**`P6B_CDC_AUDIT.md:111`（§7 诚实清单第 2 条）**：

> 2. **F-3（DP 功能复位 vs FIFO 复位不同源）未做链上实测**：我只从代码读出 `rst_dp` 的置位源含 `locked`，并确认 `vlan_strip` 以 `tuser` 认帧首 ⇒ 推断后果是"丢一帧"而非脏数据。**没有**跑"MMCM 失锁 → 重锁"的整链实验。

**`P6B_CDC_AUDIT.md:175`（附录 A.3 标题，逐字）**：

> ## A.3 F-3 实测（协调者要求"不再是推断"）：**改接线不足以解决；且字面建议有害**

**`P6B_CDC_AUDIT.md:183-187`（三接线实测表，逐字）**：

> | 变体 | 重启后首个交付帧 | `stale_words` | 带 crs=1 的截断帧 | 契约 |
> |---|---|---|---|---|
> | **A 现行**（两侧都只接 `reset_n`） | 40B **片段**（帧3 偏移24） | 0（DP 跟得上 ⇒ 重启瞬间 FIFO 近空） | **1** | 合规 |
> | **B 只复位读侧**（= 字面建议） | 帧0 完整 ⇒ **帧0/1/2 被重复投递** | **26** | 0（但 3 个已消费帧重放） | **违反硬契约** |
> | **C 两侧同源同拍复位**（FIFO 清空） | 48B **片段**（帧3 偏移16） | 0 | **1** | 合规（契约允许"同拍断言"） |

**`P6B_CDC_AUDIT.md:189-198`（结论 + 真正的收口方向，逐字）**：

> ⇒ **结论**：① 三种接线**都会**让 DP 在重启后交付一个**帧中截断的片段，且携带原帧 `tcrs=1`**
> （= 截断帧被当 FCS 有效帧交付）—— **F-3 的危害在接线层面无解**，根因是 **DP 侧没有以 SOP 为界的重启重同步**
> （FIFO 无法提供帧对齐信息）；② **字面建议（只把读侧接 `dp_rst_n`，`:434`）必须不做**：它破坏
> `fifo_async` 的复位硬契约（指针不同代），实测把**已被消费的整帧重新投递**（`stale_words=26`）。
> ③ 变体 C 额外观测到 FE 侧 8 帧丢弃 + DP 只消费 9 字 —— 未完全定因（疑为"两侧复位窗口内 FE 的 push
> 被静默丢弃而生产者以为成功"= F-1 同类），**故 C 也不是无条件更好**。
> ⇒ 本次**未改 `board/wrapper_p4.v`**（保持 `03e76507605f88acf2847dc5101eca14` 不变）。
> 真正的收口方向（均超出本次授权，建议单列）：
> (i) 让 DP 侧重启后**等 tuser 才开帧**（`vlan_strip`/`rx_classify` 加入口门控）；
> (ii) 把 `mac_rx_64` 也纳入"同源同拍复位"（其复位后必然从新前导/新帧首字开始 ⇒ 首个 push 就是 SOP 字）。

**`P6B_CDC_AUDIT.md:151-152`（F-2 的 S_FLUSH 覆盖性论证第 ③ 条，逐字）**：

> ③ 唯一"TLAST 永不到来"的情形 = DP 被复位/弃帧 ⇒ 冲刷会连下一帧整帧一起吃掉（代价 = 丢 1 帧，
> **有界、自愈、有计数**，仍绝不发坏帧）；

**`P6B_CDC_AUDIT.md:245-252`（B.5 关于"片段会不会被下游当合法帧收下"的静态判读，逐字）**：

> **不会进 fast 路，但 FCS 保护在 MAC 边界确实被击穿。** 静态判读：`rx_classify` 完全不用 `tuser`
> （`:123-128` 只把它存进 skid），ethertype 取**它自己对齐**的 `sk_d[1][31:16]`；片段起点是帧中，
> 该字段是垃圾 ⇒ `is_tcp=0` ⇒ `n==2` 拍定案 `route <= RT_SLOW`（`:133-141`）⇒ **一律走慢路径**；
> 短片段（40/48B = 5/6 字）还会在 tlast 分支提前判 slow（`:129-132`）。
> 慢路径 `slow_rx_adp` 头注释自述"补前导但**不重生成 FCS**"⇒ 它（以及任何信 `tcrs` 的消费者）
> 看到的是"`tcrs=1` 的未知协议短帧"，靠 IP `total_len`/ARP 定长自然忽略 —— 即**靠解析器兜底，
> 不是靠 FCS 校验**。⇒ 危害有界（大概率被丢），但"坏帧带 tcrs=1"这条完整性属性已被破坏。

### 1.2 `agent_docs/P6B_SUMMARY.md:75-78`（复述，与 1.1 一致）

> 1. **F-3（唯一的未修缺陷）**：MMCM **失锁/重锁**时，FIFO 只接板级 `reset_n` 而 DP 功能逻辑接
>    `dp_rst_n`（含 `locked`）⇒ DP 侧会在**帧中**重启，交付一个**帧中截断但携带 `tcrs=1`** 的片段。
>    **三种接线实测都无解**（只复位读侧更糟：把已消费的整帧重新投递）；根因 = **DP 侧没有"以 SOP 为界"的
>    重启重同步**。后果有界（丢/重一帧、进不了 fast 路、靠下游解析器兜底）。收口方向与全文见
>    `agent_docs/P6B_CDC_AUDIT.md` §A.3。

### 1.3 `_proj_10g/notes/P7B_OPEN_ITEMS.md`（**二次概括 —— 与 1.1 不符的那一处**）

`:68`（§0 表格第 17 行，逐字）：

> | **17** | **F-3（MMCM 失锁重锁）** | **未修**（DP 侧帧中重启 ⇒ 丢/重一帧） | 潜伏项，未触发 | **事件脉冲清（小改，需构建）** |

`B6` 条目（本轮现读起于 `:412`）§③/§④ 逐字：

> - **③ 为什么没解决**：跨域复位/事件清逻辑改动面在 CDC 层，需重新做一遍 CDC 门。
> - **④ 下一步最小动作**：按审计件的方向改成**事件脉冲清**（与坑 14 同族），跑 CDC 门 + 一次构建。代价 = 一次构建 + CDC 门。

⛔ **对账**：B6 自己把"依据"写成"`P6B_CDC_AUDIT.md`"，但该件的方向是 §A.3 的 (i)/(ii)
（等 SOP 重同步 / mac_rx 同源复位），**不是"事件脉冲清"**；而 B6 提到的"坑 14"
（`udp_hls_10g/CLAUDE.md` 坑 14 = 跨会话状态一律事件脉冲清）讲的是 `app_ctrl` 的
FIN/RST 标志清理，**与时钟域重启无关**。
⇒ 结论：**"事件脉冲清"是二次概括，把两个不相干的东西连到了一起**（DESIGN.md §0.1/§6-(g)）。

**旁证（全仓 `grep -rn "脉冲清"`）**：命中处全部集中在
`rtl/app_ctrl.v:88/512/1008/1205`、`rtl/tcp_tx_frame.v:2160/2303`、`sim/p5b_adv/tb_p5_app_wnd.v:427`、
`sim/p5c_t3/tb_p5c_fence.v:17` 等（**都是 FIN/RST/同槽重连类的跨会话状态清理**），
**无一处**提到 F-3 / MMCM / 时钟域。

---

## 2. t9 原始读数（三臂，2026-09-29 归档；本轮从日志原件现读）

文件：
- `agent_docs/audit_scratch/t9_f3restart/{tb_f3_restart.v, case_old/xsim_old.log, case_new/xsim_new.log, case_both/xsim_both.log}`
- runner：`agent_docs/audit_scratch/run_t9.bat`（⚠️ `:6` 逐字 `set ROOT=D:\repo\XCKU5PMini\udp_hls_10g` = **硬编码绝对路径**，非自定位）

**变体 A（现行接线）`case_old/xsim_old.log`**：

```
TB-STIM frames=12 bytes=1200 stopIdx=340
F3 STOP at si=340 (frame K=3 mid-content); dp side now restarts; W_snap=26
F3 RELOCK: fe_acc=96 dut_acc=96 (窗口内静默丢 0)
F3 DELIV[0] len=40 **片段** 源帧=3 偏移=24 crs=1 tuser=0 <== 陈字(重启前就开始收的帧)
F3 DELIV[1] len=64 WHOLE 帧4 crs=1 tuser=0
... (帧5..11 同形, 共 8 个 WHOLE)
F3 SUMMARY ndel=9 whole=8 frag=1 stale_frag=1 trunc_with_crs=1 unrec=0
F3 SUMMARY fe_acc=96 dut_acc=96 silent_drop=0 mac_frames=12 mac_drop=0 ovf=0
F3 STALE-CONSERV dw_all=69 pushes_after=70 => stale_words=0  (无陈字)
F3 VERDICT stale_frag=1 stale_words=0 silent_drop=0
```

**变体 B（只复位读侧；= 禁止用法）`case_new/xsim_new.log`**：

```
F3 RELOCK: fe_acc=96 dut_acc=96 (窗口内静默丢 0)
F3 SUMMARY ndel=12 whole=12 frag=0 stale_frag=0 trunc_with_crs=0 unrec=0
F3 STALE-CONSERV dw_all=96 pushes_after=70 => stale_words=26 <= 重启后交付了重启前的字!
F3 VERDICT stale_frag=0 stale_words=26 silent_drop=0
```

**变体 C（两侧同源同拍复位）`case_both/xsim_both.log`**：

```
F3 RELOCK: fe_acc=26 dut_acc=27 (窗口内静默丢 4294967295)
F3 SUMMARY ndel=2 whole=0 frag=2 stale_frag=1 trunc_with_crs=1 unrec=0
F3 SUMMARY fe_acc=35 dut_acc=36 silent_drop=4294967295 mac_frames=4 mac_drop=8 ovf=0
F3 STALE-CONSERV dw_all=9 pushes_after=10 => stale_words=0  (无陈字)
F3 VERDICT stale_frag=1 stale_words=0 silent_drop=4294967295
```

⚠️ **读数口径三条（别误读）**：
1. 变体 A/B 的 `silent_drop=0`（`fe_acc == dut_acc`）与 C 的 `4294967295`（= −1）——
   审计件 `:258-259` 已定案为**TB 两个计数器同块采样的 ±1 相位假象**，不是丢字。
2. `stale_words` 是**守恒式**（`dw_all − pushes_after`），在变体 A 里本来就等于 0（`dw_all=69 <
   pushes_after=70`）⇒ **它不能当"无陈字"的唯一判据**；抓缺陷的是 **J1（`stale_frag`）+ 逐帧内容
   比对**（`源帧=3 偏移=24`）。这条与 `DESIGN.md` §3.3-J5 的写法一致。
3. 变体 A 的 `F3 DELIV[1..8]` 的 `tuser=0`：TB 只在"帧首字"记 SOP（`tb_f3_restart.v:224`），
   而**重启后**的帧首字（帧4 的 SOP）是在**断档之后**才出现的——TB 把"重启后第一个 in_frame
   拍"当帧首，所以记 0。**别据此推断线上无 tuser**（`mac_rx_64` 的 SOP 合同见 §3.1）。

**TB 的重启模型（逐字，`tb_f3_restart.v:247-253`）**：

```verilog
        dp_rst_dp = 1;                     // 失锁: 复位断言 (异步)
        repeat (2) @(posedge gclk);
        dp_clk_en = 0;                     // 时钟停摆
        repeat (1500) @(posedge gclk);     // 停 1500 拍 (=1500 字节的帧流量)
        dp_clk_en = 1;                     // 重锁: 时钟恢复
        repeat (4) @(dclk);
        dp_rst_dp = 0;                     // 4 个 clk_dp 后释放 (同 clk_gen_p6b)
```

⇒ 该模型 = `DESIGN.md` §3.1-I-3。它**不复用** `clk_gen_p6b`（纯 TB 建模），但**已经抓到真缺陷**。

---

## 3. SOP / TERM 字合同（本修法赖以成立的唯一帧边界信息）

### 3.1 `rtl/mac_rx_64.v`（1G 前端）—— 本轮以 `grep -n` 现读（未逐行读全文）

- `:42-43`（头注释，逐字）：
  > (ii) 被中止 —— 补一个 **TERM 字**: `tdata=0, tkeep=8'h00, tlast=1,
  >      tuser=0, tcrs=0, terr=1` (0 字节, 不污染字节计数; tcrs=0 ⇒ 下游按坏帧丢)。
- `:202-209`（TERM 落笔，逐字含字段）：`push_data <= 64'd0; push_keep <= 8'd0; push_last <= 1'b1;`
  `push_sop <= 1'b0; push_crs <= 1'b0; push_err <= 1'b1;`
- `:238`：`push_sop <= !first_done;` ⇒ **SOP 只在本帧第一个被推入的字上**。
⇒ **每个交付帧恰一个字带 `tuser=1`（首字）；TERM 字 `tuser=0`** ⇒ "等 `tuser`"落在真帧首。

### 3.2 `_proj_10g/p7b_mac/rtl/mac_rx_10g.v`（10G 前端，板构建用它）—— 同法现读

- `:12-13`：`2. SOP: tuser=1 落在帧首字; 帧首字总是满对齐 (tkeep[7]=1)`
- `:16`：`6. TERM 字 = {tdata=0, tkeep=8'h00, tlast=1, tuser=0, tcrs=0, terr=1}`
- `:331`：`它的在飞字 (B 与本拍的字) 一律丢弃, 绝不推入 (否则会留下"无 TLAST 的裸 SOP")。`
- 端口/打包：`:503-504` `m_axis_tuser = fdout[3]; m_axis_tlast = fdout[2];`
⇒ 两个 MAC **同一份冻结合同**（仓根 `CLAUDE.md`「MAC 字流接口规范」）⇒ 门只看 `tuser` 对两侧都成立。

### 3.3 `rtl/fifo_async.v`（复位硬契约，一手；本轮读了 `:1-77`）

- `:55`：`★★ 硬契约: 两侧复位必须同时 (同源分两路, 或同一时刻断言)。`
- `:61-66`：
  > ② **只复位一侧 ⇒ 指针不一致 = 未定义行为 (静默脏数据)**。可预测的后果 (单元门量过):
  >   · 只复位读侧: 读侧以 rbin=0 去追它看到的写指针 W ⇒ **多弹** …
  >   ⇒ **单侧复位是禁止用法**, 仅供故障注入测试 …
- `:67-70`：复位期间另一侧时钟停摆 ⇒ 该侧复位保持、恢复后同步释放；
  ⚠️ "若'停摆侧的复位'与'工作侧的复位'不是同时给的, 时钟恢复后就落到 ② 的脏状态"。
- 同源规范件：`agent_docs/P6B_SPEC.md:745-777` §4.4（含"**mmcm_locked 绝不进 FIFO 的复位路径**"
  与接线照抄块）。
- ⚠️ §4.4 末段有一句**与本刀相关、且被审计件实测修正**的话（逐字）：
  > 若 `locked` 抖动（100MHz 参考钟丢失），dp_clk 会停 ⇒ DP 侧不推进 ⇒ FE 侧的 `full` 最终拉高
  > ⇒ `u_mac_rx` 丢帧（**降级但不错**）；时钟恢复后握手自动续上
  ⛔ 审计件 §A.3 实测 = 恢复后**交付一个帧中截断片段（`tcrs=1`）** ⇒ 不是"不错"。
  **引用 §4.4 末段时必须带这条订正**。

---

## 4. 复位分发与时钟生成（本轮逐处现读）

| 事实 | 位置（现读） |
|---|---|
| MMCM 的 `LIMITED` 语义（掉低条件） | `rtl/clk_gen_p6b.v:76-77` |
| 复位方案（异步置位/同步释放） | `rtl/clk_gen_p6b.v:84-91` |
| 行为模型 `locked`（`quiet` 由 `posedge clk_p` 清零） | `rtl/clk_gen_p6b.v:157-166`（`assign locked_raw = lock_byp;` :166） |
| `SIM_BYPASS` 下 `clk_in_100 = clk_p`（停参考钟会连它一起停） | `rtl/clk_gen_p6b.v:155` |
| `MMCME4_BASE.RST` **硬接 `1'b0`**（板上无法软复位 MMCM） | `rtl/clk_gen_p6b.v:211` |
| `wire rst_async = (~locked_raw) \| rst_ext;` | `rtl/clk_gen_p6b.v:228` |
| `rel_sr` 4 级 + `assign rst_dp = ~rel_sr[3];` | `rtl/clk_gen_p6b.v:230-237` |
| `hls_rst_n`（另一条 DP 域复位，只喂 HLS 实例） | `board/wrapper_p4.v:1792, :2057, :2474-2475` |
| `u_clkgen` 例化（`.rst_ext(~reset_n)`） | `board/wrapper_p4.v:698-712`（`:706` = 端口） |
| `wire dp_rst_n = ~dp_rst_dp;`（双域） | `board/wrapper_p4.v:716` |
| `wire dp_clk = gmii_clk; wire dp_rst_n = reset_n;`（单域） | `board/wrapper_p4.v:720-721` |
| `VLAN_STRIP_RESYNC` 的写法先例（同款 ifdef localparam） | `board/wrapper_p4.v:689-694` |
| `SNAP_NW_P6E = 71` + MIR 四字占用 `0x13C/0x140/0x144/0x148` | `board/wrapper_p4.v:3251-3260` |

**吃 `dp_rst_n` 的 DP 功能实例（本轮现读 20 处 `.rst_n(dp_rst_n)` 中已点名者）**：
`u_vlan_strip` `:936` · `u_classify` `:959` · `u_tcp_rx` `:1813` · `u_tcb` `:1982` ·
`u_tcp_tx`(= `tcp_tx_frame`) `:2162` · `u_udp_split` `:2322` · `u_slow_rx` `:2450` ·
`u_slow_cfg` `:2162`(同批) · `u_tx_arb` `:2751` · `u_dbg_line` `:3044`。
`retx_ram` 不是顶层实例：它在 `rtl/tcp_tx_frame.v:960`（`retx_ram u_retx (`）内，随上层复位；
其端口表含 `rst_n`（`rtl/retx_ram.v:24`），但**mem 不带复位**（`rtl/fifo_async.v:76` 同款注释可参照）。

**CDC FIFO 复位（唯二的两处边界）**：
- RX：`board/wrapper_p4.v:891-902`（`.wr_rst_n(reset_n)` `:892` / `.rd_rst_n(reset_n)` `:895`），
  `assign rxsrc_tready = ~rx_fifo_full;` `:903`，`assign rx_tvalid = ~rx_fifo_empty;` `:904`，
  单域别名 `:906-917`。
- TX：`board/wrapper_p4.v:2775-2787`（`.wr_rst_n` `:2776` / `.rd_rst_n` `:2778`），
  `assign m_tx_tvalid = ~tx_fifo_empty;` `:2786`；`mac_tx_10g.rst_n = tx_mac_rst_n` `:2803`、
  `mac_tx_64.rst_n = reset_n` `:2827`。

---

## 5. `vlan_strip` 现状（本轮**整文件**读毕：206 行）

| 事实 | 行（现读） |
|---|---|
| 模块声明（无参数） | `:47` |
| `s_axis_tready` 纯组合、**不看 `rst_n`** | `:105`（`od_free` = `:89`） |
| `acc = s_axis_tvalid && s_axis_tready` | `:90` |
| 8 处帧逻辑"认账"条件用 `acc` | `:99, 100, 101, 156, 160, 170, 173, 190` |
| 输出寄存器在复位时 `m_axis_tvalid <= 1'b0` | `:138` |
| FSM 复位值 `state <= S_PASS` | `:134` |
| `tuser` 的三处既有用法 | `:94`（`vlan_go`）/`:96`（`shifting`）/`:191`（S_SHIFT 恢复支） |
| 头注释里"帧内出现 SOP（上游截断残段）"的自述 | `:43-44` |
| 头注释背压合同（`s_axis_tready = od_free`） | `:36-37` |

**输出侧消费点（全文件现读 `grep -n "vs_tdata|vs_tvalid|...")`）**：
`u_classify` 的 `s_axis_*`（`board/wrapper_p4.v:960-967`）+ 延迟探针
`wire lat_dp_evt_vs = vs_tvalid && vs_tready && vs_tuser;`（`board/wrapper_p4.v:4853`，
注释语境 `:4824`（逐字 `//   (c1) vlan_strip : vs_tvalid && vs_tready && vs_tuser   (DP 域)`））。

## 6. `rx_classify` 现状（本轮读 `:40-190`）

| 事实 | 行（现读） |
|---|---|
| **完全不用 `tuser`**：判据 = 自对齐 `widx` + 字节 | `:98-107` |
| 复位后 `widx <= 0` | `:111` |
| `dec_val = dec_w5 ? (cur_tcp_ctl ? RT_SLOW : RT_FAST) : RT_SLOW;` | `:107` |
| 输入 FIFO 空间门（组合 `tready`） | `:82-86` |
| 输出 FWFT + 路由队列 | `:124-173` |

⇒ 片段按"垃圾 ethertype"通常落慢路（与审计件 B.5 静态判读一致）；
小概率命中 `0x0800/6/非ctl` ⇒ 伪 fast 段（**概率量级 1.3×10⁻⁸，未实测**；构造法见 DESIGN.md §1.4）。

---

## 7. 门/构建基础设施（决定修法的"文件面"）

| 事实 | 位置（现读） |
|---|---|
| 板构建宏集（**本刀不加宏**） | `board/build_p7b_ku5p.tcl:286`（`APP_MODE DEV_USP PCIE_OBS DP_156MHZ P7B_10G UDP_TX_OVL TCP_TX_OVL`） |
| 板构建**显式** `import_files` 清单（含 `rtl/vlan_strip.v`） | `board/build_p7b_ku5p.tcl:84-92`（数据面）/ `:94-101`（观测） |
| ⚠️ 该清单上方的"黑盒静默失效"警告（逐字） | `board/build_p7b_ku5p.tcl:98-103`（"**缺它 = 该模块是黑盒** … = 安静失效"） |
| 全链门 1 = **glob** 文件表（新增 rtl 文件自动进） | `sim/p6e_pcie/run_tb_p6e_pcie.bat`（`dir /b /s "%ROOT%\rtl\*.v" > files.f`）+ 宏集 `-d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN` |
| 全链门 2（板等价）= **glob** + `P7B_10G/P7B_SIM_NOPCS` | `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:16-17`（glob）/ `:39`（宏集） |
| 全链门 2 的 DUT 例化名 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v:102`（`wrapper_p4 u_dut (`）；参考钟驱动 `:83-88`（`sys_clk_p/n`，#5 翻转 = 100 MHz） |
| 编译面门（板真配置的 `d3` 臂） | `sim/p5wu_p1p2/run_xvlog_wrapper63.bat:56`（`-d APP_MODE -d P7B_10G -d PCIE_OBS -d DEV_USP -d DP_156MHZ -d UDP_TX_OVL`） |
| ⚠️ 三个 `SNAP_NW_P6E = 71` **指纹硬门** | `sim/p5wu_p1p2/run_xvlog_wrapper63.bat:53` · `_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat:33` · `_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat:25` |
| 读侧几何/未实现地址 | `_proj_pcie/p6e_snap_check.sh:60-73`（`EXPECT_BID` 默认 `0x00000024`；`UNIMPL_ADDR = 0x20+4*NW+16 = 0x14C`） |
| 全链门的 snapshot 判据（含地址↔字映射判据 2/9） | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v:43-47, 356, 381-410` |
| 常驻矩阵入口 + gate 行声明 | `sim/p4gates/run_matrix_p4dfix.bat`（`:5` "The gate list is the 'call :gate' rows of this file"） |
| 被门/矩阵引用的 `vlan_strip` 单元门 | `sim/vlansim/run_tb_vlan_strip.bat`（TB = `tb/tb_vlan_strip.v`，`:62` 具名例化） |

**`vlan_strip` 的例化点（本轮 `grep` 主树 8 处，抽查 4 处全部具名连接）**：
`board/wrapper_p4.v:934`（`u_vlan_strip`）· `tb/tb_f4_chain.v:66` · `tb/tb_p4_chain.v:659` ·
`tb/tb_p5_multi.v:437` · `tb/tb_p5_app.v:328` · `tb/tb_p5_adv.v:296` · `tb/tb_vlan_strip.v:62` ·
`sim/p5e_pre/tb_p5_udp_split.v:325`（另有 `sim/p5b_adv/tb_p5_app_wnd.v:261`、
`sim/p5e_pre/tb_p5_baseline.v:325` 同族）。
⇒ 端口表**末尾**追加输出端口对这些例化**零影响**（但落地前仍要按 DESIGN.md §2.2-(A7) 复核一遍）。

---

## 8. 我核过的"来源互相矛盾"清单（**下游引用时按本表**）

| # | 冲突 | 一手 | 二手 | 裁定 |
|---|---|---|---|---|
| 1 | F-3 的收口方向 | `P6B_CDC_AUDIT.md:196-198` = (i) 等 SOP / (ii) mac_rx 同源复位；且 `:175` 明写"**改接线不足以解决；且字面建议有害**" | `P7B_OPEN_ITEMS.md:68` + B6 §④ = "**事件脉冲清**" | **以一手为准**；"事件脉冲清"是错的概括（DESIGN.md §0.1、§6-(g)） |
| 2 | F-3 的后果形态 | `t9` 三臂实测（本文件 §2）= 现行接线**交付帧中截断片段**；"重复投递"只在变体 B | `P7B_OPEN_ITEMS.md:68` = "丢/重一帧"（合并说法） | **拆开写**：现行 = 丢一帧 + 交付伪装成好帧的片段；"重"属被禁止接线 |
| 3 | "FIFO 的…内容保留" | 代码：复位窗口内 DP 一直在弹字（`vlan_strip.v:105` + `wrapper_p4.v:895`） | `P6B_CDC_AUDIT.md:40` 原话"指针与内容保留" | 指针保留 ✓ / **内容保留 ✗**（真硬件情形）；t9 的停钟模型里它才成立（DESIGN.md §1.2） |
| 4 | 恢复后的行为评价 | `t9` 实测（片段带 `tcrs=1`） | `agent_docs/P6B_SPEC.md` §4.4 末段"降级但不错…握手自动续上" | **以实测为准**（§4.4 末段需带订正引用） |
| 5 | F-3 与 R8 的关系 | `P6B_SPEC.md:1313` 的 R8 = "复位不同代 ⇒ 指针静默错位" | F-3 = "复位同代（都接 `reset_n`）但功能逻辑另一源" | **两者不是同一件事**；F-3 **不**违反 §4.4 硬规则（本刀也不碰任何 FIFO 复位） |

---

## 9. 本轮**未**读/未做的事（避免下游过度归因）

- 未读全文：`rtl/mac_rx_64.v`（只 `grep -n` 取字段行）、`_proj_10g/p7b_mac/rtl/mac_rx_10g.v`（同）、
  `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`（只读宏集/例化/快照判据段）、
  `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`（106 KB，只读头/时钟/DUT 例化）。
- 未跑：xsim / Vivado / 上板 / 对端机（派单边界）。
- 未验证：§3 的门（不存在）、§4.1 的时序预算（无综合读数）、§1.4 的"伪 fast 段"可构造性。
