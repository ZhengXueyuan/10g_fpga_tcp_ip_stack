# F-3 修复设计件（MMCM 失锁→重锁 ⇒ 数据面帧中重启）

| 项 | 值 |
|---|---|
| 件名 | `p9_fix_f3_design_20261014` |
| 日期 | 2026-10-14 |
| 轮次性质 | **只调查 + 出设计件**。未改 `rtl/**`、`board/**`、`sim/**`、`tb/**` 任何文件；未跑 xsim；未跑 Vivado；未碰对端机；只新建 `_proj_10g/notes/p9_fix_f3_design_20261014/**` |
| 被审基线 | git HEAD `d6f5efe7218bf8fddc87a57f214b67938e03ef5f`（工作树除未跟踪残渣外干净） |
| 行号纪律 | **本件所有行号均为本轮现读**（读于 2026-10-14）。别件/旧件的行号一律不照抄 |
| 证据索引 | 见同目录 `EVIDENCE_INDEX.md`（逐字引文 + 原始读数 + 我核过的矛盾点清单） |

> ⛔ **本件不含 PASS/FAIL 裁定**（裁定权在用户）。凡未实测处一律写 **【推断】** 并给"怎么证伪"；
> 凡"没测到"一律写 **"未观测到"**，不写"不存在"。

---

## §0 摘要（含**与派单描述不符**的三处，先读这一节）

### 0.1 ⛔ 派单写的"既有收口方向 = 事件脉冲清（小改）"**与一手来源不符**

派单说：`agent_docs/P6B_CDC_AUDIT.md` 里 F-3 的既有收口方向 =「事件脉冲清（小改）」。

**现读结论：不成立。** 该件的实测附录（`agent_docs/P6B_CDC_AUDIT.md:175-198`，标题逐字 =
「A.3 F-3 实测（协调者要求"不再是推断"）：**改接线不足以解决；且字面建议有害**」）给出的方向是：

- **(i)** 让 DP 侧重启后**等 tuser 才开帧**（`vlan_strip`/`rx_classify` 加入口门控）——
  `P6B_CDC_AUDIT.md:197`；
- **(ii)** 把 `mac_rx_64` 也纳入"同源同拍复位"（其复位后必然从新前导/新帧首字开始）——
  `P6B_CDC_AUDIT.md:198`；
- 并且**逐字否掉了**"把 FIFO 清掉/改接线"这条路：三种接线变体**都**会交付帧中截断片段
  （`P6B_CDC_AUDIT.md:189-190`），"只复位读侧"更**违反硬契约**（把已消费的整帧重新投递）。

同仓 `agent_docs/P6B_SUMMARY.md:75` 的复述与之一致（"**三种接线实测都无解**；根因 = **DP 侧没有
'以 SOP 为界'的重启重同步**"）。

**"事件脉冲清"这个词只出现在 `_proj_10g/notes/P7B_OPEN_ITEMS.md`**（§0 第 17 行表格 +
`B6` 条目 §④），是**二次概括**（B6 §④ 还把它挂到"与坑 14 同族"= 跨会话状态清理 —— 那是
`app_ctrl` 的 FIN/RST 标志清理，**与时钟域重启无关**）。全仓 `grep -rn "脉冲清"` 命中处
（`rtl/app_ctrl.v:88/512/1008/1205`、`rtl/tcp_tx_frame.v:2160/2303` 等）**没有一处**与 F-3 有关。

⇒ **本设计件按一手来源的方向 (i) 设计**，并在 §1.6 给出"清 FIFO/事件脉冲清为什么不解决问题"
的实测依据（变体 C）。方向 (ii) 建议**不做**（理由见 §6-(c)）。

### 0.2 ⛔ 派单写的"丢/重一帧"也要拆开说

现读数（`agent_docs/audit_scratch/t9_f3restart/` 三臂，2026-09-29，本轮从日志原件现读）：

| 接线变体 | 重启后第一个交付帧 | `stale_words` | 截断帧带 `tcrs=1` | 判词 |
|---|---|---|---|---|
| **A 现行**（两侧只接 `reset_n`） | **40 B 片段**（源帧3 偏移24，`tuser=0`） | 0 | **1** | `F3 VERDICT stale_frag=1 stale_words=0 silent_drop=0` |
| **B 只复位读侧**（= 字面建议/禁止） | 帧0 完整 ⇒ **帧0/1/2 重复投递** | **26** | 0 | `VERDICT stale_frag=0 stale_words=26` |
| **C 两侧同源同拍复位**（FIFO 清空） | 48 B 片段（源帧3 偏移16） | 0 | **1** | `VERDICT stale_frag=1 ... silent_drop=4294967295`(±1 相位假象) |

⇒ **现行接线（板上就是它）= "丢一帧 + 交付一个伪装成 FCS 正确的截断片段"**；
**"重一帧"只在被明确禁止的变体 B 出现**。派单那句是两种症状的合并说法，落到判据上必须拆开写，
否则会做出错误的判据（例如拿"重复"当主判据 ⇒ 现行接线根本不会红）。

### 0.3 修法一句话 + 交付物

**修法 = 在 DP 侧 RX 入口（`rtl/vlan_strip.v` 输入端）加一个"复位释放后先丢到第一个 SOP（`tuser`）
再开帧"的重同步门**，用参数 `RESYNC_EN` 门控（**默认 `1'b0` = 既有行为**），只在
`board/wrapper_p4.v` 的 `DP_156MHZ` 分支打开。**唯一功能改动 = 1 个文件 1 处参数 + 1 个模块内的
1 个寄存器 + 8 处 `acc`→`acc_f`**（逐处列在 §2.2）。可测性、代价、构建/板测计划见 §3–§5。

### 0.4 板上口径（先说清，免得下游误读）

- **板上无法受控触发失锁**（Y1 = 板载 100 MHz 晶振常亮，主机侧没有任何手段让它停或漂；
  MMCM 的 `RST` 在 RTL 里硬接 `1'b0`，见 `rtl/clk_gen_p6b.v:211`）⇒ F-3 的**板级判据只能写
  "未观测到"**（见 §5.2）。
- 本刀**不新增快照字**（理由与完整代价见 §4.3-③）。

---

## §1 机制复核（每条标【事实】(带现读 `file:line`) 或【推断】(带证伪路径)）

### 1.1 触发链（代码级）

1. 【事实】DP 域时钟 = `clk_gen_p6b` 的 `clk_dp`（156.25 MHz；`rtl/clk_gen_p6b.v:14,193-217`）。
   它的 `LOCKED` 在"输入钟抖动/瞬断、频率漂移、PWRDWN/RST、温度/电压越界"时**瞬时掉低**
   （逐字见 `rtl/clk_gen_p6b.v:76-77`）。
2. 【事实】`rst_dp` 的**置位源含 `locked`**：`wire rst_async = (~locked_raw) | rst_ext;`
   （`rtl/clk_gen_p6b.v:228`）；`rel_sr` 4 级移位、`rst_dp = ~rel_sr[3]`
   （`rtl/clk_gen_p6b.v:230-237`）。⇒ **失锁立刻异步置位**，**重锁后再数 4 个 `clk_dp` 才释放**。
3. 【事实】`dp_rst_n = ~dp_rst_dp`（`board/wrapper_p4.v:716`），它复位的是**整个 DP 功能面**：
   `u_vlan_strip`（`board/wrapper_p4.v:936`）、`u_classify`（`:959`）、`u_tcp_rx`（`:1813`）、
   `u_tcb`（`:1982`）、`u_tcp_tx = tcp_tx_frame`（`:2162`）、`u_udp_split`（`:2322`）、
   `u_slow_rx`（`:2450`）、`u_tx_arb`（`:2751`）…（本轮现读的 20 处 `.rst_n(dp_rst_n)`）。
4. 【事实】两个 CDC FIFO 的**两侧复位都只接板级 `reset_n`**（硬契约，`rtl/fifo_async.v` 头注释
   §②"只复位一侧 ⇒ 指针不一致 = 未定义行为"+ `agent_docs/P6B_SPEC.md:745-777` §4.4）：
   `u_rxcdc` 在 `board/wrapper_p4.v:891-902`（`.wr_rst_n(reset_n)`/`.rd_rst_n(reset_n)`），
   `u_txcdc` 在 `:2775-2787`（同；`.wr_rst_n` 行 = 2776 / `.rd_rst_n` 行 = 2778）。
   ⇒ MMCM 失锁**不动 FIFO 指针/内容**。
