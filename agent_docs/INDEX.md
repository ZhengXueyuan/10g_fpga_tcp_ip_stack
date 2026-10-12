# agent_docs/ 索引（AI 会话入口）

> 本目录是**面向 AI 会话的权威工程件层**（规格书 / 验收原件 / 流水账 / 专题），
> 2026-10-13 从仓库根迁入（纯移动 `git mv`，R100，提交 `0c55470`；引用改写提交 `9205fb7` + 判据5修订提交③）。
> 人读导读层在 `docs/`（进度/模块/指标/术语）；**原始事实源只读层 = `_proj_10g/notes/`**，本层所有结论的出处都在那里。

## 十四件权威文档

| 文件 | 一句话 |
|---|---|
| [P6B_SUMMARY.md](P6B_SUMMARY.md) | 1G 数据面 156.25MHz 验收一页式总览（35/35 判据；**读历史先读它**） |
| [P6B_ACCEPT.md](P6B_ACCEPT.md) | 上述验收的原始判据表与板级读数（2026-09-29 正式验收） |
| [P6B_SPEC.md](P6B_SPEC.md) | 1G 跨时钟域施工规格书（判据/闸序/器件事实的权威出处） |
| [P6B_CDC_AUDIT.md](P6B_CDC_AUDIT.md) | 跨时钟域 FIFO 审计（F-1/F-2/F-3 及复位释放门） |
| [P6B_REVIEW.md](P6B_REVIEW.md) | 1G 验收的对抗审查发现清单（含负对照） |
| [P6B_INTEGRATION_REVIEW.md](P6B_INTEGRATION_REVIEW.md) | 集成评审与"真空门"核实（§5 = 空门事故权威记录） |
| [P6B_COMMIT_PLAN.md](P6B_COMMIT_PLAN.md) | P6b 收尾提交方案（历史） |
| [P6E_OBS.md](P6E_OBS.md) | 36 字观测窗寄存器表（**历史口径**；现役窗口以 `_proj_10g/notes/P7B_BIZ_WINDOW.md` §1 为准） |
| [P7A_SPEC.md](P7A_SPEC.md) | 10G PHY（PCS/PMA + gearbox）施工规格，阶段关卡 0 |
| [P7A_RESULT.md](P7A_RESULT.md) | 10G PHY 板级验收原件（BER 4.997e-13） |
| [P7A_COMMIT_PLAN.md](P7A_COMMIT_PLAN.md) | P7a 归档提交方案（历史） |
| [P7B_SPEC.md](P7B_SPEC.md) | 10G 数据面施工规格（阶段关卡顺序 / 66 条正判据 + 9 条负对照） |
| [PORT_NOTES.md](PORT_NOTES.md) | 全仓施工流水账与教训库（2026-08 起逐日；被引用最多） |
| [ISSUE_RX_BYTE_CORRUPTION.md](ISSUE_RX_BYTE_CORRUPTION.md) | 专题：1G 时代 UDP RX 方向线速字节损坏（机制未证实，历史遗留） |

## review_scratch/（对抗审查原始证据目录，78 件）

[review_scratch/](review_scratch/) = P6b 对抗审查 agent 的全部原始产物（自写 TB `rw/tb_rvw_*.v`、
变异体 `rw/mut*.v`、复跑 bat、`rd_*` 各轮 xsim 日志），即 P6B_REVIEW 附录 R 的 A/B 读数出处；
总说明见 [review_scratch/_sec_R.md](review_scratch/_sec_R.md)。2026-10-13 随追加轮从根目录迁入。

## checks/（迁移证明）

[checks/](checks/) 目录 = 两轮迁移 + 追加轮的完整证明：**[checks/migration_proof.md](checks/migration_proof.md)**
（文档迁移：基线三层计数、14 行 R100、逐文件 before→after、HISTORICAL allowlist、
p4env 指纹对、终态 grep）与 **[checks/review_scratch_move_20261013.md](checks/review_scratch_move_20261013.md)**
（review_scratch 整目录迁入：78 行 R100、引用改写计数、留档不改判定、终态证明）。
**改本目录任何文件前必读**——它们登记了哪些引用刻意没改（历史快照/变异副本/标题自指/树图路径段/日志绝对路径）。

## MAPPING.md（旧路径解析表）

[MAPPING.md](MAPPING.md) = 14 行旧路径→新路径映射。`_proj_10g/notes/**` 内的历史引用
按此表解析（该层只读不重写）；读到根相对裸名 `P6B_SPEC.md` 等一律视为 `agent_docs/` 前缀。

## 事实源入口（`_proj_10g/notes/`，只读，不移动）

| 想找什么 | 去哪 |
|---|---|
| 权威台账 / 最新续接点 | `_proj_10g/notes/P7B_TL_LEDGER_20261010.md` |
| 未解决项总表 | `_proj_10g/notes/P7B_OPEN_ITEMS.md`（§0 一张表） |
| 观测窗现役表 | `_proj_10g/notes/P7B_BIZ_WINDOW.md` §1 |
| 里程碑落库件 | `P7B_STAGE{A,B,C}_MILESTONE.md` · `P7B_WU_MILESTONE.md` |
| 独立验收原件 | `P7B_BOARD_STAGEA_ACCEPT.md` · `P7B_BOARD_STAGEB_ACCEPT.md` · `P7B_WU_ACCEPT.md` · `P7B_GATE4_ACCEPT3.md` · `P7B_LONGSEND_ACCEPT.md` |
| 板级原件目录（按轮次） | `p7b_*board*` / `p8_*` / `p9_*` 各目录（`REPORT.md` + `runs/`） |
