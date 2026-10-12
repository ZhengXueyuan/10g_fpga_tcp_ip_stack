# 文档迁移映射表（MAPPING）

**生效日期**：2026-10-13（提交 `0c55470` 纯移动，R100）
**用途**：`_proj_10g/notes/**` 内的历史引用**不重写**（事实源只读层，保持逐字留档），
读到旧路径时按本表解析：`udp_hls_10g/<名>`（根目录旧位置，已不存在）⇒ `agent_docs/<名>`。
全仓其余区域（含 `rtl/ board/ sim/ tb/ tools/ _proj_pcie/` 与根 `CLAUDE.md`）的引用
已于第二轮（提交③，判据 5 修订）全部改写为 `agent_docs/` 前缀。

| # | 旧路径（已不存在） | 新路径 |
|---|---|---|
| 1 | `udp_hls_10g/PORT_NOTES.md` | `agent_docs/PORT_NOTES.md` |
| 2 | `udp_hls_10g/P6B_ACCEPT.md` | `agent_docs/P6B_ACCEPT.md` |
| 3 | `udp_hls_10g/P6B_CDC_AUDIT.md` | `agent_docs/P6B_CDC_AUDIT.md` |
| 4 | `udp_hls_10g/P6B_COMMIT_PLAN.md` | `agent_docs/P6B_COMMIT_PLAN.md` |
| 5 | `udp_hls_10g/P6B_INTEGRATION_REVIEW.md` | `agent_docs/P6B_INTEGRATION_REVIEW.md` |
| 6 | `udp_hls_10g/P6B_REVIEW.md` | `agent_docs/P6B_REVIEW.md` |
| 7 | `udp_hls_10g/P6B_SPEC.md` | `agent_docs/P6B_SPEC.md` |
| 8 | `udp_hls_10g/P6B_SUMMARY.md` | `agent_docs/P6B_SUMMARY.md` |
| 9 | `udp_hls_10g/P6E_OBS.md` | `agent_docs/P6E_OBS.md` |
| 10 | `udp_hls_10g/P7A_COMMIT_PLAN.md` | `agent_docs/P7A_COMMIT_PLAN.md` |
| 11 | `udp_hls_10g/P7A_RESULT.md` | `agent_docs/P7A_RESULT.md` |
| 12 | `udp_hls_10g/P7A_SPEC.md` | `agent_docs/P7A_SPEC.md` |
| 13 | `udp_hls_10g/P7B_SPEC.md` | `agent_docs/P7B_SPEC.md` |
| 14 | `udp_hls_10g/ISSUE_RX_BYTE_CORRUPTION.md` | `agent_docs/ISSUE_RX_BYTE_CORRUPTION.md` |
| 15 | `udp_hls_10g/review_scratch/`（整目录，78 件） | `agent_docs/review_scratch/` |

注：`README.md` 与 `CLAUDE.md` 从未移动，仍在仓库根。行号引用（`Name.md:123`）的
"路径+行号"中路径按本表换、行号不变（纯移动零字节改动，行号物理不变；
其中指向 README 旧行号的引用在迁移前即已过期，见 `checks/migration_proof.md` §6）。
`review_scratch/` 整目录于 2026-10-13 追加轮迁入（提交 `68b5f4d`，78 行 R100）；
目录内 36 个 `.log` 保留历史绝对路径原文（当日工具输出记录），读到
`udp_hls_10g/review_scratch/...` 一律按本行解析。