5. 【事实】FIFO 的读口由 `vlan_strip` 的 `s_axis_tready` 驱动：
   `.rd_en(rx_tvalid && rx_tready)`（`board/wrapper_p4.v:895`）。而
   `rx_tvalid = ~rx_fifo_empty`（`:904`，FWFT 组合读）。
6. 【事实】`vlan_strip` 的 `s_axis_tready` 是**纯组合量、完全不看 `rst_n`**：
   `assign s_axis_tready = (state == S_TAIL) ? 1'b0 : od_free;`（`rtl/vlan_strip.v:105`），
   `od_free = !m_axis_tvalid || m_axis_tready`（`:89`），复位时 `m_axis_tvalid = 0`（`:138`）
   ⇒ **复位期间 `s_axis_tready ≡ 1`**。
7. 【事实】由 5+6：**复位窗口内 DP 侧仍在持续弹字**（`rd_en = ~empty && 1`），弹出来的字被
   复位中的功能逻辑丢在地上（`always` 块在复位 ⇒ 不落账）。

### 1.2 ⛔ 关键更正 1：FIFO 不是"内容保留"的冷冻库

`agent_docs/P6B_CDC_AUDIT.md:40` 的 F-3 行原话是"**FIFO 的指针与内容保留**：DP 侧会在帧中重启"。
指针那句对；**"内容保留"对硬件情形是错的**：由 §1.1-6/7，失锁窗口里 DP 侧一直在排空它。

⇒ 释放瞬间 FIFO 队首 = **"释放那一刻线上正在收的那一帧的中段字"**（FE 一直在写，见 §1.1-4 的
   写侧不受影响），而**不是**失锁前的存底。这条差异对修法是决定性的（见 §1.6：清/冻结 FIFO 都没用）。

⚠️ 但**在 t9 的仿真模型里**（停 DP 钟 + 断言 `dp_rst_dp`，见 `tb_f3_restart.v:247-253`）
"内容保留"**是成立的**（钟停了 ⇒ 排空也停了）：t9 变体 A 交付的片段内容逐字对得上
**失锁前**就在 FIFO 里的那 5 个字（`F3 DELIV[0] ... 源帧=3 偏移=24`，源帧 3 ≤ `K_restart=3`）。
⇒ **两种子情形（钟停 / 钟不停）都会产生"帧中重启"，本修法对两者都成立**（门只看释放后的字流，
不看窗口里发生了什么）。这条是修法设计的关键属性，写在 §2.4 不变量 I3。

### 1.3 ⛔ 关键更正 2：DP 重启清掉的**不止"帧对齐"**

由 §1.1-3：一次失锁 = **整个 DP 功能面复位**，含 `tcb`（TCP 连接状态）、`tcp_tx_frame` 的
ring/seq 状态、`app_ctrl` 的连接表、慢路径 HLS 实例…。⇒ 后果**远大于"丢/重一帧"**：
对端看到的是一个**静默丢状态的 peer**（连接要靠 RTO 才收敛）。

- 【事实】上述复位面（§1.1-3 的现读行号）。
- 【推断】对端语义 = 所有在途 TCP 连接失效、需要重建；10G 线上会先表现为"零窗口/无 ACK 响应"
  直到对端 RTO。**证伪路径**：在 §3 的全链门里注入一次失锁，观察 `tcb` 的 `state` 与
  `app_ctrl` 的连接事件 FIFO 是否被清（这是**本刀的附带读数**，不是本刀修的东西）。
- ⛔ **本刀不修这一半**（也修不了：时钟停了就没有"保住状态"的可能）。**建议单列一条登记**
  （§6-(e)），别把它塞进 F-3 的收口口径里 —— 否则 F-3 的"修好"会被误读成"失锁无害"。

### 1.4 危害的实际形态（含 rx_classify v2 的重新评估）

- 【事实】t9 变体 A 交付的片段：`len=40`、`crs=1`、`tuser=0`
  （`case_old/xsim_old.log` 的 `F3 DELIV[0]` 行）⇒ 一个**没有 SOP、却带 `tcrs=1`**的短帧。
  "坏帧带 `tcrs=1`"这条完整性属性被打穿。
- 【事实】`rx_classify` **完全不看 `tuser`**：它的判据是自对齐的 `widx`+`tdata` 字节
  （`rtl/rx_classify.v:98-107`：`widx==1` 锁存 `tdata[31:16]==0x0800`、`widx==2` 看 `[7:0]==6`、
  `widx==5` 看 `[2:0]`），复位后 `widx<=0`（`:111`）。
- 【推断（比审计件更精确的一条）】片段的 ethertype 是垃圾 ⇒ 通常判 `RT_SLOW`
  （`dec_val = RT_SLOW` 除"IPv4+TCP+非 ctl"外，`:107`），随后由慢路径的解析器兜底丢；
  **但存在小概率"伪 fast 段"**：只要片段在 `widx==1/2/5` 三个位置恰好是 `0x0800 / 6 / 000`
  就会被送进 TCP 快路径。粗算概率 ≈ 2⁻¹⁶·2⁻⁸·(7/8) ≈ 1.3×10⁻⁸（**量级，未实测**）。
  **证伪/证实路径**：在 §3 的门里构造这个字节图案的片段（一次 xsim 就能定案），
  或在 t9 的激励里把 `cbyte()` 换成命中图案的函数。⇒ 危害面"大概率被丢"这句**要带这个尾巴**。
- 【事实】危害是**有界**的：每次失锁只影响"释放瞬间正在收的那一帧"（≤1 帧），且下游有 FCS/
  长度/协议解析三层兜底。

### 1.5 TX 方向（同一个触发，另一侧）

- 【事实】`u_txcdc` 读侧跑在 `tx_fe_clk`、复位只接 `reset_n`（`board/wrapper_p4.v:2778`），
  所以 DP 失锁期间 **FE 侧照常读**：`.rd_en(m_tx_tvalid && m_tx_tready)`（`:2778`）、
  `assign m_tx_tvalid = ~tx_fifo_empty;`（`:2786`）；`mac_tx_*` 的复位是 `tx_mac_rst_n`/`reset_n`
  （`:2803`/`:2827`），**不受 `dp_rst_n` 影响**。
- 【事实】残帧行为已有安全网：F-2 修复加的 `S_FLUSH`（`rtl/mac_tx_64.v`，见审计件 §A.1）
  在中止后"一个字都不发"地吞掉到本帧 TLAST 为止；其覆盖性论证第 ③ 条逐字写明
  "唯一'TLAST 永不到来'的情形 = DP 被复位/弃帧 ⇒ 冲刷会连下一帧整帧一起吃掉（代价 = 丢 1 帧，
  **有界、自愈、有计数**）"（`agent_docs/P6B_CDC_AUDIT.md:151-152`）。
- 【推断】⇒ **TX 方向不需要改 RTL**：一次失锁的 TX 后果 = 线上一个 runt（对端按 FCS 丢）
  + 一个被 flush 掉的整帧，两者都有计数（`stat_flush_words/stat_flush_done`、`stat_abort`）。
  **证伪路径（便宜）**：在 §3 的门里加一条 TX 臂（t3 形态）判"失锁前中段的帧 → 线上恰 1 个 runt
  + flush 计数 > 0 + **0 个幽灵帧**"；若出现幽灵帧或丢帧数无界 ⇒ 本推断被证伪，回到 TX 侧设计。
  **未观测到 ≠ 不存在**：本轮**没有**跑过任何 TX 侧失锁实验。

### 1.6 "事件脉冲清 / 清 FIFO"为什么**不**解决问题（实测依据）

| 路线 | 结果 | 出处 |
|---|---|---|
| 只复位读侧（单侧清） | **违反硬契约**：`stale_words=26`（已消费的 3 整帧被重新投递） | `t9 case_new` |
| 两侧同源同拍复位（FIFO 清空） | **仍然**交付帧中截断片段（`trunc_with_crs=1`），且 FE 侧 8 帧丢弃、DP 只消费 9 字 | `t9 case_both` |
| 现状（什么都不动） | 交付帧中截断片段（`trunc_with_crs=1`） | `t9 case_old` |

