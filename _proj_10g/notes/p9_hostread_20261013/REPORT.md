# P9 宿主读循环诊断+修复轮（2026-10-13）—— 板上 0x23 的 `--stream` (AXIS→C2H) 读路径

> **边界声明**：本轮**未烧位流**（板上现役 0x23 全程未动）、**未改 `rtl/**` `board/**`**、`p7b_tcp_src_diag` 未碰、`p7b_snap.sh` 只读引用（同 md5）。工具侧只改 `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（**追加式**：新选项 `--readlog/--aio/--dual/--buf-huge/--aio-reserve-mib` + 新输出行 `READLOG/READLOG_SUM/MIR_STREAM_CFG2/AIO_*/DUAL_SUM`；**既有输出行的字段名与相对顺序一字未动**；无新选项时 `--stream` 默认路径逐位不变）。**本报告不下 PASS/FAIL 裁定**；「未观测到」不写成「不存在」；口令只作 env 前缀、未落盘。
> （落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为测试 agent 回传。）

## 0. 开工核

| 判据 | 读数 |
|---|---|
| 对端 | `a-MS-7850`（8 核）；`g++ 13.3.0`；hugepages 4×1 GiB 全空 |
| 板身份 | `0x04=0x00000023`（BID 0x23，**全程未烧**）；`0x00=0x50360001`；`0x14C=0xffffffff` |
| 开工态 | `0x08=0x2`（受控停流）→ 按派单解除 `0x08 w 0x0` ⇒ `carrier=1`/`Link detected: yes` ✓ |
| 背景泛洪 | 全程 **~4.91 Gbps / ~404 kfps**（NIC 2 s 窗，开工与收尾两次读数一致）。⚠️ 只有 P9 轮（9.82 Gbps/808.8 kfps）的一半；机理未定位 ⇒ 登记为测量条件（每窗记前后 NIC/softirq 计数） |
| 仪器件 | `/tmp/p9_hostread/p7b_mir_dump` md5 **`7cebded7e9270b6a2d81f5db29843f4d`**（`-O3 -pthread`，BUILD.md §2 口径；源件 md5 `d70ff5c3a50916c1a7e4c64f0910e72c`，仓内/部署件逐字同）；selftest **RC=0/PASS**（44 条 OK；新增 T15/T15b/T13b + T14 新门 5 条） |
| before 臂工具 | P9 轮原件 `/tmp/p9_rate/p7b_mir_dump` md5 **`5ea97067cd90f93c8c47d1f272b04667`**（＝P9 报告 §0 指纹；未改） |
| 同源件 | `p7b_udp_src e0d4da58…d1f92f` · `p7b_snap.sh 6325658a…b084bc`（＝P9 指纹 ✓） |
| 收尾态 | `MIR_CTRL=0x2`（停流）/ `0x08=0x2`（受控停流，`carrier=0`，NIC 计数两读冻结）/ `MIR_STATUS=0x00220000`（level=0）/ `MIR_DMA_CNT=0x03FC8A0E` / 无残留进程 ✓ |

### 0.1 ⛔ 开工第一件：AIO 可用性与**收尾语义探针**（`_tools/aio_probe.c`，板外程序 + 真设备只读）
| 问题 | 实测 |
|---|---|
| `io_submit` 收不收单 | ✅ 收：`PROBE_IO_SUBMIT want=2 got=2 dt=0.023ms` |
| 完成语义 | ✅ `PROBE_EVENT res=4096`；喂流能解开挂起的请求 |
| ⛔ 带在飞 iocb 退出 | ⛔⛔ **D 态挂死**（`kill -9` 无效）。物证：`PROBE_EXIT_BEGIN pending=2` 后进程 8 s 仍在（S 态）；cancel 模式探针**卡在 `__x64_sys_io_destroy` 且 state=D**（`/proc/<pid>/stack` 逐字 `__x64_sys_io_destroy+0xdd`）。**唯一解法 = 让那些传输真的完成**（arm 镜像 + 喂 ~8 MiB 后进程消失 ✓） |
| `io_cancel` | 对"在飞"请求无牙（返回后进程继续走到 `io_destroy` 才卡住） |

⇒ **AIO 修的形态被这一格钉死**：AIO 路径**返回前必须零在飞**（见 §3 两段式）。附带登记：**残留描述符会吃掉下一条流的头部**（实测：2×4 KiB 残留从我喂的 8 MiB 流里吃掉 6,144 B）。

## 1. 判据设计（**先写后跑**）

**仪器**（`--readlog 1`）：`READLOG` 每 read 一行 `i= t= gap_us= mmio_us= read_us= got= pc= w70= dw70= dma= ddma=`，口径：`gap_us`＝上一条记录时刻→本 read 发起（宿主账面+采样，**不含本行 MMIO**）；`mmio_us`＝本行现场读（`snap_w70_dma`＝SNAP_CTRL+轮询+W70+MIR_DMA_CNT 四笔 MMIO，**观测者效应见证**）；`read_us`＝`read()` 调用时长；`Δw70/Δdma` 属 [上一条→本条] 整区间。**T15 硬判据**：`#READLOG==reads ∧ Σddma×4==dwords ∧ Σdw70==drop`（板外已过）。

