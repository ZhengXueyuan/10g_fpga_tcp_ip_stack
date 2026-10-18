# P11 · P3 实施红队审查 — FINDINGS

- 日期：2026-10-19；只读审查；HEAD = `cdd24667`（父 `90307cd1`）
- 被审：`p11_p3_impl_20261018/REPORT.md`、设计件 v1.1（§14 权威）、`git diff 90307cd1..cdd24667`
- 本件不下 PASS/FAIL 裁定；【事实】= 源码/日志/复算直接可见；【推断】= 未在仿真/板级复现；【未判定】= 证据不足。
- 环境：审查期间 `vitis_hls.exe` 正在重跑 HLS；HLS 网表哈希均指矩阵运行时的 **175 个 P2 文件**，已归档到 `p11_p3_build_20261019/hls_archive_p2_dual_ip_max3/`（175/175 与指纹一致）。

## 0. 摘要

**最高优先（影响 2×10G / 8 连接合同本身）**
1. **H-1 跨口同槽 C18**：`win_pool_mgr` 不记每个槽的授出端口；跨口复用同槽时 `port_win` 记错/下溢，旧口 `rel` 可能释放新口刚授出的配额。无门覆盖。
2. **H-2 `slot_port` 翻转时机**：`slow_cfg_demux` 在 ADD 路由拍翻转 `slot_port`，早于旧口 TCB 拆除完成；`retx_pool_shared` 在窗口内丢弃旧口 ring 读写，旧口重传可能读陈旧数据。
3. **H-3 `ACC_MARGIN` 两口共用 port0 ESTAB 计数**：port1 的 `tcp_rx2` 用 `app_estab_cnt`；8+0 全在 port1 时 margin=4096 ⇒ 物理预算 136,906 B > 128KB echo 131,072 B（超 5,834 B）。

**次高**
4. **H-4 HLS 网表与 `P11_HLS_ADV_WND` 无配对硬门**：C3 用 P3 网表不定义宏 ⇒ `i_tcp_adv_wnd` 悬空、SYN-ACK 窗 0/X；C4 用 P2 网表不定义宏 ⇒ 通告 48KB 而实配额 12KB。该分支从未被任何门编译。
5. **H-5 `EXT_QUOTA=0` 回归无归档证据**：报告称 `tb_app_fc`/`tb_p5_flow`/`tb_app_wu` “本轮重跑全绿”，但 32 门矩阵不含、`gates/` 无日志、`sim/p5sim|p5wu` 无新日志。源码静态等价成立，行为回归证据缺失。
6. **M-1 C4 wrapper 门读数与报告相反**：arm A 归档日志 `reply idx=13`（IP_B 在 ch0 有回包，网表是 P2 双 IP），报告写“单 IP 不应答 reply idx=-1”；arm C 未执行；无 Error/Critical/Unisim 硬门。

## 1. 高

### H-1 跨口同槽 C18：`win_pool_mgr` 的 `port_win` 归属错误 / 新配额被旧 `rel` 释放
- 位置：`rtl/win_pool_mgr.v:115-133` / `:136-153`（`old_q = winq_n[slot]`，`pwX_n -= old_q`）；`:84-86`（无 `slot_port`/授出端口记忆）；`hls/src/layer_tcp.cpp:159-165`（`tcp_find` 最低空闲槽）；`:672-674/:738`（旧槽回 free）；`:705-717`（新连接可另一口）；`tb_p3_churn.v:308-315`（只测同口 C18）；`slow_cfg_demux.v:144-150`（DEL 按旧 `slot_port`）。
- 失效链【推断可达】：旧连接 port0 slot N（winq=0x3000, pw0=0x3000）→ HLS DEL 后 slot 回 free → 新 SYN 在 port1 复用 N → 若 `ev_up1` 先于 `rel0`：`old_q=0x3000` 从 **pw1** 扣（下溢为 0x1FD000），`g=0` 新连接零窗；若 `g>0`，随后旧 `rel0` 读 `winq[N]=g` 把新配额归零/回池。`stat_rel_dup=0`，无计数器可见。
- 建议：manager 增 `grant_port[7:0]`（ev_up 时记录授出端口）；rel/C18 的 old 一律从 **授出端口** 扣；加 `stat_c18_cross_port`/`stat_port_win_underflow`；churn 增“同槽跨口复用 + 旧口 gnt 延迟”臂。