**机理**：清 FIFO 只清"存下来的字"，**清不掉"线上正在发的这一帧"** —— 释放后 FE 立刻把该帧的
**中段字**推回来（§1.1-4：写侧从不参与 DP 复位）。⇒ **只有"以 SOP 为界的重同步"能在入口处判别
帧边界**（题面那句话：FIFO 结构上无法提供帧对齐信息）。这就是一手来源的方向 (i)。

---

## §2 修法设计（实现级：照此实施即可）

### 2.1 方案选择（为什么放在 `vlan_strip` 内 + 参数门控）

**入选：方案 1 —— 在 `rtl/vlan_strip.v` 的输入侧加"等 SOP"门，参数 `RESYNC_EN`（默认 0），
由 `board/wrapper_p4.v` 的 `DP_156MHZ` 分支打开（`localparam` + 具名参数）。**

理由（逐条都要能过审）：

1. **唯一入口**：DP 侧 RX 字流的**唯一消费者**就是 `u_vlan_strip`（现读 `board/wrapper_p4.v:937-944`
   是全文件对 `rx_tdata/rx_tvalid/rx_tuser/...` 的唯一使用处；单域分支的别名在 `:906-913`）。
   门放在这里 = 覆盖 DP 的**全部** RX 入口。
2. **零新增文件 ⇒ 灭掉本仓最大一类静默失效**：本仓构建清单是**显式 `import_files`**
   （`board/build_p7b_ku5p.tcl:84-118`），且那里逐字警告过"**缺它 = 该模块是黑盒**（Vivado 对未导入的
   被例化模块不报硬错 … = 安静失效）"。新增一个 `rtl/*.v` 就必须同步所有构建 tcl 与所有显式文件表；
   `vlan_strip.v` **已经在每一张表里** ⇒ 本方案的文件面是 **0**。
3. **默认参数下逐位退化**（§2.4 的不变量 I1/I2 给出的是**结构**证明，不是"我觉得"）：
   `RESYNC_EN=0 ⇒ fwd ≡ 1'b1`（常数）⇒ `acc_f ≡ acc` ⇒ 综合期常数折叠后网表不变。
4. **不碰 VLAN FSM 的语义**：本改动只做"**少收字**"（§2.4 的 I3），对已收下的字，所有表达式
   与旧文逐字相同。
5. **备选方案（不选）**：新增 `rtl/rx_resync_gate.v` 插在 `u_rxcdc` 与 `u_vlan_strip` 之间。
   工程上更"单一职责"，但代价是 ① 新增文件 ⇒ 上面第 2 条的整片雷区；② 必须把 `u_vlan_strip`
   的 12 条 `.s_axis_*` 改指向新的 `g_*` 别名，并在 `ifdef` 的另一支补 8~12 行纯别名
   （判句"两种构建一份文本"因此变松散）。**若实施中发现方案 1 有硬阻塞**（见 §4.5-R1），
   回落到本方案，编辑清单见 §2.8。

### 2.2 编辑清单 A：`rtl/vlan_strip.v`（唯一功能改动文件，现读 206 行）

> 纪律：**插入型编辑**。逐处给"锚点行（现读原文）→ 新文"。除列出的行，其余一字不动。
> ⚠️ 落地后**必须**复查 ① 三处 `if (acc)` 全改成 `acc_f`；② `s_axis_tready` **一字未改**。

**(A1) 模块头加参数** —— 锚点 = 文件第 47 行 `module vlan_strip (`：

```verilog
module vlan_strip #(
    // ---------------------------------------------------------------------------
    // F-3 (2026-10-14, 见 _proj_10g/notes/p9_fix_f3_design_20261014/DESIGN.md):
    //   RESYNC_EN = 1: 复位释放后**先丢弃输入字直到第一个 tuser (SOP) 再开帧** —— 只在
    //                 "数据面独立时钟域"(DP_156MHZ) 的构建里打开。
    //   RESYNC_EN = 0: 既有行为 (默认值; 默认参数下不产生任何逻辑, 见设计件 §2.4 的 I1/I2)。
    //   为什么需要: MMCM 失锁→重锁时 DP 功能逻辑被 dp_rst_n 复位, 而 u_rxcdc 的读侧只接板级
    //   reset_n(指针同代硬契约) ⇒ 释放瞬间 FIFO 队首多半是**帧中字** ⇒ 不设门就会把它当帧首
    //   交付一个"帧中截断但带 tcrs=1"的片段。实测 = agent_docs/P6B_CDC_AUDIT.md §A.3 (三接线都红)。
    //   未同步期间被丢弃的字计入 stat_resync_words (弹出但未当帧内容收下)。
    // ---------------------------------------------------------------------------
    parameter RESYNC_EN = 1'b0
)(
```

**(A2) 新增信号** —— 锚点 = 第 81 行 `reg        tail_crs, tail_err;   // 尾字沿用末输入字的 tlast 侧带`
（在其**之后**插入）：

```verilog
    // ---- F-3 重同步门 --------------------------------------------------------
    // resync: 已重同步到帧首. 复位释放后为 0; 一旦有一个字被"当帧内容收下"(acc_f && rst_n) 置 1,
    //   保持到下次复位。不变量: resync==0 ⇒ state==S_PASS ∧ m_axis_tvalid==0 (复位值, 且 FSM
    //   的推进条件已全部被 acc_f 门控)。
    reg         resync;
    // fwd: 本拍这个输入字是否被当帧内容处理。
    //   RESYNC_EN=0 ⇒ 恒 1 (常数折叠 ⇒ 与旧文逐位等价)
    //   RESYNC_EN=1 ⇒ 未同步期间只有 tuser=1 的字被收下, 其余字弹出并丢弃
    wire        fwd   = (!RESYNC_EN) || resync || s_axis_tuser;
```
（`s_axis_tuser` 已在端口表 ⇒ 先声明后用的次序满足。）

**(A3) 在 `acc` 之后新增派生态 + 计数器** —— 锚点 = 第 90 行
`wire        acc     = s_axis_tvalid && s_axis_tready;`（在其**之后**插入）：

```verilog
    wire        acc_f = acc && fwd;   // 帧逻辑"认账"的接受拍 (F-3: 受 fwd 门控; RESYNC_EN=0 ⇒ ≡acc)
    wire        rsw   = RESYNC_EN && acc && !(acc_f && rst_n);
                                      // 弹出但未当帧内容收下 = 被丢弃 (含复位窗口内的浪费)
    reg  [31:0] stat_resync_words;    // F-3 观测: 丢弃字数 (⚠️ 若做 (A7) 把这一行挪到端口表)
```

**(A4) 8 处 `acc` → `acc_f`**（帧逻辑的"认账"条件；**`s_axis_tready` 那行不动**）：

| 现读行 | 现文 | 改成 |
|---|---|---|
| 99 | `wire load_pass  = (state == S_PASS)  && acc;` | `... && acc_f;` |
| 100 | `wire load_w1    = (state == S_W1)    && acc && !vlan_go;` | `... && acc_f && !vlan_go;` |
| 101 | `wire load_shift = (state == S_SHIFT) && acc;` | `... && acc_f;` |
| 156 | `if ((state == S_W1) && acc && vlan_go) begin` | `if ((state == S_W1) && acc_f && vlan_go) begin` |
| 160 | `end else if (shifting && acc) begin` | `end else if (shifting && acc_f) begin` |
| 170 | `S_PASS: if (acc) begin` | `S_PASS: if (acc_f) begin` |
| 173 | `S_W1: if (acc) begin` | `S_W1: if (acc_f) begin` |
| 190 | `S_SHIFT: if (acc) begin` | `S_SHIFT: if (acc_f) begin` |

⚠️ **第 105 行 `assign s_axis_tready = (state == S_TAIL) ? 1'b0 : od_free;` 不改**（这是"Policy D"：
复位窗口内继续排空 = 现行行为，见 §2.5）。

**(A5) 复位块加两行** —— 锚点 = 第 140 行 `stat_stripped <= 32'd0; dbg_vlan <= 1'b0;`：

