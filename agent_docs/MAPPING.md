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
| 16 | `udp_hls_10g/_p7a_probe/`（22 件 + 192 件被忽略残渣同迁） | `agent_docs/_p7a_probe/` |
| 17 | `udp_hls_10g/_pcie/`（9 件） | `agent_docs/_pcie/` |
| 18 | `udp_hls_10g/_tmp_w9probe/`（5 件） | `agent_docs/_tmp_w9probe/` |
| 19 | `udp_hls_10g/_tmp_w9verify/`（51 件） | `agent_docs/_tmp_w9verify/` |
| 20 | `udp_hls_10g/audit_scratch/`（132 件） | `agent_docs/audit_scratch/` |
| 21 | `udp_hls_10g/int_scratch/`（40 件） | `agent_docs/int_scratch/` |
| 22 | `udp_hls_10g/p5diag_verify/`（66 件） | `agent_docs/p5diag_verify/` |
| 23 | `udp_hls_10g/p5e_verify/`（6 件） | `agent_docs/p5e_verify/` |
| 24 | `udp_hls_10g/p5f_verify/`（26 件） | `agent_docs/p5f_verify/` |
| 25 | `udp_hls_10g/p6_verify/`（32 件） | `agent_docs/p6_verify/` |
| 26 | `udp_hls_10g/p6a_ku5p_verify/`（18 件） | `agent_docs/p6a_ku5p_verify/` |
| 27 | `udp_hls_10g/p6b_accept_final/`（13 件 + 8 件未跟踪残留同迁） | `agent_docs/p6b_accept_final/` |
| 28 | `udp_hls_10g/p6b_final_verify/`（21 件） | `agent_docs/p6b_final_verify/` |
| 29 | `udp_hls_10g/p5d_verify/`（0 跟踪；42 件被忽略残渣同迁） | `agent_docs/p5d_verify/` |
| 30 | `udp_hls_10g/whs_reroll_probe/`（0 跟踪；3067 件被忽略残渣同迁） | `agent_docs/whs_reroll_probe/` |

**第三批注记（2026-10-13，提交 `dcb3fde` 纯移动 + `30d2253` 引用改写）**：
① 目录内 `.log/.rpt/.out/.txt` 证据文件（xsim/vivado/仪器输出的**绝对路径段**与
命令行回显）刻意保留原文——改写 = 伪造"当日在何处运行"的记录；读到
`udp_hls_10g/<名>/...` 一律按上表解析。② `_proj_10g/**`（848 处）与 `_proj_pcie/`（5 处）
内的引用不重写（事实源/边界约束），按本表兜底。③ `D:\repo\ECO\udp_hls_10g\...` 为
**外仓**路径（2026-09-28 前的开发树，仍在磁盘上），其中的 `<名>/` **不在本表映射范围**
——ECO 锚定路径一律保持原样。④ `sim/p4gates/evidence/sweep_*.txt` 等审计快照
（313 处旧形态）是工具输出的路径清单，按本表解析。

注：`README.md` 与 `CLAUDE.md` 从未移动，仍在仓库根。行号引用（`Name.md:123`）的
"路径+行号"中路径按本表换、行号不变（纯移动零字节改动，行号物理不变；
其中指向 README 旧行号的引用在迁移前即已过期，见 `checks/migration_proof.md` §6）。
`review_scratch/` 整目录于 2026-10-13 追加轮迁入（提交 `68b5f4d`，78 行 R100）；
目录内 36 个 `.log` 保留历史绝对路径原文（当日工具输出记录），读到
`udp_hls_10g/review_scratch/...` 一律按本行解析。