### H-2 `slow_cfg_demux` 在 ADD 路由拍翻转 `slot_port` ⇒ 旧连接 retx 读写被丢弃
- 位置：`rtl/slow_cfg_demux.v:139-143`（`slot_port[slot] <= ip_b_match` 在 `S_ROUTE`）；`rtl/retx_pool_shared.v:67-70`（按 `slot_port` 门控）、`:107-110`（mismatch 计数）；`slow_cfg_adp.v:166-177`（DEL 的 state=0 等 `cfg_gnt` 才落地）；`tb_retx_pool_shared.v`（`slot_port` 固定 0xF0，从不翻转）。
- 失效链：DEL 播到旧口后、旧口 TCB 拆除完成前，ADD 路由拍把 `slot_port` 翻到新口；旧口 `tcp_tx_frame` 仍可能 ESTAB/retx，其 ring 读写被判非属主 ⇒ 写丢弃、读拿到陈旧 `r_data`。`stat_retx_owner_mismatch` 非 0 但不进快照。
- 建议：retx owner 改用 **ev_up 时更新的 `grant_port`**（H-1 的 manager 输出），不在 ADD 路由拍翻；旧口在 ev_up 前仍属主；新口 ev_up 后接管。`slow_cfg_demux` 的 `slot_port` 只用于 cfg DEL 路由。加 `slot_port`/owner 翻转定向门。

### H-3 `ACC_MARGIN` 两口共用 port0 的 ESTAB 计数 ⇒ port1 8+0 物理预算超界
- 位置：`board/wrapper_p4.v:1628`（`acc_margin_n = app_estab_cnt`）、`:2314`（port0 接 `acc_margin_eff`）、`:2936`（**port1 `u_tcp_rx2.ACC_MARGIN(acc_margin_eff)` 共用**）、`:3116`（`a2_estab_cnt` 已声明）、`:3158`（接 `u_app_ctrl2.dbg_estab_cnt` 后无消费者）；`rtl/tcp_rx.v:40-46`（N×ACC_MARGIN 进物理预算）、`:317`。
- 算术【事实/纸面】：port1 8×0x3000=98,304；port0 ESTAB=0 ⇒ margin=4096；上界 98,304+8×4096+2,816+1,518+1,500=136,906 > 131,072（128KB），超 5,834 B。port0 有 ≥4 条时 margin=3328 ⇒ 130,762，仅余 310 B。
- 建议：`acc_margin_eff0 <= acc_margin_of(app_estab_cnt)`、`acc_margin_eff1 <= acc_margin_of(a2_estab_cnt)`；`u_tcp_rx` 接 0，`u_tcp_rx2` 接 1；重算/订正 64KB 注释；加 8+0 port1 预算断言。

### H-4 HLS 网表与 `P11_HLS_ADV_WND` 无配对硬门；该分支从未编译
- 位置：`wrapper_p4.v:3751-3756`（`ifdef P11_HLS_ADV_WND` 才接）；`build_p7b_ku5p.tcl:27`（固定 `hls_dir`）、`:330-334`（C3 宏集）；全仓 `P11_HLS_ADV_WND` 仅 wrapper/tcl 注释，无门定义；P2 归档网表 `i_tcp_adv_wnd=0`；P3 网表有端口。
- 失效：C3+P3 网表+无宏 ⇒ 悬空/0/X；C4+P2 网表+无宏 ⇒ 通告 48KB vs 实配额 12KB；C4+P2 网表+宏 ⇒ xelab 报无端口（好的失败）。现有 C4 elab/wrap 门都未定义该宏。
- 建议：build tcl 增 `CFG_HLS_VARIANT`（c1/p2/p3），按配置选 `hls_dir`；构建前 `grep -c i_tcp_adv_wnd` 双向硬判；`P11_DUAL=1 ⇒ 有端口 + 宏`，`P11_DUAL=0 ⇒ 无端口 + 无宏`；P3 网表生成后加 `-d P11_HLS_ADV_WND` 重跑 C4 elab/wrap。

