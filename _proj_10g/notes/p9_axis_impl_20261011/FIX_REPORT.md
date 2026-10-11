# P9 修正轮（REVIEW.md 的 D 项）— FIX_REPORT

**轮次**: 2026-10-11 深夜 → 2026-10-12 凌晨 · 目录 `_proj_10g/notes/p9_axis_impl_20261011/`
**对象**: 只读对抗审查 `REVIEW.md` 的 D2 / D3 / D4 / D5 / D6 / D7 / D8（+ TL 2026-10-12 **中途修正**）
**边界 (逐条遵守)**: ⛔ 不出位流 · ⛔ 不 bump BID · ⛔ 不做读侧同步 · ⛔ 不烧板 · ⛔ 不碰对端机 ·
只在本机改源码 + 跑 xsim 门（跑门期间 `tasklist` 核过：本机无其它 Vivado/xsim 进程）。
**本报告不下 PASS/FAIL 裁定、不写"时序已解决"、不把"未观测到"写成"不存在"。**

**权威口径**: 本轮的 D4 以 **TL 2026-10-12 板级修正消息**为准（见 §1）；其余 D 项按 `REVIEW.md` 原文。
**门日志 (13 臂)**: 本目录 `logs_d4fix/`（`<arm>.xsim.log` + `<arm>.xvlog.log` + `mut_mut_*_gen.txt`）。

---

## §0 一页结论

| D 项 | 状态 | 一行结果 |
|---|---|---|
| **D4**【行为·中·最重要】 | ✅ 已实现 (含 TL 中途改口径) | `clr` ⇒ **丢弃**残拍 (不发拍) + clr 拍不拉 `dma_req`; 非 clr 停流 ⇒ 排空 + 静置 32 拍后**唯一**一拍短拍; 头注释三处自洽; 门 **12 臂全捕获**、real **100 PASS / 0 FAIL** |
| **D2**【口径·中】 | ✅ 已改 (仅注释) | `axi_regs.v` 5 处 + `wrapper_p4.v` 2 处 "已交付/握手拍" → "**从镜像 aux 口取走** (每 grant +2)"; `diff 173b18d` 实核 = **全部落在 `//` 行** |
| **D3**【证据·中】 | ✅ 已闭环 | 两臂各写不同名日志并**重跑**: `xvlog_head_arm.log` = **6 条 `10-2989`(同名 6 个 udpapp_\*)**, `xvlog_patched_arm.log` = **0 ERROR** ⇒ "HEAD 同 6 条签名" **现在有留存证据、成立** |
| **D5/D6**【文档·低】 | ✅ 已改口径 | 在飞 ≤32 B **现读 RTL 核实成立** (b 16 + 两槽 16, 紧界); `clr` 边界界 **不再是 ≤40 B** —— TL 改口径后 **= 0 B**（旧 ≤16/≤40 全部作废, 理由见 §5） |
| **D7**【证据·低】 | ✅ 已改 | `G8a` 阈值 96→**140**/300 (理论 150 / **实测 149**), 标签同步改准 |
| **D8**【文案·低】 | ⛔ **不在我写面** (如实报) | 该 INFO 在 **`sim/p6e_pcie/tb_p6e_pcie_wrapper.v:732`**（不是 `tb/tb_axis_c2h_stream.v`: 该文件仅 399 行、无此串）; 该目录 = 派单里的**不可写面** ⇒ **未改**, 一行补丁见 §6 |
| **tdata 映射单点** | ✅ | **`rtl/axis_c2h_stream.v:258` = `assign c2h_tdata_map = b_data;`**（唯一映射点; "一行翻转"只改该行 RHS） |

---

## §1 D4 —— 停流/`clr` 语义（TL 中途修正后的**现役口径**）

### 1.1 口径变更（TL 2026-10-12 逐条落实; 取代旧"clr 立即送残拍"）

板级触发（原始件 = `_proj_10g/notes/p9_board_0x22_20261011/runs/D4_BOUNDARY.txt`）:
`clr → cap_en=1` 起测瞬间残拍以**短拍 (`tlast=1`)** 冒出 ⇒ **EOP 早关描述符** ⇒ 宿主首块
`[8,4096)` 全零 + 尾部截断 8,176 B + 第二次 read 超时 10 s（内容本身无损: 偏移 ≥4096 处 0 失配）。

