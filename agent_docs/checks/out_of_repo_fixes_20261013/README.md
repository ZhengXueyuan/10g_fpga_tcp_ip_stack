# 仓外悬挂修复（2026-10-13，owner 裁决「都想办法修复」）

文档迁移（14 件根 .md → `agent_docs/`）后，仓库之外存在三处无法被 git 覆盖的引用层。
本目录留存**改动前完整副本**与 diff 证据，使这些仓外编辑可回滚。

## 修复清单

| 层 | 文件 | 改前命中 | 改后 |
|---|---|---|---|
| 上一级（非 git） | `D:\repo\XCKU5PMini\CLAUDE.md` | 12 行（显式 `udp_hls_10g/<名>.md` + 裸名两种形态） | 全部指向 `udp_hls_10g/agent_docs/<名>.md`；改动面 = 12 行，EOL 逐字节保留（diff：`CLAUDE_parent.diff.txt`） |
| 记忆层（非 git） | `~/.claude/projects/D--repo-XCKU5PMini/memory/feedback_agent_workflow.md` | 2 处（L42/L46 裸名 PORT_NOTES） | 已改 |
| 记忆层 | `~/.claude/projects/D--repo-XCKU5PMini/memory/p4b7-p6-freeze-saga.md` | 1 处（L47） | 已改 |
| 记忆层 | `~/.claude/projects/D--repo-XCKU5PMini/memory/perfv-udp-eco-migration.md` | 6 处（L32/40/53/68/75/148，全部指本仓） | 已改 |
| 记忆层 | `~/.claude/projects/D--repo-XCKU5PMini/memory/xcku5p-mini-10g-board.md` | 4 行（L132/133/154/187） | 已改 |
| 记忆层 | `~/.claude/projects/D--repo-XCKU5PMini/memory/udp-hls-10g-rx-byte-corruption.md` | 1 处 = `D:\repo\ECO\udp_hls_10g\ISSUE_RX_BYTE_CORRUPTION.md` | **不改（FOREIGN）**：指向兄弟仓 ECO 的副本，该文件在盘上仍存在 |
| 用户全局（kimi） | `~/.kimi-code/AGENTS.md` + `~/.kimi-code/skills/` | 0 处（实测） | 无需动 |
| 上一层 | `D:\repo\XCKU5PMini\AGENTS.md` | 0 处（实测） | 无需动 |

## 回滚配方

```bash
cp agent_docs/checks/out_of_repo_fixes_20261013/CLAUDE_parent.before.md /d/repo/XCKU5PMini/CLAUDE.md
cp agent_docs/checks/out_of_repo_fixes_20261013/memory_before/*.md ~/.claude/projects/D--repo-XCKU5PMini/memory/
```

## 终态验证（原始输出）

- 父 CLAUDE.md：14 个旧名 grep = **0 命中**（排除 agent_docs 新形态）。
- memory 5 文件：旧形态残留 = **1 处**，即上表 FOREIGN 行（ECO 兄弟仓副本，盘上存在）。