### H-5 `EXT_QUOTA=0` 回归“本轮重跑全绿”无归档证据
- 报告 `REPORT.md:84` 点名三条门；`find` 无日志、`sim/p5sim|p5wu` 无 2026-10-18 后新日志；32 门矩阵不含。源码静态等价成立（6 写点 `if(!EXT_QUOTA)`、读 mux 退化、C15 恢复），但行为回归未被归档证明。
- 建议：重跑三条门并归档 stdout；注册进矩阵或 wrapper gate；报告如实写“读数见路径”或“未跑”。

## 2. 中

| # | 位置 | 事实/风险 | 建议 |
|---|---|---|---|
| M-1 | `gates/sim/tb_p11_c4_wrap.v:247-253`；`logs/p11_c4_wrap_xsim_c4w.txt:39`；`REPORT.md:107` | arm A 只有 `$display`，无 `chk`；日志 `reply idx=13`（P2 双 IP 网表有 IP_B 字节 `8'd4`），报告写 `-1`/单 IP；arm C 未执行；无 Error/Unisim 硬门 | arm A 加 chk（idx≥0/opcode=2/SPA=IP_B）；补 arm C（ch0 SYN/IP_B）；加 P2 G6 同款 Error/Critical/Unisim 硬门（允许 `u_slow_rx.u_ff`）；修正报告/TB 头 |
| M-2 | `hls/tb/udp_echo_tb.cpp` 末尾；`gates/csim/run_csim_p3.bat` | 三臂 failed=3，exe/bat RC=1；脚本只打印 FAIL，不判“失败集合=基线” | 解析 `P11_SUMMARY`，断言 failed==3 且 FAIL 集合=基线；或 3 条改显式 XFAIL；归档 |
| M-3 | `rtl/win_pool_mgr.v:115-153,187-203`；`tb_win_pool_mgr.v:149-152` | slot≥8 只计数，算术仍按 `[2:0]` 别名到 0..7；臂 F 只查计数，状态被改也 PASS | 算术分支外 gate `slot<8`；≥8 保持状态不变；TB 前后快照逐项相等 |
| M-4 | `win_pool_mgr.v:120,140`；`tb_win_pool_mgr.v:23`；`tb_p3_churn.v:60,96` | `occ0/occ1` 全程 0；无 8+0/6+2；无同拍 ev_up+rel | 加 occ=0/0x1000/>pool/两口不同；8+0/6+2 churn；同拍 ev_up+rel 臂 |
| M-5 | `app_ctrl.v:632-639`；`tb_win_pool_mgr.v:39-42` | 双读口未直接门控；unit TB 把 id0/id0b/id1/id1b 接同一索引；churn 未查 redge/fc/wu 值 | 独立 G-P3-2 单元 TB：scan=A 同拍 ev_down=B、init+scan、C18；断言 pa/pb_winq/redge/fc_wq/wu_mark；负控接单读口必红 |
| M-6 | `tb_slow_cfg_demux.v` / `tb_slow_merge2.v` / `tb_slow_demux2.v` | 只有正控，无设计 §9.1 的负控（w2 反向/DEL 按 w2/帧内 o_port 变化/slot=8） | 补 mutant + `run_negctl_slow.bat`；slot=8 显式断言 |
| M-7 | 同上 | G-P3-6 实际只 ch1 ARP+SYN；无 8 连接/计数/TX_DIS；报告称“全链门” | 改名 smoke 或补齐臂；至少 A/B/D 两边断言 |
| M-8 | `run_negctl_{wpm,churn,cfg_c4}.bat`；`p11neg_src.f`/`p11cfggate_src.f` | negctl 不在矩阵；两个 manifest 是死清单 | 每个 negctl 写自定位 gate 入矩阵，或合并进正控 NEGCTL 模式；删死清单 |
| M-9 | `wrapper_p4.v:3601-3602` vs `:3362/:3701` | `slow_merge2.rst_n=reset_n`，上游 `udp_split`/`slow_rx_adp` 用 `dp_rst_n`；MMCM 重锁时 merge 保留 busy/sel，半帧进 HLS | 改 `dp_rst_n`（与上游一致）或登记 F-19 例外并加 MMCM 重锁定向门 |
| M-10 | `wrapper_p4.v:1044-1047` | 注释写 `P11_DUAL_REQUIRES_*` 但无模块；只定义 `P11_DUAL` 不定义 C4/ENFORCE 不被具名门拦；¬APP_MODE 时 `app_winq_rd` 16→1 隐式网风险 | 补 `P11_DUAL_REQUIRES_{DUAL_SFP_A,P7B_10G,DP_156MHZ,APP_MODE,SFP2_MODE_A}`；负控 |
| M-11 | `REPORT.md:197`；`p4gate.py:519-540` vs `:691-694` | 382 条记录对 HEAD 全一致（missing 0/mismatch 0）；存储 `DIGEST_ALL=851d1343`；`e4367d75` 是 compare 按路径排序重算；报告/commit 写成“两次运行”；root 正/反斜杠影响 digest | 报告改为“存储 851d1343；compare 重算 e4367d75”；统一排序键/root 规范化；不需重跑矩阵 |
| M-12 | `paths.txt:62`；`gates/logs/` | 无 `HLS_SRC_HASH`/`NET_HASH` 归档；`hls/tb/**`、`gates/csim/**` 不在指纹 | 记录两哈希；csim/hls TB 入指纹或独立 fingerprint |
| M-13 | `frame_fifo.v:125-126,247-251,228` | D=16384 ⇒ NB=32、main_sel 32 路 OR、边存 16384×9；设计 +27–30k LUT 未显式计第一口 64→128KB 的 +1.1–2.2k LUT | 构建轮定向 STA `u_tcp_echo{,2}/u_fifo/*`；核对 placed LUT/BRAM |
| M-14 | `wrapper_p4.v:372-374`；`build_p7b_ku5p.tcl` | `P11_CFG_SELECT_ONE` 只在 ENFORCE 下硬失败；新 build tcl 忘写 ENFORCE 会静默 legacy | build tcl 断言 ENFORCE=1 + 恰一个 C；打印 `P11_CONFIG`；失败 `error` |