| # | 判据 | 设计 | 判定口径（跑前定） |
|---|---|---|---|
| C-INST | 仪器自证 | 板外 selftest | PASS + T15/T15b 逐条成立（**已过**） |
| C-H1 | **成分分离**（派单 #2） | 同源同步读、`--chunk∈{1,4,16,32,64} MiB` 阶梯 | 逐 read 报 `gap/mmio/read` 中位 + 丢量反解空档；拟合 `idle(C)=a+b·C` |
| C-C1a | 页级成本 | 32 MiB 档 `--buf-huge`（1 GiB 大页）vs 4 KB 页 | b 塌缩 ⇒ 宿主页级；b 不变 ⇒ 描述符/引擎侧 |
| C-C1c | 描述符粒度 | **只读**驱动源码 | 见 §2.4 |
| C-C2a | 读周转/边界 | `--aio 4`（1 MiB）vs 同步同块 | ΔW70 / pc |
| C-C3 | 采样 MMIO | `--sample-ms 1000` vs `1000000` 同配置 | ΔW70 差异 + `mmio_us` 汇总 |
| C-C4 | 泛洪挤占 | 逐窗 softirq NET_RX Δ + 读侧 CPU | 见 §2.5（含一处仪器失效） |
| C-C5 | 板内/链路天花板 | 入口加压臂（4 源） | 平台化读数 |
| C-C6 | 镜像侧丢粒度 | READLOG dw70 分布 + **≥128 MB 捕获**（fm/洞） | 定性 |
| A/B | **同窗 before/after** | 同 K/源数/SECS/sample_ms/rx-usecs/FIXOFF；单源 + 4 源 | ΔW70（主）、pc、式B、≥128 MB 捕获 |

**窗协议**（`_tools/run_win_hw.sh`，继承 P9 `run_win.sh`）：源**有界**（`--bytes K`）→ 工具 arm（内含 clr）→ 源起 → 收到 K（或驱动超时）→ 前后触发式快照。**主跑一律 `FIXOFF=0`**（绕开源侧 O(off) LFSR 快进；P9 纪律）＋ `--no-verify`（速率/丢字节档）。K=1 GiB、`SAMPLE_MS=1000`、`SECS=6`、`BUFMB=1024`。

## 2. 判别实验（逐项；原始日志 = `runs/*.txt`，对端镜像 = `/tmp/p9_hostread/wins/`）

### 2.1 C-H1 成分分离（chunk 阶梯，同源/同读循环）
| chunk | reads | 入口 MB/s | read_us 中位 | gap_us 中位 | mmio_us 中位 | **idle(丢量反解)** | drop 合计 | 式B |
|---|---|---|---|---|---|---|---|---|
| 1 MiB | 990 | 378.5 | 2 856.7 µs | 0.1 | 5.0 | **92.0 µs** | 34.75 MB | 0 ✓ |
| 4 MiB | 141 | 316.2 | 13 436.6 | 0.2 | 5.0 | 143.3 | 8.71 MB | ✗（窗被源侧快进截断，见注） |
| 16 MiB | 64 | 369.7 | 45 991.4 | 0.2 | 5.0 | 615.1 | 14.54 MB | 0 ✓ |
| 32 MiB | 32 | 317.0 | 106 980.8 | 0.2 | 5.0 | **1 141.2** | 11.82 MB | 0 ✓ |
| 64 MiB | 16 | 380.5 | 178 746.9 | 0.7 | 5.1 | **2 255.6** | 13.57 MB | 0 ✓ |

