---
name: udp-hls-10g-rx-byte-corruption
description: "udp_hls_10g RX 字节损坏专题已结案 (2026-09-27): 被测设计完全清白, 根因是 peer.exe 经 npcap 的发送路径会打乱帧序"
metadata: 
  node_type: memory
  type: project
  modified: 2026-09-27T10:01:10.679Z
  originSessionId: a43dc219-6b2c-4721-bd7a-260ae74f7393
---

**已结案（2026-09-27）**：`D:\repo\ECO\udp_hls_10g` 的 UDP app **RX 字节损坏**
（线速下 0.05%–0.45% 字节值与图案不符）**根因不在 FPGA** ——
**`peer.exe` 经 npcap 的原始帧注入路径在高速率下会打乱帧顺序**。
整帧置换 ⇒ 对端的连续图案在窗口内"循环旋转"，但字节总数/帧数/FCS 全部精确 ⇒
长时间被误读成"物理余量不足 / droop / 时钟质量"。

**决定性归因实验**（只有它能排掉，多机制互证排不掉）：新工具
`tools/cpp_peer/udpsend.exe`（**故意不经 npcap**，走普通 UDP socket）发**同一图案**到
**同一块板、同一位流、同一线速** ⇒ `UMM/IV/IW` 全部归零，而 `URB/URF` 依旧**精确**
（不是靠丢帧换来的）。换的只有发送路径这一个变量。
`Killer*` 三个服务全停后现象照旧 ⇒ Killer 软件栈同样被排除。

**⚠️ 对项目其余判据的影响（必须记）**：此前所有用 `peer.exe` 在**高速率**下做的测量，
凡**把"第 m 帧"锚在发送侧计数器上**、或**依赖线上顺序**的判据都受同一影响。
板侧**总量**类结论（速率/字节数/丢弃数/时序）不受影响；
**顺序相关的结论必须在非 npcap 发送路径上重做**，或把判据改成顺序无关的形式。
`peer.exe` **降到 ≤100 Mbps 可完全规避**（§18.16：损坏需要高帧速率）。
`IW`（线上帧序探针：16 位寄存器+比较器+计数器，近乎零代价）值得留作常驻探针。

完整证据链（§1–§19：v1–v7 插桩、判据、若干自我纠正）：
`D:\repo\ECO\udp_hls_10g\ISSUE_RX_BYTE_CORRUPTION.md` §19.7–§19.9
（§19.9 未做且不影响结论：`peer.cpp` 里具体哪一行在乱序）。

相关：[[board-measurement-preconditions]]、[[udp-hls-10g-speed-tests-in-cpp]]、[[udp-hls-10g-p6-kickoff]]