| # | 规则 | 实现 |
|---|---|---|
| ① | **`clr` ⇒ 丢弃打包器残留**（`b` + 两槽; 不发任何拍）+ `dma_words` 归零 + **clr 拍不拉 `dma_req`** | 单点 alias `wire clr_drop = clr;`（`:167`）三处用: b 块清（`:212`）、槽块清（`:227`）、`dma_req` 门（`:202`） |
| ② | 非 clr 停流（`cap_en=0` / `en=0`）⇒ 排空 + **静置 32 拍**后只发**最后一拍短拍** | `stop = (!cap_en) || (!en)`（`:162`）; `quiet` = 连续 32 拍 `drain_wait` 零成交（`:169-182`）; `mv_go`（`:190`） |
| ③ | 正常采集期（`cap_en=1`）恒不发短拍; **整拍恒 `tlast=0`** | `mv_last = mv_full ? 1'b0 : 1'b1`（`:196`）—— 唯一出 tlast 的时机 = 停流收尾短拍 |

**⛔ 与旧口径相反的两处**（TL 明确取代）: 旧"clr 不丢弃残拍 / 把残拍作短末拍送出"（TL 裁定 ④）**已废**;
旧"`stop` 含 `clr`" **已废**。**D6 的 ≤40 B 界随之作废**（那是旧 clr 口径下的界; 新口径 = **0 B**）。

### 1.2 头注释（TL 要求"逐条写清"）—— 三处已自洽

- `:26-32`（tlast 段）: 唯一时机 = **一处**（非 clr 停流静置排空后的最后半拍）; ⛔ clr 不出任何拍。
- `:35-88`（触发式块）: 现役公式 `stop` / `drain_wait` / `qcnt` / `quiet` / `mv_go` / `mv_last` 逐字给出;
  `QUIET_N = 32` **取值理由**（同拍组合成交 ⇒ 32 拍零成交 = 源已空; 在途 ≤8 拍 ⇒ ≥4× 余量; 代价 128 ns）;
  "一个停流事件只允许产生一个包尾"的理由; **nested/重复 stop 不重复发**（结构性）。
- `:62-80`（clr 块）: **窗口边界 ⇒ 丢弃** + 板级形态与后果链一句引上（件名 + "EOP 早关描述符 ⇒
  宿主首块出现洞/零填充/超时"）+ `clr_drop` 三条用法 + 与 AXIS 合同的偏差登记 + "打包器全空 ⇒ 发不出空拍"边界。

### 1.3 门（D4 ④"门要加牙"）

- **新用例**: `G7`（clr 丢弃: 0 拍 + 计数归零 + **新窗口头部无 pre-clr 字节**）·
  `G7x`（clr 连**已成形未交付**的拍也丢弃）· `G11`（停流 + 5 grant 排空 ⇒ 2 整拍 + **只一拍**短尾）·
  `G11b`（**41 grant 长排空** ⇒ 排空期**零** tlast + 收尾恰一拍）· `G12`（重复/nested stop 不重复发）;
  原有"停流后只出一拍 / clr 相关 / 背压 / 吞吐"用例保留（`G4/G4c/G5/G10` 的等待按静置 32 拍改准）。
- **新突变臂 5 个**（每件恰 1 行 / 恰 1 命中 [`MUT_AXIS pattern hits = 1 (want 1)`]）:
  `mut_drain`（丢 `&& quiet` ⇒ 见 stop 就碎片化）· `mut_tlast`（整拍打 stop-tlast）·
  `mut_quiet`（永不 quiet）· **`mut_clrdrop`（`clr_drop → 1'b0` = "clr 又改成发残拍" ⇒ 必须被抓到, TL 点名）** ·
  `mut_qrst`（grant 不归零静置计数 ⇒ 排空期误判"源已空"）。`mut_clrnow`（旧 `flush_now` 锚点）随代码结构消失, 由 `mut_clrdrop` 取代。

### 1.4 读数（13 臂全表; 日志 = `logs_d4fix/`）