- **拟合：`idle(C) = 58 µs + 34.3 µs/MiB`** ⇒ **复核 H1 的 `~57 µs + ~36 µs/MiB` 独立复现**（两成分**同时存在**被证实；从"拟合推断"升为"逐 read 直测"）。
- ⭐ **`read_us 中位 ≈ chunk/入口率 + idle`**（1 MiB：2770+92=2862 vs 实测 2856.7；32 MiB：105834+1141=106975 vs 106981；64 MiB：176357+2256=178613 vs 178747，三点全中）⇒ **"空档"发生在 `read()` 调用内部，不是两次 read 之间**：`gap_us ≈ 0.1–0.7 µs`（宿主账面/采样可忽略）。⛔ 由此**推翻"块间空档"这一措辞**：正确形态 = "**read() 内部的引擎空档**"。
- 4 MiB 档注：该窗源侧 `--off` 触发 LFSR 快进 ~3.5 s ⇒ 工具看门狗先响（窗截断，式B 红属**协议性**）；逐 read 数据仍有效。等价可复现档 = 32/16/64 MiB 三点，直线性极好（R²≈0.999）。

### 2.2 C-C1a 页级成本（1 GiB 大页 vs 4 KB 页；同为 32 MiB 档、同日同源）
| 臂 | 入口 MB/s | read_us 中位 | **idle** | drop/read | 归一化 b' |
|---|---|---|---|---|---|
| N32b（4 KB 页） | 317.0 | 107 000.8 µs | **1 139.5 µs** | 371 KB | ~34.3 µs/MiB |
| H32（1 GiB 大页） | 368.7 | 91 833.1 | **855.4 µs** | 310 KB | **~24.9 µs/MiB（−27%）** |

⇒ **每 MiB 项只塌缩 ~1/4**：它不是纯"每 4 KB 页 GUP/缺页"成本，而是**页条目级**成本（驱动仍按 4 KB 建 SG、仍逐条目 `put_page`+`dirty`；大页只让 `get_user_pages_fast` 与 `dma_map_sg`(IOMMU 粒度) 变便宜）⇒ §2.4。⚠️ 两臂入口率不同（317 vs 369 MB/s），`idle` 已按各臂入口归一，但 b' 的差留有入口率偏差的口子（登记）。

### 2.3 C-C2a 读周转 / `--aio`（流水提交读）
| 臂 | chunk/depth | pc | dW70 | **每 MiB 丢** | 式B | 收尾 |
|---|---|---|---|---|---|---|
| AI4 | 1 MiB × d4 | 1 061.05 MB | 12.11 MB | **11.4 KB/MiB** | 0 ✓ | `pending_end=0`（干净） |
| AI2M | 2 MiB × d3 | 1 061.66 MB | 11.74 MB | 11.0 KB/MiB | 0 ✓ | 0 ✓ |
| S1M（同步 1 MiB 对照） | 1 MiB | 1 039.14 MB | 34.50 MB | 33.2 KB/MiB | 0 ✓ | — |

⇒ **AIO 拿掉了"固定项"**（同步 1 MiB 3.21% → AIO 1.08%；与 P9 轮同块 3.2% 逐字吻合），**但拿不掉"每 MiB 项"**（1 与 2 MiB 块同为 ~11 KB/MiB）——与 §2.4 的机制**定量一致**。

### 2.4 C-C1c 驱动源码**只读**核查（原件 = `runs/driver_{cdev_sgdma,libxdma}.{c,h}`；对端现役驱动 = 该树构建）
1. **每次 read() = 一整张 SG 表 + 一串串行传输**：`char_sgdma_read_write` 先 `char_sgdma_map_user_buf_to_sgl`（`get_user_pages_fast` **按 4 KB 页** + `sg_set_page` **逐页一条**）→ `dma_map_sg` → 传输循环（每段 ≤ `engine->desc_max`；`enable_st_c2h_credit=0` ⇒ **desc_max=0x800=2048**，`/sys/module/xdma/parameters/` 实测）**每段"建表→排队→等完成"**（下一段的表在上一段完成后才建）→ 返回前 `char_sgdma_unmap_user_buf`（**逐页 `set_page_dirty_lock` + `put_page`**）。
2. **引擎每段结束即停**：`transfer_init` 把每段最后一条描述符写成 `STOPPED|EOP|COMPLETED`；重启由**工作队列** `xdma_isr → schedule_work(&engine->work) → engine_service → engine_service_resume` 完成。
3. ⭐⭐ **AIO 路径的同一段 unmap 跑在"引擎 service 上下文"**：`engine_transfer_completion` → `transfer->cb->io_done(...)`=`async_io_handler` → `char_sgdma_unmap_user_buf`——**排在 `engine_service_resume`（重启引擎）之前** ⇒ 逐页成本**直接变成引擎空档**（同步路径里同一段在**用户线程**）。
4. ⛔ **看门狗在驱动层被吞**：`xlx_wait_event_interruptible_timeout` = `do { __ret = wait_event_interruptible_timeout(...); } while ((__ret<0) && (jiffies<expire));` ⇒ **信号被重试吞掉**，阻塞的 C2H read **只在 `c2h_timeout`(10 s) 到期才返回**。⇒ 每窗收尾 = 驱动 10 s 超时；工具侧 `--seconds` 只是把 `wd_fired` 置起来（**被误标成"看门狗截断"**——这正是复核 L1"alarm 先响、驱动超时后到"的**机理**）。本轮所有窗墙钟 ~16 s 皆由此（数据在 ~4 s 前已到齐）。