```verilog
            stat_stripped <= 32'd0; dbg_vlan <= 1'b0;
            resync <= 1'b0;                    // F-3: 复位 = 未同步 (等下一个 SOP)
            stat_resync_words <= 32'd0;
```

**(A6) 重同步置位 + 丢弃计数** —— 锚点 = 第 168-169 行
`// ---- 帧状态机 ----` / `case (state)`（在 `case` **之前**插入）：

```verilog
            // ---- F-3: 重同步到帧首 + 丢弃计数 ----
            // `acc_f && rst_n` = 本拍这个字真的被当帧内容收下了 ⇒ 已对齐 (未同步期间 fwd 只在
            //   tuser 拍为 1, 所以这一拍一定是 SOP 拍); 复位期间不置位 (那时收下也不算数)。
            if (acc_f && rst_n) resync <= 1'b1;
            if (rsw)            stat_resync_words <= stat_resync_words + 32'd1;
```
⚠️ 两处 `&& rst_n` / `!(... && rst_n)` 的说明：`resync` 那行的 `&& rst_n` 在 `else` 支内
**语义上冗余**（本支只在 `rst_n` 为高时执行），**有意保留**：防 xsim 下 `rst_n` 下落沿与 `clk`
上升沿同刻的求值竞态把 `resync` 误置 1（本仓坑 17 的同一族）。`rsw` 里的 `!(acc_f && rst_n)`
**不冗余** —— 它是"复位窗口内弹掉但没落账的字也算丢"的唯一来源（见 §2.5 Policy D）。

**(A7) 端口表末尾追加输出**（**可选**：G1/G2 都可用层次名读计数器，见 §3.2-G2 末两条；
只有"将来真要进快照"时才必须加）——锚点 = 第 70 行
`output reg         dbg_vlan        // 当前帧处于剥离支 (调试观测)`：

```verilog
    output reg         dbg_vlan,       // 当前帧处于剥离支 (调试观测)
    // F-3 观测: 被本模块丢弃的输入字数 (resync 丢弃支 + 复位窗口内未落账的弹出)
    output reg  [31:0] stat_resync_words
```

并把 (A3) 里内部声明的 `reg [31:0] stat_resync_words;` **删掉**（改由端口表声明；两处只能留一处）。
⚠️ 落地前核一遍所有例化点都是**具名连接**（本轮现读主树 8 处：
`board/wrapper_p4.v:934`、`tb/tb_f4_chain.v:66`、`tb/tb_p4_chain.v:659`、`tb/tb_p5_multi.v:437`、
`tb/tb_p5_app.v:328`、`tb/tb_p5_adv.v:296`、`tb/tb_vlan_strip.v:62`、
`sim/p5e_pre/tb_p5_udp_split.v:325` —— 现读抽查 4 处全部 `.port(...)` 具名；
`sim/p5b_adv/`、`sim/p5e_pre/tb_p5_baseline.v` 同族，实施时一次性跑
`grep -rn "vlan_strip u_" --include=*.v .` 逐处看下一行）。若发现任何**按位置**例化 ⇒ **取消 (A7)**，
把计数器留在模块内部（门用层次名 `u_vs.stat_resync_words` 读，见 §3.2-G1/G2 —— 层次读不依赖综合，
不会被剪掉）。⚠️ 若跳过 (A7)，则 (A6) 里那行内部声明要保留。

**(A8) 文件头注释**：在 `rtl/vlan_strip.v:1-45` 的合同段**追加一段**（不改旧行）：

```verilog
// ---- F-3 (2026-10-14) 追加合同 (仅 RESYNC_EN=1 时生效) ---------------------------
// 复位释放后, 本模块先把输入字**弹出并丢弃**直到第一个 tuser=1 (SOP) 字, 才把它与之后的字
//   当帧内容处理; 被丢弃的字计入 stat_resync_words。RESYNC_EN=0 时本条不存在 (逐位等价)。
// 不变量: resync==0 期间本模块不产生输出、不推进 FSM、不装载 hold (只弹字)。
// 为什么这是对的: 上游 u_rxcdc 的读侧复位只接板级 reset_n (指针同代硬契约), 所以 DP 复位释放
//   的瞬间队首可能是"帧中字"; 唯一的帧边界信息 = tuser (rtl/mac_rx_64.v:42-43 与
//   _proj_10g/p7b_mac/rtl/mac_rx_10g.v:16 的 TERM 字都是 tuser=0; SOP 恰一帧一次)。
// ----------------------------------------------------------------------------------
```

### 2.3 编辑清单 B：`board/wrapper_p4.v`

**(B1) 加 `localparam` 选择** —— 锚点 = 第 716 行
`    wire dp_rst_n = ~dp_rst_dp;        // 低有效 (与 reset_n 同极性), 见上面极性说明`
（**双域分支内**，在其后插入；单域分支在 `:720-721` 另有 `wire dp_rst_n = reset_n;`）：

```verilog
    wire dp_rst_n = ~dp_rst_dp;        // 低有效 (与 reset_n 同极性), 见上面极性说明
    // F-3 (2026-10-14): vlan_strip 的"复位后等 SOP"重同步门只在**数据面独立时钟域**的构建里打开。
    //   单域构建里 mac_rx 与 vlan_strip 复位同源同拍 ⇒ mac_rx 复位后必从新前导起步 ⇒ 首个交付字
    //   必是 SOP ⇒ 不需要门; 且默认构建必须逐位等价 (CLAUDE.md「应用接口」的硬合同)。
`ifdef DP_156MHZ
    localparam VLAN_STRIP_RESYNC = 1'b1;
`else
    localparam VLAN_STRIP_RESYNC = 1'b0;
`endif
```
⚠️ 写法照抄同文件既有先例 `board/wrapper_p4.v:689-694`（`SIM_CLKGEN_BYPASS` 的
`ifdef P6B_SIM_CLKGEN localparam ... else localparam ...`）。**这条 `ifdef` 是恒真的**
（它就在 `ifdef DP_156MHZ` 里），保留它是为了①与旧文同风格 ②使"单域 = 0"的取值在文本上可见。
⇒ 更省的等价写法：直接 `localparam VLAN_STRIP_RESYNC = 1'b1;`（在双域支内）+ 单域支里加一行
`localparam VLAN_STRIP_RESYNC = 1'b0;`。**二选一，实施时取"更省"的那个**（两处各一行）。

**(B2) 例化点传参** —— 锚点 = 第 934 行 `    vlan_strip u_vlan_strip (`：

```verilog
    vlan_strip #(.RESYNC_EN(VLAN_STRIP_RESYNC)) u_vlan_strip (
```

**(B3)（可选；⚠️ 依赖 (A7) —— 跳过 (A7) 就一并跳过 (B3)）观测线接出** —— 锚点 = 第 931 行
`    wire [31:0] vlan_stat_stripped;   // 板级观测: UART 帧行未接 (后续可加)`：

```verilog
    wire [31:0] vlan_stat_stripped;   // 板级观测: UART 帧行未接 (后续可加)
    wire [31:0] vlan_stat_resync;     // F-3: vlan_strip 被丢弃字数 (同 vlan_stat_stripped 口径,
                                      //      当前未进快照 —— 进窗口的代价见设计件 §4.3-③)
```
并在例化里加一行 `.stat_resync_words (vlan_stat_resync),`（放在 `.stat_stripped(...)` 之后）。
**本行按"不新增快照字"的前提写**；把 `vlan_stat_resync` 接进 W 窗口是**另一件**（§6-(a)）。

### 2.4 不变量（这是本修法"为什么安全"的全部内容；门要逐条判）

- **I1（默认关 = 逐位等价）**：`RESYNC_EN=0 ⇒ fwd ≡ 1'b1`（`(!0) || ...` 是常数真）
  ⇒ `acc_f ≡ acc` ⇒ 8 处替换在综合期**常数折叠回原式**；`resync` 恒 0（`(A6)` 的置位条件
  在 `acc_f && rst_n` 下…… ⚠️ **注意**：`resync` 仍会置位，但它唯一的作用点是 `fwd`，
  而 `fwd` 已被常数真短路 ⇒ 该寄存器无扇出 ⇒ 被优化掉；`stat_resync_words` 的增量
  `rsw ≡ 0`（含常数 `RESYNC_EN`）⇒ 计数器被优化掉。
  ⇒ **默认构建的网表逐位不变**。判据形态 = 结构（综合后无新增 cell）+ 行为（既有门逐字不变）。