| 臂 | VERDICT | FAIL 数 | 红灯面要点（⛔ 只列主抓点） |
|---|---|---|---|
| **real** | **PASS-as-expected** | **0** (100 PASS) | — |
| `mut_last` | MUTANT-CAUGHT | 8 | G4e / G4c-e / G10c / G11b3 / G11b5 / G11b-b / G11b-d / G12d（收尾拍标记消失） |
| `mut_keep` | MUTANT-CAUGHT | 5 | *-keep == 00FF 一族（G4d / G4c-* / G10b / G11b2 / G11b-c） |
| `mut_order` | MUTANT-CAUGHT | 13 | 内容锚一族（G1b / G3g / G3h / G7g / G7x-f / G8b×4 / G11a4…） |
| `mut_req` | MUTANT-CAUGHT | 5 | G3b（grant 数）/ **G3c（满态仍拉 req）** / G3g-* |
| `mut_cnt` | MUTANT-CAUGHT | 10 | G1e / G2d / G7b / G7j / G9a / G11b6 / G11b-e… |
| `mut_clr` | MUTANT-CAUGHT | 3 | G7c / G7j / G9a |
| `mut_stop` | MUTANT-CAUGHT | 9 | G4 一族（en=0 不再算停流 ⇒ 该收尾的不收尾） |
| **`mut_drain`** | MUTANT-CAUGHT | **16** | G4a3 / G4c-b / G11a / G11a2..a5 / G11b / G11b4..5 / G11b-a/b/j / G12a/c/d |
| **`mut_tlast`** | MUTANT-CAUGHT | 8 | G5h / G5h2 / G11a3 / G11a5 / G11b5 / G11b-b / G11b-j / G12d |
| **`mut_quiet`** | MUTANT-CAUGHT | **27** | G4b / G4c-* / G10a0..e / G11* / G12*（收尾拍永不发） |
| **`mut_clrdrop`** | MUTANT-CAUGHT | **12** | **G7g（新窗口头部有陈旧前缀）/ G7x-c/d/e/f（已成形拍没被丢弃）** / G8b×4 / G10b/c/e |
| **`mut_qrst`** | MUTANT-CAUGHT | 6 | **G11b-a / G11b-b / G11b-j（排空第 16 拍冒短拍 = 中途误判）/ G12a/c/d** |

- `G8a` 读数: `[INFO] G8 beats=149 grants=299 (300 clk)` ⇒ 阈值 140 留 ~6% 余量（见 §6-D7）。
- 12 个突变臂的 FAIL 集合**两两不相等**（口径 = REVIEW ④ 的"互不相同"= 两两不相等, 非互斥）。

---

## §2 D2 —— `MIR_DMA_CNT` 口径注释（**仅注释**）

| 文件 | 行 | 旧文 | 新文 |
|---|---|---|---|
| `_proj_pcie/rtl/axi_regs.v` | `:64` | 已交付 AXIS 口的 32 位字数 | **从镜像 aux 口取走的 32 位字数** |
| 同 | `:89-91` | "已交付…"+ **"计数点 = `tvalid&&tready` 握手拍 ⇒ 整拍 +4 / 停流末拍 +2"** | "**从镜像 aux 口取走**…计数点 = `dma_gnt` ⇒ **每 grant +2**; `clr` 归零" + ⛔ 明写"**不是**握手口径; 速率巧合相同、**计数时刻**不同 (在飞 ≤32 B 时 aux 先计)" |
| 同 | `:197` / `:214` / `:320` | 已交付 AXIS 字数 | aux 取走字数 |
| `board/wrapper_p4.v` | `:3257-3259` | "**已交付 AXIS 口的 32 位字数**" | "从镜像 aux 口取走的 32 位字数 (`dma_gnt`, 每 grant +2; ⛔ 不是握手口径)" |
| 同 | `:4664`（例化端口行尾注释） | 交付 AXIS 字数 | aux 取走字数 |

**机检**: `git diff 173b18d -- _proj_pcie/rtl/axi_regs.v` 的**全部 hunk 落在 `//` 行**（本报告 §2 表所列 5 处;
`numstat = 10/7`）⇒ **位域/地址表/逻辑一个字未动**; `wrapper_p4.v` 两处同为 `//` 注释
（该文件在 build 轮已就地改过 `BUILD_ID_V`——未提交; 我只加注释, 不碰其改动）。
⛔ 余项（**不在我写面**, 交还）: REVIEW 指出的工具侧"已交付"措辞与 `p7b_mir_dump.cpp` 的闭合式口径统一
= **D1**, 属 `_proj_pcie/p7b_biz/**`（不可写面）⇒ 未动。

