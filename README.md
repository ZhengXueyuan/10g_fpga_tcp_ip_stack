# udp_hls_10g — 纯硬件 TCP/IP 数据面（1G 已验收，10G 已达标，PCIe 通路已打通）

## 这是什么

一块 **XCKU5P** FPGA 开发板（Kintex UltraScale+ 系列芯片，板上有 2 个 SFP+ 万兆光纤插槽、1 个千兆电口、1 条 PCIe 高速扩展插槽），
上面用 Verilog 硬件描述语言实现了一整套 **TCP/IP 协议栈数据面**：万兆光口（万兆以太网物理层 IP + 自写 64 位 MAC——
即以太网"媒体访问控制器"，负责成帧/校验的硬件模块）与千兆电口（RGMII 接口：千兆电口的标准接法）两个前端，
共用同一条 64 位数据流水线（ARM AXI-Stream 流格式：一拍拍传数据、带握手机制，每时钟周期处理一个字）。
TCP/UDP 数据段走纯硬件快路径；ARP、ping、TCP 握手等慢速控制包走用 C 语言编写、经高层综合（HLS，"用 C 代码自动生成硬件"的工具）生成的硬件协议栈。
板子插在 PC 的 PCIe 插槽上，PC 通过由 71 个 32 位寄存器组成的观察窗口读取板内计数器与状态（像读内存一样访问）——
本板没有串口，这是唯一观测手段。
项目终局目标是"TCP 卸载引擎"（TOE）：对上提供 TCP/UDP 调用接口，支撑低延迟行情接收（UDP 组播）与交易发送（TCP 少量连接）。

## 现在处于什么阶段（2026-10-13）

- **1G 数据面**：已板级正式验收，35 条判据全过，956.0 Mbps（2026-09-29）。
- **10G 方向**：物理层验收（误码率上界 4.997×10⁻¹³）→ 五个施工阶段关卡全部收口 → **线速达标**（813,794.7 帧/秒）→
  业务实测 → 长时发送 → 窗口机制分析 → 缺陷修复批次（重放越界 / 零窗探询 / 窗口守卫，均已构建并板级验证）。
- **PCIe 数据通路（里程碑 P8/P9）**：用户指定的"SFP+ → 板上协议栈 → PCIe → 驱动 → PC 程序"链路已打通，
  镜像载荷在 UDP/TCP 两种来源、任意字节对齐下逐字节零失配；PCIe 用户接口已从内存映射模式改造为流模式（AXIS）并完成板级对照验证。
- **P9 增量（2026-10-13，PCIe 通路性能轮）**：测试台架已恢复（重烧 0x23 位流、身份检查全过）；
  线速档补测完成——PC 侧单探针 **8.66 Gbps（入口速率的 94%）**，丢字节机制定案 = 电脑读数据调用内部的固定空档，
  新双缓冲模式让丢字节量再降 **57–70%**；URAM 板内缓冲（32 KB）已实施并过单元门。
- **进行中**：构建 0x24（带 URAM 缓冲的位流）；随后清理剩余未结项（清单见 `_proj_10g/notes/P7B_OPEN_ITEMS.md`）。
- **文档分层（2026-10-13 起）**：`docs/` 给人读（进度 / 模块 / 指标 / 术语四份导读）；`agent_docs/` 给 AI 会话读（规格书、验收原件、流水账）；
  `_proj_10g/notes/` 是全部原始事实源。

## 文档索引（树状根）

```
udp_hls_10g/
├─ docs/                      ← 给人读的导读层
│   └─ INDEX.md               ← 索引根：docs/ 五件导读 + 人读层审查规则 + agent_docs/ 与 notes/ 导读
├─ agent_docs/                ← 给 AI 读的权威工程件
│   ├─ P6B_SUMMARY.md         ← 1G 验收一页式总览（读历史先读它）
│   ├─ P6B_{ACCEPT,SPEC,CDC_AUDIT,REVIEW,INTEGRATION_REVIEW,COMMIT_PLAN}.md
│   ├─ P6E_OBS.md             ← 36 字观测窗表（历史口径）
│   ├─ P7A_{SPEC,RESULT,COMMIT_PLAN}.md
│   ├─ P7B_SPEC.md            ← 10G 施工规格（阶段关卡判据表）
│   ├─ PORT_NOTES.md          ← 施工流水账与教训（2026-08 起逐日）
│   ├─ ISSUE_RX_BYTE_CORRUPTION.md
│   ├─ review_scratch/        ← P6b 对抗审查原始证据（78 件）
│   ├─ （15 个验证产物目录）    ← p5*/p6* 各轮构建与板级验证原始产物（共 441 件）
│   ├─ INDEX.md / MAPPING.md  ← AI 向索引 + 旧→新路径映射表
│   └─ checks/                ← 文档迁移证明与检查证据
├─ _proj_10g/notes/           ← 原始事实源（台账 / 未结项总表 / 各轮板级原件）
├─ rtl/ · board/ · sim/ · tb/ · tools/ · hls/ · _proj_pcie/   ← 源码 / 构建 / 仿真 / 板级工具
└─ CLAUDE.md                  ← 工程规范与铁律（AI 施工纪律）
```

- **人读入口** → [docs/INDEX.md](docs/INDEX.md)（两分钟了解进度，五分钟查到指标）。
- **AI 会话入口** → [agent_docs/P6B_SUMMARY.md](agent_docs/P6B_SUMMARY.md)（1G 收口）与 `agent_docs/PORT_NOTES.md`（逐日流水）；
  最新续接点一律以 `_proj_10g/notes/P7B_TL_LEDGER_20261010.md`（权威台账）与 `_proj_10g/notes/P7B_OPEN_ITEMS.md`（未结项总表）为准。
