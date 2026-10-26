# E1a-1 独立审查处置表（Claude 审查 agent，2026-10-27）

- 被审件：`DESIGN.md`（设计轮版本）+ 现读 RTL/工具
- 审查性质：独立 Claude agent，只读，未改文件；不下 PASS/FAIL 裁定
- 结果：**高 5 / 中 11 / 低若干**；快照算术/拼接顺序核对无误
- 本件 = 逐条处置；**实施已按处置改 RTL/工具**，构建结果另行记录

---

## 高

| # | finding（摘要） | 处置 | 证据/落点 |
|---:|---|---|---|
| H-1 | `present_pending` 跨 app 撤字/换流会陈旧；`app_pattern` 会故意 `pw_valid<=0` | **已修**：RTL 增加 `else if (!s_axis_tvalid) present_pending <= 0`；TB 新增场景 D（先呈现 100 拍→撤字 10 拍→重呈交），断言 L 不包含撤字窗 | `rtl/tcp_tx_frame.v` `g_e1a`；`tb_e1a_draft.v` D；`compile/xsim.log` `E1A_D sum delta=19`。**未加 `cfg_up` 清位**：pending 是全局单帧，多连接下 `cfg_up` 可能属于另一连接，清它会误删有效等待；`app_pattern` 换流路径本身 `pw_valid<=0`，`!tvalid` 已覆盖。 |
| H-2 | 指标漏 `RX_FIN` 尾与 `RX_RING` 等待（第一版 `first_present` 要求 `RX_IDLE`） | **已修**：`first_present = recv_first && s_axis_tvalid && !start_data`，**不要求 `rx_state==RX_IDLE`**；RX_RING/RX_FIN/RX_FLUSH 期间的 app 等待都计入 | `rtl/tcp_tx_frame.v` `g_e1a.first_present`；`DESIGN.md §2.1` |
| H-3 | `tx_arb` 不是纯组合；每帧 ≥1 拍仲裁气泡 | **已订正表述**：数据通路组合、`busy/sel_fast` 寄存器；T_DONE 端点仍 = 末字进 txcdc，气泡计入 L | `DESIGN.md` §0/§2.1 |
| H-4 | 快照几何同步漏了 3 个活门（`tb_p6e_pcie_wrapper` / `tb_p7b_chain` / `tb_biz_win`） | **部分修**：`tb_p7b_chain.v` 0x174→0x1A4、0x184→0x1B4；`tb_biz_win.v` NW 85→97、MIR 自动派生、未实现 0x1B4；`tb_p6e_pcie_wrapper.v` **不在 41 门矩阵且已过期（MIR 地址停在 NW=75/85 世代）** ⇒ 登记测试债（已存 `P7B_OPEN_ITEMS.md §0-75`），E1a 不依赖它 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v:1650-1658`；`_proj_10g/notes/p7b_biz_win/tb_biz_win.v:29-35,61`；`DESIGN.md §4.5` |
| H-5 | `.E1A_EN` 端口/参数位置写错；无宏门会污染所有构建 | **已确认实施正确**：`E1A_EN` 在 `tcp_tx_frame` 参数区，wrapper 放在 `#(...)` 参数表；**并改为 `.E1A_EN(P11_DUAL_DEF)`**（仅 C4 开，C1/C3 输出 0；serial 支恒 0） | `board/wrapper_p4.v:2838-2841`；`rtl/tcp_tx_frame.v:327+` |

## 中

