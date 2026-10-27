# 文档索引（docs/ 层）

> 本页是"给人读的文档层"（`docs/`）的总索引；更上层入口在根目录 `README.md`。
> 约定：三层文档各管一段——
> - **`docs/`（本层）**：面向人的导读：进度 / 模块 / 指标 / 术语。
> - **`agent_docs/`**：面向 AI 会话的权威工程件（规格书、验收原件、流水账）。
> - **`_proj_10g/notes/`**：全部原始事实源（每轮施工笔记与板级原件目录），由上面两层引用。

## 本层（docs/）

| 文件 | 一句话说明 |
|---|---|
| [progress.md](progress.md) | 施工进度时间线：已完成（里程碑+验收状态）/ 进行中 / 未来计划 |
| [modules.md](modules.md) | 模块划分：每个模块是什么 / 功能 / 接口 / 关键指标 / 已知缺陷 |
| [metrics.md](metrics.md) | 指标汇总：速率 / 时延 / 资源 / 时序 / 判据达成，全部注明出处与构建配置 |
| [glossary.md](glossary.md) | 术语对照表：技术词平白解释 + 项目黑话翻译（黑话只许出现在这一份） |
| [HUMAN_LAYER.md](HUMAN_LAYER.md) | 人读层清单与审查规则（哪些件算人读层、审查看什么、变更怎么通知——owner 2026-10-13 裁定落地） |
| [INDEX.md](INDEX.md) | 本页 |

## agent_docs/ 层（AI 权威件；由并行的整理轮从根目录移入）

| 文件 | 一句话说明 |
|---|---|
| [P6B_SUMMARY.md](../agent_docs/P6B_SUMMARY.md) | 1G 数据面 156.25 MHz 验收的一页式总览（35/35 判据；**读历史先读它**） |
| [P6B_ACCEPT.md](../agent_docs/P6B_ACCEPT.md) | 上述验收的原始判据表与板级读数 |
| [P6B_SPEC.md](../agent_docs/P6B_SPEC.md) | 1G 跨时钟域施工规格书 |
| [P6B_CDC_AUDIT.md](../agent_docs/P6B_CDC_AUDIT.md) | 跨时钟域审计（F-1/F-2/F-3） |
| [P6B_REVIEW.md](../agent_docs/P6B_REVIEW.md) | 1G 验收的对抗审查 |
| [P6B_INTEGRATION_REVIEW.md](../agent_docs/P6B_INTEGRATION_REVIEW.md) | 集成评审与"空门"核实 |
| [P6B_COMMIT_PLAN.md](../agent_docs/P6B_COMMIT_PLAN.md) | 1G 轮的提交计划（历史） |
| [P6E_OBS.md](../agent_docs/P6E_OBS.md) | 36 字观测窗表（**历史口径**；现役 **85 字**〔0x32，W0..W84〕，权威源 = `board/wrapper_p4.v` 装配段 / `P7B_BIZ_WINDOW.md` §1 的 2026-10-18 更新块） |
| [P7A_SPEC.md](../agent_docs/P7A_SPEC.md) | 10G 物理层施工规格（阶段关卡 0） |
| [P7A_RESULT.md](../agent_docs/P7A_RESULT.md) | 10G 物理层板级验收原件（BER 4.997e-13） |
| [P7A_COMMIT_PLAN.md](../agent_docs/P7A_COMMIT_PLAN.md) | P7a 提交计划（历史） |
| [P7B_SPEC.md](../agent_docs/P7B_SPEC.md) | 10G 数据面施工规格（阶段关卡顺序 / 66 条正判据 + 9 条负对照） |
| [PORT_NOTES.md](../agent_docs/PORT_NOTES.md) | 全仓施工流水账与教训（2026-08 起逐日分节） |
| [ISSUE_RX_BYTE_CORRUPTION.md](../agent_docs/ISSUE_RX_BYTE_CORRUPTION.md) | 专题：1G 时代 UDP 接收方向线速字节损坏（机制未证实，历史遗留） |