- **I2（错被限制在"少收字"）**：新逻辑**只可能减少**被收下的字集合，且**只在 `resync==0`
  期间**（即从释放到第一个 SOP）；一旦 `resync==1`，`fwd==1` ⇒ 所有表达式与旧文逐字等价。
- **I3（与"钟停/钟不停"无关）**：门只看"释放之后"的字流，不看失锁窗口里 DP 有没有排空
  （§1.2）⇒ 两种子情形都被同一逻辑覆盖。
- **I4（不可能死锁/不可能丢整帧的过头）**：`resync==0 ⇒ state==S_PASS ∧ m_axis_tvalid==0
  ⇒ od_free==1 ⇒ s_axis_tready==1` ⇒ 丢弃支**永远走得动**（不依赖下游）；丢弃在下一个
  `tuser` 拍结束（≤1 帧时间，10G/1G 都是 ≤1.3 µs 量级）。
- **I5（守恒）**：上游弹出数 = 交付给 `rx_classify` 的字数 + `stat_resync_words`
  （逐字可对；见 §3.3-J4）。

### 2.5 政策选择：复位窗口内"继续排空"(D，推荐) vs "冻结上游"(H，可选)

| 政策 | 复位窗口内 `rd_en` | 好处 | 代价 |
|---|---|---|---|
| **D（推荐，= 本设计的 (A4) 不改 `:105`）** | 继续弹（现行行为） | **改动最小**：FIFO 侧、FE 侧、PCS/GT 侧行为**一字不变**；只有"释放后 DP 收哪些字"变了 | 窗口内弹掉的字**丢在地上**（被 `stat_resync_words` 计数，不再静默）；那一帧本来也保不住（它的头已被复位前的 DP 消费并随复位丢失） |
| H（可选） | 冻结（`s_axis_tready` 加 `rst_n` 门） | 若释放瞬间 FIFO 队首恰是某帧的 SOP，该帧可**完整交付**（少丢一帧） | 长失锁窗口里 FIFO 会被填满 ⇒ FE 回压 ⇒ MAC/PCS 丢帧（新引入一段回压模态），收益只在窄窗且**换不回被复位吃掉的那一帧** |

⇒ **推荐 D**。H 的 1 行差异（若将来要 A/B）：
`assign s_axis_tready = (state == S_TAIL) ? 1'b0 : (rst_n ? od_free : 1'b0);`
**并且** H 必须把 `rsw` 的口径改成"弹出未交付"（`rsw = RESYNC_EN && !rst_n && acc;` 之外的
字不算丢）—— 即 H 是一次**口径改动**，不是一行开关。**本刀不做 H**（登记为 §6-(b)）。

### 2.6 对每个消费点的语义影响（逐条）

| 消费点 | 现读位置 | 影响 |
|---|---|---|
| `rx_classify`（唯一帧流消费者） | `board/wrapper_p4.v:957-967` | 上游字流在**复位后**变成"从 SOP 开始"；稳态一字不变。⇒ 它拿不到"无 SOP 的片段"了（这正是目的）。它的 `widx`/`dec_*` 逻辑不受影响（`:98-107`） |
| 延迟探针 `lat_dp_evt_vs` | `board/wrapper_p4.v:4853`（`vs_tvalid && vs_tready && vs_tuser`） | **两臂一致**：被丢弃的字不产生输出（`od_load ⊂ acc_f`）⇒ 探针不触发；旧行为的片段首字 `tuser=0`（t9 实测）⇒ 旧臂也不触发。⇒ **该探针读数不受本刀影响** |
| `u_rxcdc` 读口 | `:895` | `rd_en = rx_tvalid && rx_tready` 不变；**指针同代契约不变**（本刀不碰任何 FIFO 复位）。§4.4 硬规则(T4)继续成立 |
| 背压/FE 侧 | `:903`（`rxsrc_tready = ~rx_fifo_full`） | **完全不变**（Policy D） |
| 快照/统计 | `stat_stripped`/`dbg_vlan` 语义不变；新增 `stat_resync_words`（**未进窗口**，§6-(a)） | 旧字逐项未动 |
| 单域构建（K7/P4/P6a） | `:720-721` + `VLAN_STRIP_RESYNC=0` | 逐位不变（I1） |

### 2.7 边界与反例扫描（实施者要逐条在门里覆盖）

| 场景 | 期望 | 依据 |
|---|---|---|
| TERM 收尾字（`tdata=0,tkeep=0,tlast=1,tuser=0`）在队首 | 未同步 ⇒ **丢弃**（正确：它不是帧首） | `rtl/mac_rx_64.v:42-43`、`_proj_10g/p7b_mac/rtl/mac_rx_10g.v:16` |
| 帧内 `tuser`（上游截断后紧跟新帧首字） | 未同步 ⇒ 就把这个 SOP 当帧首开帧（正确） | `rtl/vlan_strip.v:44`（既有 tuser 恢复支） |
| 释放瞬间 FIFO 空 | 门保持关闭到下一个 SOP ⇒ **正常帧零影响** | I4 |
| SOP 与 TLAST 同拍（1 字帧/runt） | 收下并交付一个 0 字节帧（与旧行为一致） | `:171`/`:178` 的既有分支 |
| VLAN 帧 | 不变（门只在 `resync==0` 起作用；VLAN 分支需 `state==S_W1` ⇒ 必然已同步） | `:86-87,94,174-177` |
| 下游长期停（`m_axis_tready=0`）且 `resync==0` | 不影响丢弃（`m_axis_tvalid==0 ⇒ od_free==1`）；错位不可能 | I4 |
| 背靠背帧、IFG 内释放 | 门在下一条 SOP 开 | I4 |
| watchdog `hls_rst_n`（`slow_rx_adp` 饥饿复位） | **不影响本门**（它是 DP 域内另一个复位，只喂 HLS 实例 `:2474-2475`） | `:2474` |

### 2.8 备选方案（若方案 1 被否）：新模块 `rtl/rx_resync_gate.v`

只有当 §4.5-R1 触发时才用它。编辑 = ① 新文件（`s_*`/`m_*` 两套 76 位 AXIS，端口表里带
`stat_drop_words`）；② `board/wrapper_p4.v` 的 `ifdef DP_156MHZ` 支例化它 + `ifndef` 支补 12 行
`assign g_* = rx_*;` 纯别名；③ 把共享的 `u_vlan_strip` 例化的 12 条 `.s_axis_*` 改指 `g_*`；
④ **`board/build_p7b_ku5p.tcl` 的显式清单加该文件**（否⇒黑盒静默失效，见 `:98-103` 的原警告）；
⑤ 其余定义 `DP_156MHZ` 的构建 tcl 逐个核。**代价比方案 1 高一个数量级**，故不推荐。

---

## §3 可测性设计（MMCM 是物理件：怎么在 xsim 里造"失锁→重锁"）

> ⚠️ 本轮**未跑任何仿真**（派单禁止）⇒ 本节是**计划**，不是读数；所有"期望"都必须由实施者
> 用自己的读数替换后方可引用。已存在的读数只来自 2026-09-29 的归档（§0.2 表）。

### 3.1 注入方案（三种，按"离真硬件多近"排）