---

## §3 D3 —— `head_negapp` 两臂日志（**已重跑 + 留存**）

**修法**: `run.bat` → `xvlog_head_arm.log`; `run_patched.bat` → `xvlog_patched_arm.log`（原两臂**同名覆写**
`xvlog_head.log` ⇒ HEAD 臂日志被 patched 臂覆盖, md5 双份相同 `6d83a6cd…`）。两 bat 另落
`err10_2989_<arm>.txt` + 行计数。**只编译, 无 xelab/synth**（与 D3 要求一致; 臂 A/B 各 ~5 min, 顺序跑）。

| 臂 | 编译对象 | `10-2989` 条数 | 其它 ERROR | 末行 |
|---|---|---|---|---|
| A（HEAD 件） | `wrapper_p4_head.v` | **6**（`udpapp_mismatch/rx_null/rx_bytes/rx_frames/tx_bytes/tx_frames` @ **:4187-4192**） | +1× `10-8530`（"module 'wrapper_p4' is ignored due to previous errors", 随之而来） | ERROR 行 |
| B（诊断副本） | `wrapper_p4_negapp_patched.v` | **0** | 0 | `INFO: [VRFC 10-311] analyzing module xdma_0` |

**与现文件臂对照**（`logs/negappmode_xvlog.log`, 现文件 = `wrapper_p4.v` 现行本, 6× `10-2989` @ `:4136-4141`）:
`diff` 两臂的 6 个名字集合 ⇒ **逐名相同（"SAME-6-NAMES"）**。
⇒ **结论: "HEAD 同 6 条签名" 现在有留存证据、成立**（行号 4187-4192 vs 4136-4141 的差 = 两版文件在错误点之前的行数差, 同族同签名）。
⚠️ 口径: 两臂的 `files.f` 含**工作树**的 `rtl/*.v`（含本轮 D4 前的 `axis_c2h_stream.v`）; 被比较的 **wrapper 两件是冻结副本** ⇒ 签名对照不受影响（捕获时刻 = 2026-10-11 23:34 / 23:47）。

---

## §4 D5/D6 —— 残差界 / 在飞深度（从 RTL 现读）

1. **在飞（已取走未交付）上界 = 32 B —— 核实成立、是紧界**（现读 `rtl/axis_c2h_stream.v`）:
   `b_data` = **128 位 = 16 B**（`:140`）+ `s0_data`/`s1_data` 各 **64 位 = 2×8 B**（`:137-138`）——
   全模块**只有这三份载荷寄存器**（其余是计数器/指针/valid） ⇒ 在飞 ≤ **16+8+8 = 32 B**;
   "两槽满 + `b` 满"**可达**（tready 慢时: `b` 顶住 ⇒ 两槽照收 2 grant）⇒ 32 是**紧界**。
   工具 `--resid-max-shaper 默认 32` = 按本上界设 ✓（已写进 RTL 头注释 `:87-95`）。
2. **`clr` 边界界**: 旧文档"≤16 B"**低估**; 中途我按"clr 送残拍"口径算出 **≤40 B**
   （在飞 32 B + clr 拍成交未计数 8 B —— 推导: clr 拍开始时最坏 `b` 满 16 + 两槽满 16;
   `b` 那 16 B 在 clr 拍交付, 两槽移进 `b`, 同拍成交 8 B 落进腾出的槽）。
   ⛔ **该 ≤40 B 随 TL 中途改口径一并作废**: 现役 **`clr` ⇒ 丢弃** ⇒ **post-clr 窗口头部 = 0 B
   pre-clr 字节**, 且 **clr 拍不拉 `dma_req`** ⇒ 连"未计数取走"也不存在。
   RTL 头注释 `:62-80` 与 IMPL_REPORT §8.4 已按新口径重写（旧界留档说明作废原因）。

---

## §5 D7 / D8