### 2.5 C-C3 / C-C4
| C-C3 | sample_ms=1000（A1） | sample_ms=1000000（A1N2） |
|---|---|---|
| dW70 | 5.460 MB | **5.462 MB（逐字同）** ⇒ **未观测到采样率对丢字节的影响** ✓ |
| 仪器自身 | `mmio_us` 中位 **5.0–5.2 µs/read**（四笔 MMIO）⇒ 观测者效应 ≈ 每 MiB 档 ~1.8 KB 的丢量当量（登记） |

（A1N 首次跑 pc=0：原因 = 上一步收尾把板留在受控停流态（link down），**已定位并登记**，非异常。）

**C-C4**：逐窗 `softirq NET_RX` Δ：B1=733k / A1=741k / B4=378k / A4=443k（同量级）。⚠️ **一处仪器失效（如实登记）**：`rstat_*.log` 采的是 `timeout` 包装进程（非工具进程）⇒ `utime/stime` 恒 0（`threads=1`）——**本轮读侧 CPU 见证无效**；替代证据 = `read_us 中位 ≈ 数据时间`（读循环未被 CPU 饿；若被挤占 read_us 会显著大于数据时间）。⇒ **未观测到泛洪挤占的独立影响；同位素臂（抬 rx-usecs/绑核）本轮未跑（登记）**。

### 2.6 C-C5 / C-C6
- **C-C5（4 源加压，入口 ≈1.26 GB/s）**：B4 pc=1040.19 MB/dW70=29.70 MB；A4 pc=1061.16 MB/dW70=8.93 MB。**未观测到"宿主收数平台化"**（丢率随配置变、不落在 1.08–1.12 GB/s 的固定平台）⇒ C5 作为"宿主天花板"的形态**不成立**。
- **C-C6（丢的粒度）**：⭐ **`MIR_VERIFY first_mismatch` 在四个不同块径的窗里逐字复现 `2^k + 2104`**（1 MiB→1,050,680；4 MiB→4,196,408；8 MiB→8,390,712（P9 轮）；256 MiB 捕获→4,196,408）——`2104 = 2048(镜像 FIFO) + 24 + 32(在途)` = **管线容量**，即"第一个洞出现在**第二块边界后 2104 B**"。逐块 dw70 分布 = **双模**（~42 KB 与 ~0–1 KB 两簇；42 KB ≈ 4 MiB 档一整段 epilogue 的量级）⇒ 丢是**块边界处**的结构性事件（与"每段停-重启窗口"同形），**不是**帧粒度、**不是**逐字节渗漏。

## 3. 修复（**按主导成分**）

**诊断结论（数据 + 驱动源码双证）**：读循环总空档 = **固定 ~58 µs/read（等待/唤醒/段边界）** + **~34 µs/MiB（逐 4 KB 页 SG/映射/解映射/put_page；其中 ~3/4 为"页条目级"成本，大页只吃掉 1/4）**；两者都在 `read()` 调用内部；"每 MiB 项"在 **AIO 路径被搬进引擎 service 上下文、直接挡住引擎重启** ⇒ **AIO 只能去掉固定项**（实测 3.21%→1.08%，且不随块径变）。

**修复主臂 = `--dual 2`（两线程交错同步读，块 ≤ 4 MiB）**：奇偶分块 + 起步错拍 δ（默认 2 ms），使"上一条 read 的 epilogue"与"下一条 read 的传输"**重叠**（同步路径的 epilogue 在**用户线程**，不占引擎 service 上下文 ⇒ 重叠有效）。
- **环安全**：每块 ≤ 4 MiB（≤1024 描述符）⇒ 两笔在飞 ≤ 2048 = 环全宽；每线程只在自己上一笔**返回后**才发下一笔。
- **顺序**：单流按提交序落各块缓冲；δ 给"发起序"时间裕量（**非硬保证**），乱序会被内容判据抓住（**可检测、不静默**）。
- **登记（本轮未做，留待裁定）**：① 驱动侧修法 = 把 `char_sgdma_unmap_user_buf`（或 `set_page_dirty_lock`）移出 `engine_service` 上下文（deferred work）⇒ 理论上再吃掉 ~34 µs/MiB；源码已在（`dma_ip_drivers-patched`），但**重编+重载内核模块超出"宿主读循环"范围且会动台架共享件**，故不动。② 板内缓冲（URAM）加大 2 KB FIFO 即可吸收块边界窗口；属 RTL/位流改动，本轮禁。