## 事实源（_proj_10g/notes/，只读层）

| 想找什么 | 去哪 |
|---|---|
| **权威台账 / 最新续接点** | `_proj_10g/notes/P7B_TL_LEDGER_20261010.md`（§10-166 最新；时点 2026-10-27） |
| 未解决项总表 | `_proj_10g/notes/P7B_OPEN_ITEMS.md`（§0 一张表；每条四格：现状 / 依据 / 为什么没解决 / 下一步） |
| 观测窗现役表（**85 字**，W0..W84） | 权威源 = `board/wrapper_p4.v` 装配段 / `_proj_10g/notes/P7B_BIZ_WINDOW.md` §1（2026-10-18 更新块含 W76..W84 逐字表与逐代回溯） |
| 下一轮开工入口（对端/板卡环境） | `_proj_10g/notes/P7B_LOOP_HANDOFF.md` §6（恢复清单）；板级现场交接见 `p11_board_p3_0x32_20261026/burn/BURN_0x32_20261027_003211.txt` + `raw/POST_SESSION_20261027.txt`（现役 0x32 轮） |
| 里程碑落库件（措辞权威） | `P7B_STAGE{A,B,C}_MILESTONE.md` · `P7B_WU_MILESTONE.md` · `P11_LATENCY_RESEARCH_20261026.md`（延迟研究主线） |
| 独立验收原件 | `P7B_BOARD_STAGEA_ACCEPT.md` · `P7B_BOARD_STAGEB_ACCEPT.md` · `P7B_WU_ACCEPT.md` · `P7B_GATE4_ACCEPT3.md` · `P7B_LONGSEND_ACCEPT.md` |
| 资源研究 | `P7B_BRAM_REPORT.md` · `P7B_BRAM_INVENTORY.md` · `P7B_BRAM_URAM_FEASIBILITY.md` · `P7B_BRAM_TIMING_LATENCY.md` |
| 时延实测 | `P7B_LATENCY.md`（分段流水延迟）；满载占空 / 窗口归因 = `p11_e05_latency_20261027/README_FOR_TL.md`（E0.5） |
| 板级原件目录（按轮次） | `p7b_*board*` / `p8_*` / `p9_board_*` / `p11_board_*` 各目录（`REPORT.md` / `raw/`） |
| 构建读数（按位流版本） | `p7b_build*/READINGS.txt` · `p8_build_0x20/0x21/` · `p9_build_0x22/…/0x2A_20261017/` · `p11_build_0x2{C,D}_20261018/` · `p11_fix_0x30_0x31_20261025/` · `p11_fix_0x31_rom_0x32_20261026/` |
| P11 设计/实施/审查链（2026-10-18 起） | `p9_dual_sfp_plan_20261017/` · `p11_p3_dualstack_design_20261018/` · `p11_p3_impl_20261018/` · `p11_e05_latency_20261027/`（含 kimi 审查原件副本 `artifacts/REVIEW_BOARD_0X32_E05.md` 与回灌 `REVIEW_RESPONSE.md`） |
| 四条真实缺陷（F-3 / RFC 序号 / 换流时序 / MDIO）的设计与实施件 | `p9_fix_{f3,rfcseq,upok,mdio}_design_20261014/`（设计链）· `p9_impl_{f3,rfc,upok,e12}_20261015/` · `p9_fix_mdio_impl_20261015/`（实施） |
| 独立审查件（自对抗审查模式，2026-10-15 起） | `p9_review_*/FINDINGS.md`（折叠-4 / 板级三轮 / 0x28 构建 / B4 板级 / MDIO A+ 五份） |

## 使用建议

1. 五分钟了解现状 → [progress.md](progress.md) §1 + [metrics.md](metrics.md) §1/§5。
2. 查某个模块的底细 → [modules.md](modules.md) 对应章，按出处回原始件。
3. 看不懂的词 → [glossary.md](glossary.md)。
4. 要动手或复核原始读数 → 按上表进 `_proj_10g/notes/`（事实源只读）。