## 3. 低（摘要）

L-1 `stat_grant_zero` 用事件前 pool，同拍双口漏计；L-2 `PORT_CAP` 参数/`winq_q_ev` 未用；L-3 uart_dbg 指针 13 位 vs 14 位；L-4 W79/W80 计数点不同；L-5 check_window 接受两源名不分配置；L-6 死清单 + `minimal_test.cpp` 旧声明；L-7 slow_merge2 TO=4096 半帧未测；L-8 cfg demux 跨口 HOL 无上界；L-9 manager/retx stat 未接快照；L-10 p4gate.py 两个 digest/root 拼写；L-11 报告 851d/e436 叙事；L-12 C4+ModeB 被宽门预占；L-13 ACC_MARGIN 注释 64KB 口径。

## 4. 逐项核对（关键结论）

- **EXT_QUOTA 6 类写点旁路：全部成立【事实】**（`:1069,1095` 复位无消费者；`:1173-1180` ev_up；`:1217-1224` ev_down；`:1336-1342` 超时；`:1364-1370` abort；`:1415-1424` C15）。`o_quota_rel` 四源收敛；`!ev_up` 守卫在现有上游结构下冗余但安全（`to_fire/st_req_now` 带 `!ev_blk`；orphan 门带 `!ev_up&&!ev_down_i`；slow_cfg_adp ev_up/ev_down 不同状态）。
- **双读口实现正确但未直接门控**：`:632-639` id_A=`init_pend?init_slot:scan_id`、id_B=`ev_down_i?ev_slot_i:ev_slot`；`to_fire/st_req_now` 要求 `!init_pend`。
- **win_pool_mgr**：grant 公式/C18 old-first/同拍双口次序/复位正确；跨口归属缺失（H-1）；slot≥8 别名（M-3）；occ 未测（M-4）。
- **retx_pool_shared**：8×N=1、同拍不同槽、owner 门、2 拍读延迟正确；`slot_port` 动态翻转未测（H-2）；非属主读未清零。
- **慢三件**：正控通过；负控缺失（M-6）；TO 未测（L-7）；reset 不同源（M-9）。
- **tcp_tx_frame EXTERNAL_RETX**：OVL/默认两体都接；默认 N=16 行为不变；外部接口位宽/延迟匹配；全链未测。
- **tcp_echo D/AW**：128KB/CQ/FQ/app_rx_occ 饱和/默认 8192 正确；无 128KB unit TB；frame_fifo 32 片选观察点（M-13）。
- **HLS**：MAX=8/adv_wnd/4 处 DEL local_ip 正确；csim 3 条失败 = P2 前基线；H-4 配对风险未编译。
- **wrapper C4**：文本实例计数 2/1 正确；C1/C3 分支未污染；模式宏只在 board/；11 硬门；boot 常量；W79；每口 UDP app；`slow_merge2` reset 例外；`P11_CFG_ENFORCE` 边界。
- **矩阵**：内容绑定 HEAD 382/382（missing/mismatch 0）；HLS 175/175 与归档一致；存储 851d1343；compare e4367d75；报告叙事错误（M-11）。
- **负控**：wpm 3/3、churn 4/4、cfg 9/9 全红有牙；csim 门无机器判据（M-2）；C4 wrap 无 Error 硬门（M-1）。