## 4. 同窗 A/B（before = 未改工具 5ea97067 / after = 新工具 7cebded7；同 K/源/SECS/sample_ms/FIXOFF/rx-usecs）

| 档 | 臂 | 工具/模式 | chunk | pc | **ΔW70** | 丢率 | 式B |
|---|---|---|---|---|---|---|---|
| **单源**（K=1 GiB, unpaced） | **before** | 老工具 · 同步 | 32 MiB | 1 056.96 MB | **12.77 MB** | 1.19% | 0 ✓ |
| | **after** | 新工具 · `--dual 2` | 4 MiB | 1 065.35 MB | **5.46 MB** | **0.51%** | 0 ✓ |
| **4 源**（K=1 GiB 总） | **before** | 老工具 · 同步 | 32 MiB | 1 040.19 MB | **29.70 MB** | 2.78% | 0 ✓ |
| | **after** | 新工具 · `--dual 2` | 4 MiB | 1 061.16 MB | **8.93 MB** | **0.83%** | 0 ✓ |

- **主判据 ΔW70：单源 12.77→5.46 MB（−57%，2.34×）；4 源 29.70→8.93 MB（−70%，3.33×）**；pc 同步上升（+0.8%/+2.0% 的 K 份额）⇒ "少丢 = 多收"闭合。
- **式B（`K − taken − dW70 ∈[0,24]`）四臂全 0（逐字）** ✓。
- **内容档（≥128 MB 捕获）**：`CAPD`＝dual 4 MiB、K=256 MiB、`--pat-off` 自动、**verify 开**：`pc=264,241,152 B`（252 MiB ✓）、`dW70=907,208`（0.34%）、**式B=0**、`MIR_VERIFY rc=1 first_mismatch=4,196,408`；文件留对端 `/tmp/p9_hostread/mir_CAPD.bin`（264,241,152 B，md5 `d8ea957629a31401da29d8e91a8b479b`）供离线定内容。
- **顺序/正确性旁证**：`ORD1`（dual，K=64 MiB，`--mbps 100` 低速）15 块全数完成（pc=62,914,560=15×4 MiB 整齐）、式B=0。
- **负对照臂（同工具、关修复）**：`S1M`（同步 1 MiB）=34.50 MB ↔ `D1M`（dual 1 MiB）=27.46 MB ⇒ 1 MiB 块上 dual 只拿掉 ~20%，**4 MiB 块上才拉开**（机制见 §2/§3）。

## 5. 未竟项（⛔ 不许当已答）
1. **每 MiB 项只降 27%（大页）/dual 覆盖一部分**；剩余 ~5.4 KB/MiB（单源）**不是宿主读循环能继续压的**——需 ① 驱动侧 deferred unmap 或 ② 板内缓冲（URAM），两者**未做**。
2. **"~42 KB vs ~0–1 KB"双模 dw70 的机理未定位**（怀疑 = 块边界停-重启窗口是否与 epilogue 重叠的分叉；无逐拍见证）。
3. **C4 同位素臂未跑**；`rstat_*` 读侧 CPU 见证**仪器失效**（采到 `timeout` 包装进程）。
4. **起步 δ 只给时间裕量**（非硬保证）；本轮 dual 窗都带内容旁证，但**未构造"故意乱序"负对照**。
5. **`c2h_timeout=10 s` 未改** ⇒ 每窗收尾固定多花 ~10 s 墙钟（读数不受影响）；工具措辞仍把驱动超时标成"看门狗截断/真读错"（**措辞待修**）。
6. 未跑：`--aio` 4 MiB×d2（环全宽、安全性待评）、`--dual + --buf-huge` 组合、`W57/W58` 相关档。

---
*本件 = 宿主读循环诊断+修复轮记录；判据层 PASS/FAIL 裁定权在判据所有者（用户）。原始件：`runs/*.txt`（20 窗）+ `runs/driver_*`（驱动源码只读副本）+ `_tools/`（仪器源 + 窗协议 + 分析器）；对端镜像 `/tmp/p9_hostread/`。*
