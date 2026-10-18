# P6 闸 B（K7 @6.4/8.0ns 受控 A/B）归档 — 补充文件

这三个文件由提交 `a719030d`（2026-09-28，P6 闸 B 归档）加入，但当时落在仓库根目录；
2026-10-18 归位到本目录（`git mv`，历史保留）。

| 文件 | 内容 | 出处 |
|---|---|---|
| `board_seq.txt` | K7 板级时序序列捕获（4,342 行；列 = 序号 / 时间 / 值） | 提交 `a719030d` |
| `clockInfo.txt` | Vivado 2025.2 时钟布线调试文件（设备 `xc7k325t-ffg676-2`，K7） | 同上 |
| `tight_setup_hold_pins.txt` | Vivado tight setup/hold pin 列表（`gmii_clk` 域） | 同上 |

- 性质 = **P6 闸 B 的历史取证**，不是现役 KU5P 设计的输入，也未被任何现役门/脚本引用。
- 现役 P7a 的 `clockInfo.txt` 在 `agent_docs/_p7a_probe/clockInfo.txt`（另一份，勿混）。
- 根目录的同名文件已加入 `.gitignore` 锚定规则，防止再次误落。