| # | 注入 | 做法 | 保真度 | 副作用 | 推荐 |
|---|---|---|---|---|---|
| **I-1** | **停参考钟** | 让 TB 的 `sys_clk_p/n`（100 MHz，`tb_p7b_chain.v:84-88`）停止翻转 N 个 `clk_dp` 周期再恢复 | **最高（走真端口）**：`P6B_SIM_CLKGEN` 行为模型（`rtl/clk_gen_p6b.v:157-166`）的 `quiet` 计数器**由 `posedge clk_p` 清零** ⇒ 停 `clk_p` 16 个 `clk_dp` 后 `locked` 掉低；恢复后 1 个 `clk_dp` 内 `locked` 回真 ⇒ `rel_sr` 再 4 拍释放 ⇒ **`rst_dp` 的整段波形与真机同形** | ⚠️ 该模型里 `clk_in_100 = clk_p`（`rtl/clk_gen_p6b.v:155`）⇒ 停钟期间 PCS st​ub/dclk/P7b POR 计数器一并停（`board/wrapper_p4.v:594`）。**只要 F-3 判据不落在 `clk_in_100` 域观测上就无害**（实施时核一遍） | ⭐ **首选** |
| **I-2** | **force 内部 `locked` 源** | `force u_dut.u_clkgen.g_sim.lock_byp = 1'b0;` … 恢复 `release` | 高（只动 F-3 那根信号；`clk_dp` 与 `clk_in_100` 全程不停） | 依赖层次名（`u_dut` = `tb_p7b_chain.v:102` / `tb_p6e_pcie_wrapper.v:82`；`g_sim` = `rtl/clk_gen_p6b.v:144` 的 generate 块名）；`-debug typical` 已在两个门里 ✓ | 若 I-1 扰动别的判据 ⇒ 用它 |
| **I-3** | **TB 侧建模重启**（既有 t9 形态） | 停 DP 钟 + 直接驱动 `dp_rst_dp`，1500 gclk 后恢复钟、4 个 DP 沿释放（`tb_f3_restart.v:247-253`） | 中（不复用 `clk_gen_p6b`；但**已经抓到真缺陷**） | 无（纯 TB） | 单元/链级门首选（已存在，扩展便宜） |

⛔ **三种注入都必须带 witness**：TB 必须**打印/断言 `dp_rst_dp`（或 `mmcm_locked`）真的走完了
"高→低"整段，否则"未观测到"与"注入没生效"不可区分**（全仓纪律：**"注入过" ≠ "测到了"**）。
层次名 = `u_dut.dp_rst_dp`（`board/wrapper_p4.v:696`，`DP_156MHZ` 支内）。

### 3.2 门计划（放哪 / 判什么 / 负对照必须红）

**G1（单元/链级门，主承重；新建 `sim/f3_resync/`，自定位 bat）**

- 被测链（与 t9 同构，`tb_f3_restart.v:5-7`）：`GMII 帧源 → mac_rx_64 → fifo_async(76/256/FWFT)
  → vlan_strip(真 RTL) → DP 水槽（按 TLAST 成帧，逐帧记内容/长度/tcrs/tuser）`。
- 注入 = **I-3**（既有模型，零新增风险）。
- 臂：**F** = `vlan_strip #(.RESYNC_EN(1'b1))`（期望绿）· **L** = `RESYNC_EN(1'b0)`
  （= 负对照，**必须红**，形态 = `trunc_with_crs ≥ 1`；先例口径 = `XFAIL-REPRODUCED`）·
  **M1** = 变异 `fwd = 1'b1`（"tuser 谓词没承重" ⇒ 必须红）· **M2** = 变异
  `fwd = (!RESYNC_EN) || resync || s_axis_tlast`（"开在帧尾而非帧首" ⇒ 必须红）。
  变异件放 `sim/f3_resync/mut/`（照 `sim/p3sim_sw/` 的变异器风格）。
- 判据（**正证据形态**，逐条打印）：
  - **J1**（缺陷消失，主判据）：`frag == 0 && trunc_with_crs == 0`（沿用 t9 的
    `F3 SUMMARY frag/trunc_with_crs` 两项）—— **L/M1/M2 三臂必须 ≥1**。
  - **J2**（形状）：重启后交付的**第一个**帧是 `whole` 且 `tuser=1`（t9 已打印 `dtuser[]`）。
  - **J3**（机制真的跑了 ≠ 空判据）：`stat_resync_words > 0` 且**恰等于**"被丢弃的字数"
    （由 TB 侧独立数：`上游弹出数 − 交付字数`）。**这条是"注入过≠测到了"的解药**。
  - **J4**（守恒，I5）：`上游弹出字数 == 交付给下游的字数 + stat_resync_words`，逐跑闭合。
  - **J5**（不重放）：`stale_words == 0` **且** 没有任何交付帧的内容匹配"重启前已开始的帧
    的非零偏移"（t9 的 `srco != 0` 计数 = 0；注意**不要**拿 t9 的 `stale_words` 守恒式当主判据 ——
    它在变体 A 里本来就等于 0，见 §1.2 的说明）。
  - **J6**（回归未受伤）：重启**之后**的帧逐字节全等（t9 的 `whole` 帧数 = 注入帧数 − 被丢帧数）。
- **t9 原件落点**：`agent_docs/audit_scratch/t9_f3restart/`（三臂原始日志在案，可直接当 L 臂的
  历史基线）。⚠️ 它的 runner `agent_docs/audit_scratch/run_t9.bat` **硬编码了绝对路径**
  （`set ROOT=D:\repo\XCKU5PMini\udp_hls_10g`）⇒ **新门必须自定位**（本仓纪律；
  参见 `sim/p4gates/p4env.bat` / `sim/p5sim` 的两种自定位口味），别把绝对路径抄进新门。

**G2（全链门，板等价配置；挂在 P7b chain 家族）**

- 被测 = **真 wrapper**（板等价宏集：`P7B_10G + P7B_SIM_NOPCS + PCIE_OBS + DEV_USP + APP_MODE +
  DP_156MHZ + P6B_SIM_CLKGEN`，见 `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:39-41`；
  文件表 = `dir /b /s "%ROOT%\rtl\*.v"` **glob** ⇒ **本刀不新增文件 ⇒ 文件表零改动**）。
- 注入 = **I-1（首选）** 或 **I-2**（若 I-1 扰动别的判据）。**injection 必须落在"XGMII 帧流中间"**
  （否则根本不触发 F-3）。
- 判据（形态 + **现成仪器名**，本轮现读定位）：
  (a) witness：`u_dut.dp_rst_dp` 走完一整段（打印 + 断言）；
  (b) `u_dut.u_vlan_strip.stat_resync_words` 在事件后 **> 0**（若 0 ⇒ 说明注入没落在帧中，
      该格写 **"未观测到"**、不许写 PASS）；
  (c) 事件后 DP 侧交付的帧**无一为帧中片段**：该 TB 已有可直接 hierarchically 读的 DP 侧仪器
      （`u_dut.rx_stat_frames` / `u_dut.rx_stat_crc_err` / `u_dut.rx_stat_drop_full|partial`
      —— 见 `tb_p7b_chain.v:1667-1688` 的用法；`u_dut.u_classify.dbg_stat_*` / `dbg_occ`
      —— 见 `:1454,1489-1492` 的用法，注意它用的是 **`force`** 注入，说明该 TB 的注入风格已成立）；
      判"事件前后帧/字节账自洽" + `W54`（app RX 失配）事件后**零增量**；
  (d) 既有判据（F2/F4/等）**逐条不变**。
  ⚠️ **实施前仍要现读该 TB 的判据全表**（`tb_p7b_chain.v` 106 KB，本轮只读了头/时钟/DUT 例化/
  仪器用法，**未逐行读完**）—— 这是本件**唯一一处"需要实施者先现读再定判据落点"的地方**，
  已在 §6-(f) 登记。
- ⭐ **注入风格现成**：该 TB 已在用 `force u_dut.u_classify.dbg_occ = 5'h15;`（`:1454`）+
  `release`（`:1537`）⇒ **I-2（force 内部 `locked` 源）与该 TB 的既有风格一致**，不是新引入的手法。
- ⭐ **计数器不必加端口**：G1/G2 都可用层次名读（`u_vs.stat_resync_words` /
  `u_dut.u_vlan_strip.stat_resync_words`）—— 与 `u_dut.u_classify.dbg_occ` 同款。
  ⇒ §2.2 的 (A7)（端口表追加输出）是**可选**的；**若 §4.5-R1 有任何疑虑，直接跳过 (A7)**，
  改由门用层次名读（xsim 下层次读不依赖综合，计数器不会被剪掉）。

**G3（登记进常驻矩阵）**：G1 必须进 `sim/p4gates/run_matrix_p4dfix.bat` 的 gate 行（声明一次）。
⚠️ 现役矩阵**不含任何 `DP_156MHZ` 门** ⇒ G2 只能挂在 P7b chain 家族，**别指望矩阵替你跑全链**。
⚠️ 反向：`sim/vlansim/run_tb_vlan_strip.bat`（`unit_vlan`）**在矩阵里**，它编的是 `vlan_strip.v`
的默认参数 ⇒ 本刀后它必须**逐字不变绿**（见 §4.3）。