## 5. 构建/板级前必须收口（优先序）

**A. 必须修/决（否则静默错）**
1. H-1 跨口 C18 的 `grant_port` 归属 + 门。
2. H-2 `slot_port` 翻转时机（retx owner 用 ev_up 的 grant_port；非属主读清零）+ 门。
3. H-3 `ACC_MARGIN` 分口（`a2_estab_cnt`）+ 8+0 port1 预算断言 + 注释。
4. H-4 HLS 网表/宏配对（build tcl 变体选择 + `grep i_tcp_adv_wnd` 双向硬判；P3 网表加宏重跑 C4 elab/wrap）。
5. H-5 EXT=0 三条门重跑 + 归档（入矩阵或 wrapper）。
6. M-2 csim 门机器判据；M-3 slot≥8；M-4 occ/8+0/6+2/同拍 ev_up+rel；M-5 双读口 TB；M-6 慢三件负控；M-8 negctl 入册；M-10 P11_DUAL_REQUIRES_*；M-12 HLS 哈希/指纹；M-14 build ENFORCE 断言。
7. M-1 C4 wrap arm A/C + Error 硬门；修正报告 §2.7/:107。

**B. 建议修（证据/文档）**
M-9 slow_merge2 reset（`dp_rst_n` 或登记例外）；M-11 digest 叙事；M-13 frame_fifo STA/资源；L-7/L-8/L-9 登记；L-1/L-3/L-4/L-5/L-6/L-10..L-13 随手。

**C. 用户/判据所有者裁定**
G-P3-6 是否补齐或改名降级；EXT=0 证据是否足够进构建；跨口复用产品语义（manager 支持 vs 准入层禁止）；`P11_HLS_ADV_WND` 配对是否允许其他组合。

## 6. 证据路径

- 实施报告：`p11_p3_impl_20261018/REPORT.md`（`:84`/`:107`/`:163`/`:197`）
- 设计：`p11_p3_dualstack_design_20261018/README_FOR_TL.md` §4.3/§4.4/§4.7/§5.2/§9.1/§14
- 门日志：`p11_p3_impl_20261018/gates/logs/`；C4 wrap 原始 `p11_c4_wrap_xsim_c4w.txt`（arm A `reply idx=13`；3× RAMB36E2-11 @ `u_slow_rx.u_ff`）
- 矩阵：`sim/p4sim/matrix_p4dfix.log`（`GIT_HEAD=90307cd1`、`DIGEST_ALL=851d1343`、`:406` compare `e4367d75`）；指纹 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261019_005516_{before,after}.txt`
- HLS 归档：`p11_p3_build_20261019/hls_archive_p2_dual_ip_max3/`（175 文件）
- 既有良性 RAMB 判定：`p11_p2a_fix_20261018/FIX_REPORT.md:64`