| # | finding（摘要） | 处置 |
|---:|---|---|
| M-1 | per-bank 无竞态论证不完整 | 已补严格论证：`start_data` 含 `!bank_rdy[rx_bank]`、T_DONE 当拍 `bank_rdy[tx_bank]` 仍 1 ⇒ 同拍不可能同 bank 写/读；`ring_start` 与 `start_data` 互斥。TB 覆盖 bank0/1 交替 + ctrl 过滤；**已加 `start_data && done_ev` 同拍断言**（`cyc_assert_fail`） |
| M-2 | 分母对账过松，漏 W14 | 已改用 **W14 = port0 `tcp_tx_frame.stat_frames`** 为主判据；`|hist−ΔW52|≤2`；W83 仅 DUAL 构建作辅。`e1a_latency.sh`/`e1a_metrics.py` 已加 W14 |
| M-3 | max 粘滞且被每会话首帧污染 | 已明确 W96 = **复位以来全局 max**；单窗不做 max 一致性；首帧 `acks_ok` 等待污染已写进边界（max 只作全局上界，稳态尾看 hist） |
| M-4 | sum 32 位回卷 / 空判据 | 已把 `sum ≥ max` 改累计口径；删 `sum ≥ hist` 空判据；改“mean ≥ 帧器最小服务拍”有判别力下界；窗口 ≤10 s、mod 2³² 记 k |
| M-5 | `ts_ctr` 32 位在零窗 persist 60 s 下别名 | **已修**：`{ts_wrap,ts_ctr}` 34 位时间戳；`lat_ok=0`（L≥27.487 s）的帧**跳过** hist/sum/max，不写错值；TB 覆盖 |
| M-6 | 桶表低段浪费 | **已改桶**：0:0-127 / 1:128-159 / 2:160-191 / 3:192-223 / 4:224-255 / 5:256-383 / 6:384-511 / 7:512-1023 / 8:1024-4095 / 9:≥4096；服务 ~193 落在 bin3（0.2 µs 分辨率）。TB 断言同步 bin3 |
| M-7 | 资源/时序估算偏乐观 | 已更新 DP ≈523 FF、LUT 400–700；34 位差/9 比较链已登记；backstop 仍为“失败不烧、只一次构建”；若构建 WNS 太薄按预注册不烧 |
| M-8 | top5 门“每槽 1 个 hold_b”无牙 | 已加**静态 din 映射门**（`check_snap_top5_wired.py` 3b：p7bdp_din[41..52] = e1a_hist/sum/max）；build 门槽集扩到 39..52。源是否寄存器由静态 din 连接 + 板级正对照共同约束；定向 `-from e1a_*_reg` STA 未做（登记） |
| M-9 | 静态门被设计件带偏 | `check_window.py` 顶端已改为 31 项（14 p7bdp + 4 ch0 + 13）并加 W85..W96 din 映射；**PASS=122/FAIL=0**。`check_snap_top5_wired.py` TOPN=14 + 3b；PASS |
| M-10 | 1/16 只能当上下界，不能当修正 | 已改成“下界”：`L_raw ≥ 15/16 L_raw_wait`；不缩小 p99 区间、不用于不含窗口分量的帧 |
| M-11 | `T_DONE` 与 FSM `default` 不等价 | 已登记：当前 FSM 编码只用到 0..4，非法态 5..7 不可达；若将来扩展状态，`done_ev` 必须改用与 `default` 同义的谓词 |

## 低（处置）

- `sum ≥ hist` / `max < 2^32` 空判据：已删/降为格式检查。
- hist 每桶 32 位 ~5368 s 回卷：已登记（E1a 窗口远短）。
- `len_bad` 中止后 pipe 尾字伪样本：登记为契约违规路径；E1a 的正对照/分母对账可发现。
- 每会话首帧含 `acks_ok` 等待：已在 DESIGN §3.1 注明，max 不作稳态尾。
- 伪代码省略号：正式 RTL 已逐项展开（`hist0..hist9`、`{hist9,...}` 显式）。
- bin1 “1460B 服务附近”措辞：已改桶表，服务落 bin3。
- `p7b_snap.sh` 标签：已加 W85..W96。
- 单次构建 backstop：保留；未增加“删桶重试”，避免“重跑到过”。

## 仍未做/登记（不写成已修）

1. `tb_p6e_pcie_wrapper.v` 整表 MIR 地址重派生（测试债；非 E1a 依赖）。
2. `ring_start && start_data` 同拍断言的显式 TB 形式（当前靠结构互斥 + `start_data`/`done_ev` 断言）。
3. 定向 STA `-from e1a_*_reg* -to u_snap_p7bdp/hold_b_reg[*]/D`（M-8 的源寄存器牙）。
4. 构建时序结果（矩阵后一次构建；WNS<0 则不烧）。
5. `too_long` 专字/逐窗 max（E1a-2）。