### 3.3 判据/负对照/空判据防护（汇总表）

| 编号 | 判什么 | 正证据形态 | 负对照（必须红） | 空判据风险 |
|---|---|---|---|---|
| J1 | 片段不再交付 | `frag==0 ∧ trunc_with_crs==0` | L/M1/M2 ≥1 | 无（L 臂已实测 =1） |
| J3 | 门真的运行过 | `stat_resync_words == 独立数的丢弃数 > 0` | 把注入挪到"帧间 IFG"⇒ 应 =0（**这是正对照**：证明该计数不是恒正） | ⚠️ 若注入落在 IFG ⇒ 0 是**正确**读数，不许当失败 |
| J4 | 守恒 | 逐跑闭合 | 变异 `rsw` 少计 1（计数面有牙） | 无 |
| J5 | 无重放 | `stale_words==0 ∧ (srco!=0 计数)==0` | 变体 B 接线（`rd_rst_n=reset_n&dp_rst_n`）⇒ **必须红**（`stale_words=26`，已实测） | ⚠️ t9 的 `stale_words` 在现行接线恒 0 ⇒ **不能让它是唯一判据** |
| J6 | 后续帧逐字节 | 全等 | 激励换成"内容可证伪"的图案（t9 的 `cbyte(f,k)` 已满足） | 无 |
| J7（TX 臂，可选） | TX 侧有界自愈 | 线上恰 1 runt + `stat_flush_done>0` + **0 幽灵帧** | 关掉 S_FLUSH 的旧 RTL ⇒ **幽灵帧** | 若注入未落在 TX 帧中 ⇒ 写"未观测到" |

---

## §4 代价与风险

### 4.1 时序（**预算，不是读数** —— 本轮未跑 Vivado）

- 现役基线（`0x24`）：全局/DP 域 WNS **+0.066**（派单给定值），DP 余量 ≈ 1%（6.400 ns 周期）。
- 新逻辑落在 **DP 域 vlan_strip 的组合锥**上，具体是**两条**：
  ① `s_axis_tuser`（→`fwd`）→ `acc_f` → `load_*`/FSM/`hold` 的**使能/数据锥**（加 1 级 AND/OR）；
  ② `s_axis_tuser`（→`fwd`）→ `acc_f`→`rsw` 的**计数器使能**（只驱动 1 个 32 位计数器）。
  ⚠️ **`s_axis_tready`（`:105`）不在改动面** ⇒ 对"`vlan_strip.tready → u_rxcdc.rd_en → LUTRAM 组合读
  → 头字 → 下游"这条跨模块组合链**零新增级数**（Policy D 的一个附带好处）。
- 判据（落地后必做）：新构建的 DP 域 WNS 与 **DP 前 10** 报告面里出现
  `u_vlan_strip/*` 的条数；若 `u_vlan_strip` 相关的端点进入 DP 前 10 ⇒ 触发 **Plan B**：
  把门做成**寄存输出**（`synced` 已寄存，再把 `fwd` 也寄存一拍 = 加 1 拍 RX 延迟，
  `vlan_strip` 是 1-deep 弹性、上游 256 深 FIFO 吸收；代价 = +2 FF，+1 拍帧内延迟，
  不改变帧几何）。
- 结论：**风险中低**（现役 DP 最差族是既存的 `u_tcp_tx/u_fifo_b→tcb`，不是 RX 入口那条）。

### 4.2 资源（预算）

| 项 | 量 | 说明 |
|---|---|---|
| FF | **+1**（`resync`）+（可选）**+32**（`stat_resync_words`） | 落 **DP 域** |
| LUT | **+2~+4** | `fwd`/`acc_f`/`rsw` 的与或 + 4 处 load 条件多一个输入 |
| BRAM/URAM/DSP | 0 | — |
| 若走 Plan B | +2 FF / +0 LUT | 见 §4.1 |

⚠️ 若 `stat_resync_words` 接出但不进窗口（§2.3-(B3)）⇒ 综合会把它当**死逻辑剪掉**（零代价、
零观测）⇒ **"接出"不等于"可读"**，这点必须写进实施记录（别把"接好了"当"有读数"）。

### 4.3 回归影响面（**逐文件清单**）

**① 改动/新增的文件（本刀的全部）**
- 改：`rtl/vlan_strip.v`（§2.2）、`board/wrapper_p4.v`（§2.3）。
- 新增：`sim/f3_resync/{tb_f3_resync.v, run_tb_f3_resync.bat, mut/*}`（G1）；
  `_proj_10g/notes/p9_fix_f3_design_20261014/**`（本件）。
- **不动**：任何 FIFO、任何 `rtl/` 其它文件、任何 XDC、任何构建宏表
  （`board/build_p7b_ku5p.tcl:286` 的 `verilog_define` **不加宏** —— 本刀用参数不用宏）。

**② 必须重跑、且期望"逐字不变"的门**
- `sim/vlansim/run_tb_vlan_strip.bat`（`unit_vlan`，在常驻矩阵里；默认参数 ⇒ I1 保证不变）；
- 常驻矩阵 17 门（`sim/p4gates/run_matrix_p4dfix.bat`）；
- `sim/p6e_pcie/run_tb_p6e_pcie.bat`（全链，含 `DP_156MHZ` ⇒ **会实际打开门**；其激励来自
  真 MAC ⇒ 首个交付字必是 SOP ⇒ 期望判据逐条不变）；
- `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat`（板等价全链，同上）；
- `sim/p5wu_p1p2/run_xvlog_wrapper63.bat`（`d3` 臂 = 板真配置**编译面**）；
- 各 `tb_p5_*`/`sim/p5*` 里直连 `vlan_strip` 的门（默认参数 ⇒ 不变）。

**③ 会被本刀"打红"、需要重新基线的东西（必须如实登记，别当失败）**
- `sim/p4gates` 的**修订指纹 / `FROZEN` manifest**：它是**文件哈希**清单，`rtl/vlan_strip.v`
  内容一变就会"红" —— 这是**设计内**的，重新基线时**必须把"本刀的 diff = 参数 + 门 + 计数"
  写进理由**，并用 §2.4-I1 的结构/行为证据支撑"逐位等价"（**不许用指纹没变来证明等价**，
  也不许用指纹变了来证明不等价）。
- ⚠️ **`stat_resync_words` 不进快照 ⇒ 本刀不碰任何 NW/地址常量**：
  `SNAP_NW_P6E = 71`（`board/wrapper_p4.v:3260`）、未实现地址 `0x14C`、三个指纹门
  （`sim/p5wu_p1p2/run_xvlog_wrapper63.bat:53`、`_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat:33`、
  `run_tb_biz_win.bat:25` 里的逐字 `SNAP_NW_P6E = 71`）、`_proj_pcie/p6e_snap_check.sh:60` 的
  `EXPECT_BID` **全部不动**（只改 `BUILD_ID_V`）。
  ⛔ **反过来说：一旦决定把新字进窗口，上面这一整片都要动**：地址 `0x13C/0x140/0x144/0x148`
  **已被 4 个 MIR 字占用**（`board/wrapper_p4.v:3251-3252`）⇒ 要么"插在 MIR 之前并把 4 个 MIR
  地址整体平移"（波及 `_proj_pcie` 的 PC 侧工具与 `check_window.py`/`tb_biz_win.v` 的地址常量），
  要么"改读侧 `0x20+4*i` 的算术"（波及 `p6e_snap_check.sh:64-73` 的整段公式）。**代价远超收益**
  （理由见 §6-(a)）。⇒ 本件**建议本刀不做**。

**④ 不会被本刀影响的（明说，免得下游重复排查）**：任何 FIFO 单元门、`p3sim*`/`p4*` 数据面门、
`board/build_p6a_ku5p.tcl`/`build_p6b_*.tcl`（单域或另一配置）、`_proj_mdio/**`。

### 4.4 回退方案

- **一行回退**：`board/wrapper_p4.v` 的 (B2) 改回 `vlan_strip u_vlan_strip (`（去掉 `#(...)`），
  或把 `VLAN_STRIP_RESYNC` 置 `1'b0`。⇒ 网表逐位回到本刀之前（I1），**RTL 无需回退**。