- **D7（做）**: `G8a` 断言 `rx_n >= 96` 与其"≥1 拍/2 拍钟"标签不符（理论 150）。
  实测 **149**（`[INFO] G8 beats=149 grants=299`）⇒ **阈值收窄到 140**（理论 150 的 ~93%, 留 ~6% 余量,
  仍能抓 ≥2/3 级吞吐回归）, 标签同步改准（"≥140 拍 / 300 拍钟 (理论上限 150, 实测 149)"）。
  ⚠️ 这是**改判据阈值**的例外情形（REVIEW 点名"阈值带过宽 ⇒ 一个把吞吐砍到 2/3 的缺陷仍会绿"）,
  在此明示。
- **D8（未做; 不在写面）**: 单一命中 = `sim/p6e_pcie/tb_p6e_pcie_wrapper.v:732`
  `$display("  [INFO] P9-B-3 W70: %08x -> %08x (300 字灌入, 下游停收)", …)` —— 而循环上界是 **700**（`:721`）。
  派单把它写成 `tb/tb_axis_c2h_stream.v` ⇒ **核到不符, 如实报**: 该文件（sim/p9_axis_stream/, 399 行）
  无此串。**建议一行补丁**: `"300 字灌入"` → `"700 字灌入"`（数字本身自洽, REVIEW ①#19 已用日志数字逐位闭合）。
  该文件目录 = 派单**不可写面** ⇒ 未改。

---

## §6 口径声明（变了什么 / 没变什么）

**变了（逐条）**:
1. `rtl/axis_c2h_stream.v` **行为**: ① `clr` = 丢弃（旧: 送残拍）; ② `stop` 不含 `clr`（旧: 含）;
   ③ `mv_last` 整拍恒 0（旧: `stop` 采样）; ④ 新增静置计数（32 拍）; ⑤ `dma_req` 增加 `!clr_drop` 门。
   ⇒ 触发 (`clr → cap_en=1`) 与停流两条路径**都被重定义**; 正常全流段（`cap_en=1`）**行为逐位不变**
   （`stop=0` ⇒ 新逻辑全不参与; `tlast` 仍恒 0; `dmake_req`/打包/计数不变）。
2. `axi_regs.v` / `wrapper_p4.v`: **仅注释**（D2）; 位域/地址表/逻辑 0 改动。
3. `sim/p9_axis_stream/**`: 门/突变/TB 按新口径加牙（12 臂; 新用例 G7/G7x/G11/G11b/G12）。
4. `IMPL_REPORT.md`: 加**订正块 1**（文首）+ §2-③/§3/§5.1/§8.4/§8.5 就地标记（历史保留、按订正块读）。

**没变（逐条）**:
- 上游 aux 合同（`dma_req`/`dma_gnt`/`dma_data`/空态/优先级）**一字未改**;
  `MIR_DMA_CNT` 的**口径**（aux 取走, 每 grant +2）与地址/名字; 快照几何 71 字 / 未实现地址 `0x14C`;
  丢字节口径（不新增计数器, 全记 `W70`）; `tdata` 打包与字节序**恒等映射**（见 §7）。

---

## §7 `tdata` → 宿主字节序的**唯一映射点**（供"一行翻转"）

**`rtl/axis_c2h_stream.v:258`**: `assign c2h_tdata_map = b_data;   // ← ⭐ 唯一映射点`
（其上 `:257` 声明 `wire [127:0] c2h_tdata_map;`; `:262` `s_axis_c2h_tdata = c2h_tdata_map`）。
现状 = **恒等**。板级若带回落差结论, **只改本行 RHS**; 候选（按 REVIEW §7-3 的三选一判别）:
(a) 8 B 半交换 `{b_data[63:0], b_data[127:64]}`; (b) 16 B 整拍反序; (c) 4 B 字序反序。
⛔ 未证环不变: "XDMA 把 `tdata` 按小端写宿主内存镜像"（PG195 不写字节序）⇒ 仍属**未观测到结论**。

---

## §8 未定项 / 未观测项（⛔ 不许当已答）

1. **`dma_req` 的 `!clr_drop` 门无专属突变臂**（如实登记）: 它在结构上只在"clr 拍恰有可成交的字"
   时可观测, 而 TB 无法在不引入脆弱时序的前提下把"恰在 clr 沿挂一笔待成交"造稳
   （`gr_hold` 放开与 clr 沿的先后差一拍就改变激励）。**与它同源的另一面**（clr 拍丢弃残拍）
   已由 `mut_clrdrop` 覆盖 ⇒ 该门当前只有**构造性论据 + G7 的"头部无陈旧字节"内容判据**, **无独立红面**。
2. **`clr` 落在"已呈现未握手"时刻会无握手撤销 `tvalid`**（AXIS 合同偏差; 软复位式边界, 已写进头注释）——
   C2H 引擎侧行为**未在板级观测**（引擎按"该拍从未发生"处理的推断, 未证）。
3. **`QUIET_N = 32` 的选取** = 构造性论据（同拍成交 + 在途 ≤8 拍 ≤ ≥4× 余量）; **未做**"故意让 aux 饿 32 拍
   但源非空"的病理性对抗（合同外混用两读出口才会出现）⇒ 该假想形态**未覆盖**。
4. **板级连带**: `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 旧口径 clr 判据组在新口径下**实测 6 条 FAIL**
   （`P9-B-5h/5i/5j` + `P9-B-5m1/5m2/5m3`; 其余全过; 我**跑过一次**核对, 日志 `sim/p6e_pcie/xsim_p6e.log`,
   其权威副本仍在本目录 `logs/`）⇒ **需该文件所有者按新口径改写**（`5k/5k2/5m4/5m5` 是读陈旧抓拍缓冲的
   **白过**行, 建议一并加 `str_n` 门）。**不是回归, 是口径变更的下游连带, 未修（不在我写面）。**
5. **D8 未改**（不在写面; 见 §5）; **D1（工具闭合式）** 属 `_proj_pcie/p7b_biz/**`, 不在写面 ⇒ 未动。
6. 板级再测时请注意: 现役 RTL 的 `clr` 语义与 `0x22` 位流**不同**（位流是旧口径）—— 下一次构建
   （bump BID）才带上本修正。

---

## §9 文件清单（本轮改动; 全部在可写面内）

| 文件 | 改动 | 归属 |
|---|---|---|
| `rtl/axis_c2h_stream.v` | D4 行为 + 头注释 + `clr_drop` + tdata 单点 + 在飞 ≤32 B 注 | 可写 ✓ |
| `_proj_pcie/rtl/axi_regs.v` | D2 注释 5 处（**仅注释**, 机检 `diff` 全落 `//`） | 可写 ✓（仅注释） |
| `board/wrapper_p4.v` | D2 注释 2 处（**仅注释**; 文件内含 build 轮未提交的 BID 改动, 未碰） | 可写 ✓（仅注释） |
| `sim/p9_axis_stream/tb_axis_c2h_stream.v` | 新用例 + 改名 ASCII + G8a 阈值 + 等待改准 | 可写 ✓ |
| `sim/p9_axis_stream/mut_axis.py` | 12 臂（新 5 + 锚点跟现源） | 可写 ✓ |
| `sim/p9_axis_stream/run_tb_axis_c2h_stream.bat` | 用法行（臂表） | 可写 ✓ |
| `_proj_10g/notes/p9_axis_impl_20261011/{FIX_REPORT.md, PROGRESS.txt, logs_d4fix/*}` | 本报告 + 日志 | 可写 ✓ |
| (删除) `sim/p9_axis_stream/mut/axis_c2h_stream_mut_clrnow.v` + `sim/p9_axis_stream/mut_mut_clrnow_gen.txt` + `logs_d4fix/mut_clrnow.*` | **陈旧产物清理**: `mut_clrnow` 臂已被 `mut_clrdrop` 取代 (其锚点 `flush_now` 随 D4 改口径消失) ⇒ 防"陈旧突变件/日志被当现役臂" | 可写 ✓ |
| `_proj_10g/notes/p9_axis_impl_20261011/head_negapp/{run.bat, run_patched.bat, xvlog_*_arm.log, err10_2989_*}` | D3 | 可写 ✓ |
| `_proj_10g/notes/p9_axis_impl_20261011/IMPL_REPORT.md` | 订正块 1 + 就地标记 | 可写 ✓ |

⛔ 未动（不可写面/未授权）: `sim/p6e_pcie/**`（除读/跑）· `_proj_pcie/p7b_biz/**` · `tb/**` ·
`board/build_p7b_ku5p.tcl` · 位流/BID/读侧同步/烧板。