- 已烧位流不受影响（参数是编译期常量；回退 = 改一行 + 一次构建）。
- ⚠️ 与"宏关 = HEAD"那类免测金牌不同：**本刀没有宏**，回退点是 `localparam` 的**取值**，
  所以它**不会**被"改默认分支"这件事静默作废（这比宏方案稳）。

### 4.5 风险登记（含触发条件与对策）

| # | 风险 | 触发条件 | 对策 |
|---|---|---|---|
| R1 | `rtl/vlan_strip.v` 内有**按位置**例化的消费者（隐藏我的端口表改动） | (A7) 落地前的 `grep` 复查发现 | 取消 (A7)，计数器留内部；仍不选方案 2 |
| R2 | 新逻辑落进 DP 关键路径 | §4.1 的构建后判据 | Plan B（寄存 `fwd`）|
| R3 | 既有全链门（p6e/p7b chain）**期望值变化** | 其激励里有"非 SOP 开头"的字流 | 先判该变化是"本刀修好的形态"还是"门的前提错"；**不许直接改门期望**（先归因，再决定） |
| R4 | 单域构建意外变色（I1 被证伪） | P4 矩阵/单域门红 | 说明常数折叠失败 → 改用 `ifdef` 包住整段门逻辑（§2.3-(B1) 的等价写法），或退回方案 2 |
| R5 | "接出计数器但不进窗口"被下游读成"板上可判" | 报告措辞 | 本件已在 §4.2 末尾逐字警告；报告必须写"未进快照 ⇒ 板上不可读" |
| R6 | 把"板级未观测到"读成"F-3 不存在" | 措辞 | §5.2 口径 |
| R7 | 失锁把整个 DP 协议状态清掉（§1.3）被误读成"F-3 已修好" | 报告 | §6-(e) 单列登记 |

---

## §5 构建/板测计划

### 5.1 构建批次建议

**建议：独立构建（不与其它 RTL 刀同批）**，理由：

1. 本刀的判据在**仿真侧**（§3），板级只有"回归未受伤"一条正能量 ⇒ 构建的主要产出是
   "网表差异被限定为这一刀"，便于时序归因（§4.1 事后可判"是不是它动的"）。
2. DP 域余量只有 ~1%（`0x24` 的 `+0.066`）⇒ 与别的刀同批会让"余量变化"不可归因。
3. 同批的唯一好处是省一次构建；但**它换不回**"事后想 A/B 还要再构建一次"的代价
   （本刀的回退点是一行，但**位流**必须重建）⇒ 收益不对称。
- BID：`BUILD_ID_V 0x24 → 0x25`（纪律："每次构建必须 bump"，别件多次踩过）；
  几何**不变**（71 字 / `0x14C`）。
- 构建入口 = **`board/run_build_p7b_ku5p.bat`**（⛔ 不许走 GUI 重编 `vivado_prj` 里那份
  `imports/board/wrapper_p4.v` —— 那条"永久禁发"陷阱仍在，见仓根 CLAUDE.md）。
- 归档纪律：`create_project -force` 会摧毁上一轮取证 ⇒ **归档写进构建脚本本身**（既有纪律）。

### 5.2 板级可测性（诚实结论）

- ⛔ **失锁在板上无法受控触发**：MMCM 参考钟 = `sys_clk_p/n` = 板载 Y1（常亮）；
  `MMCME4_BASE.RST` 在 RTL 里**硬接 `1'b0`**（`rtl/clk_gen_p6b.v:211`）；
  `rst_ext = ~reset_n` 走 PCIe 复位，会**同时复位 FIFO**（不构成 F-3 场景）。
  ⇒ 板级**没有**能造出"FIFO 保留 / DP 复位"的入口。
- ⇒ **板级判据 = "未观测到"**（写清：这不等于 F-3 不存在；且**本刀的收口依据是仿真侧读数**）。
- 板上**能做**的三件事（都不判 F-3 本身）：
  1. **身份门**：`0x04 = 0x25` / 71 字 / `0x14C` 回 `0xffffffff` / `LnkSta x4` / 2 BARs；
  2. **回归未受伤**（本刀的主正能量）：既有板级长跑逐字复现 —— TCP 连续下行 `9.1–9.3 Gbps`、
     `mism_bytes=0`、UDP 300 s `9.5336 Gbps / 809,577.8 fps`、双向 `8.9–9.0 Gbps`；
     期望**逐字不变**（I2：稳态 `fwd==1 ⇒ acc_f≡acc`；`0x08` / `carrier` 状态照旧）。
     ⚠️ 读数必须带 `PIN_CPU=` 见证、核对核号；对端网卡中断合并状态要现记（`#68`）。
  3. **冷启动零影响**：上电时 DP 与 FE 同起 ⇒ 释放后第一个交付字必是 SOP ⇒ 门不被激励
     （这条与 2 是同一件事，但值得在长跑里显式确认一次）。

### 5.3 与其它在飞项的排批

- ⛔ **不与 persist/0x1E 那类"已收口但未进位流"的刀混**（会毁掉它们各自的 A/B 锚）。
- ⚠️ 若用户要求"搭车"，本刀**可以**搭（它只加参数不改宏），但**必须**在同一构建前把
  §4.3-① 的清单写进构建脚本的注释（谁在本批里），并接受"余量变化不可归因"。

---

## §6 未决 / 待裁（本件不代裁）

| # | 待决项 | 本件建议 | 理由摘要 |
|---|---|---|---|
| (a) | `stat_resync_words` 是否进快照（W71） | **不进**（本刀） | 地址 `0x13C..0x148` 被 4 个 MIR 字占用 ⇒ 要动 PC 侧工具/地址常量/读侧公式；且**板上无法受控触发 ⇒ 没有验证路径**（"结构性缺席 ⇒ 空判据"）。若将来有别的理由扩窗，可顺带 |
| (b) | 复位窗口内 Policy D（排空）vs H（冻结） | **D** | 零新增回压模态；H 的收益窄且换不回被复位吃掉的那一帧；H 要改丢字口径（不是一行开关） |
| (c) | 是否同时做审计件方向 (ii)（`mac_rx_64` 同源同拍复位） | **不做** | ① 方向 (i) 已结构性覆盖；② (ii) 会把 FE 域重引进 FIFO 写侧复位生成 = F-1 的地雷区（"生产者首个 push 比写域释放晚"的隐含假设会被打破）；③ 收益 0 |
| (d) | F-3 的板级收口口径 = "未观测到" 是否可接受 | 需用户裁定 | §5.2：板上无受控触发入口 |
| (e) | **失锁会清掉整个 DP 协议状态**（§1.3）是否单列一条 | **建议单列**（不在本刀） | 它的后果（连接全断）远大于 F-3 登记的"丢/重一帧"；不拆开 ⇒ 会把"F-3 修好"误读成"失锁无害" |
| (f) | G2 的判据落点需**先现读** `tb_p7b_chain.v`（106 KB）的 DP 侧仪器清单 | 实施者第一步做 | 本件只给到"判据形态"（§3.2-G2），未逐行读该 TB |
| (g) | "事件脉冲清"这一说法在 `P7B_OPEN_ITEMS.md`（§0 第 17 行 + B6 §④）是**错的** | **建议订正该两处** | 见 §0.1；订正文本可直接用 §0.1 的措辞（"按审计件 §A.3 的方向 = DP 侧等 SOP 重同步 / 不是事件脉冲清"） |

---

## 附录 A：证据索引

逐字引文、原始读数、我核过的三处"来源互相矛盾"清单、以及本件引用的全部 `file:line`
（现读于我这一轮）= 同目录 **`EVIDENCE_INDEX.md`**。

## 附录 B：本件的**未做**清单（接手者别当已做）

- 未跑 xsim / 未跑 Vivado / 未上板 / 未碰对端机（派单边界）；
- **未**验证 §3 的门（门本身不存在，只有计划）；
- **未**验证 §4.1 的时序预算（没有综合读数）；
- **未**逐行读 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 与 `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`
  （只读了它们的宏集、DUT 例化名、时钟驱动方式与部分注释）⇒ G2 的判据落点待定（§6-(f)）；
- **未**验证 §1.4 的"伪 fast 段"概率是否真的可构造（只给了量级与构造法）。
