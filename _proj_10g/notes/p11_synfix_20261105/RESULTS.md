# p11_synfix（F2）构建 + 板级结果（0x3C，2026-11-06）

- 设计 = `DESIGN_v2.md`；审查 = `REVIEW_FINDINGS.md`；本文 = 实施/构建/板级原始结论。
- 单变量 = **F2（FIN 优先级）**：`hls/src/layer_tcp.cpp` 的 `T_SYN_RCVD` 握手 ACK 分支加
  `!(flags&TCP_FIN)`（宏 `P11_FIN_FIX`，默认 0；`hls/run_hls.tcl` cflags 传 1）。
  旧码在 `#else`，源码级 inert。**未改任何 RTL、未改快照几何。**

## 1. 实施与 csim（已证）

- csim 双臂（MSVC，`run_csim_p3_all.bat`）：**4/4 臂 PASS，RC=0**；基线 3 条 XFAIL 逐字不变；
  `passed=114/113`（LEGACY/FIX，含新增 `test_p11_zero_data_fin`）。
- 原始判据行：
  ```
  LEGACY: P11_FIN_ARM=LEGACY  P11_TB_ZDFIN FIN1_DEL=0 STATE1=3 FIN2_DEL=1 STATE2=4 NEW_SYNACK=-1
  FIX   : P11_FIN_ARM=FIX     P11_TB_ZDFIN FIN1_DEL=1 STATE1=0 FIN2_DEL=-1 NEW_SYNACK=1
  ```
  STATE：0=T_FREE / 3=T_ESTABLISHED / 4=T_LAST_ACK（`TCP_STATE_PROBE` 直测）。
  ⇒ LEGACY 精确复现 R2（一个 FIN 不释放、槽停在 ESTABLISHED；第二个 FIN 才 DEL 并停 LAST_ACK）；
  FIX 一个 FIN 即 DEL + FREE，新 SYN 可建连。
- 现有用例（CHURN/SYNPAIR/HALFOPEN/P3）在两臂下逐行相同（除新增 ZDFIN 行）。

## 2. 构建 0x3C（已证）

- **HLS 重综合**（构建 bat 不会自动做，v1 的阻断项）：`hls/run_hls.bat` RC=0；
  **All loop constraints satisfied**；Estimated Fmax **156.92 MHz**；
  新归档 `hls_archive_p11fix_fin`（173 .v + 3 .dat）。
- 哈希：`HLS_SRC_HASH = 93dc1327…4e17`、`HLS_NET_HASH = 3fe03211…228d`
  （0x3B 为 `125a71f8…f8c3` ⇒ 网表确实变化）；`udp_echo.v` `a3b55f03…048f`
  vs 旧 `38767094…0538`；`udp_echo_tcp_rx_process.v` `a1925414…b190` vs `00f6d4a1…14ba`。
- 时序：**WNS +0.046 / TNS 0.000 / setup 失败端点 0 / 总端点 400,560；
  WHS +0.010 / hold 0；WPWS 0.000 / PW 0；"All user specified timing constraints are met."**
  路由 0 错。LUT 136,759（0x3B 136,748，+11）、FF/BRAM/URAM 见 `build_ok_0x3C/READINGS_0x3C.txt`。
- 位流：`bits/wrapper_p4_0x3C.bit`，sha256 **`d09d787ceb4cb871d2c5ef9f6ef8a6082bfa92a270d3b9860147f1dbbf9f6a8e`**
  （15,431,261 B）；已烧：BID `0x3C` / MAGIC / marker / UNIMPL 全中、`WINDOW_SCAN_NFF=0`、
  2 BAR、LnkSta x4、两 carrier=1、`0x08=0`。QSPI 零写入。

## 3. 板级 F2 A/B（同工装、同构型、单变量）【已证】

工装 = `leak_then_rawprobe.sh`：`.4` 口 8×4 GiB 一轮（单会话 app 只服务 1–2 条，其余零数据连接被关闭）
→ 板空闲 → 8 个原始 SYN（nsa 内 iptables 抑制内核 RST）→ **W7 增量 = 该时刻 HLS 空闲槽数**。

| 臂 | .4 零数据连接 | 原始探针 W7 增量 | W52（ev/estab） | 结论 |
|---|---|---|---|---|
| 0x3B（负臂） | P1–P6 = 6 条 0 字节 | **+2** | `0x0002/0x0002` | 只剩 2 槽 ⇒ 6 槽被零数据 FIN 泄漏 |
| 0x3C（正臂） | P1–P6 = 6 条 0 字节 | **+8** | `0x0008/0x0008` | 8 槽全空 ⇒ FIN 全部释放 |

原始件 = `raw/leak_then_rawprobe_0x3B.txt`、`raw/leak_then_rawprobe_0x3C.txt`。
（同一工装曾先在 0x3C 的 .4 泄漏轮后测到 W7 +8，见 `raw/raw_probe_after_f2_0x3C.txt`。）
⇒ **F2 修复在板级坐实**：零板→对端数据的连接关闭后不再泄漏 HLS 槽。

## 4. 回归（0x3C）

- 新鲜态 8×16 MB（`verify_0x3B_p0_c.sh`）：**8/8 建立并收满**，conn 0.11–1.45 ms，`poll_tmo=0`。
- 新鲜态 8×256 MB（`verify_0x3B_p0_d.sh`）：**8/8 收满**，`poll_tmo=0`，每条 268 MB。
  （mism 为 `TX_CONTINUOUS` 相位错，按既有口径不是内容判据。）
- ⚠️ **c→d 连续两轮**（先 8×16 MB 再 8×256 MB）：第二轮 3 条完成 / 5 条停顿（8 条均建立成功）；
  **单独重跑 d（新鲜态）= 8/8** ⇒ 状态依赖，属既有 A7 类（上一轮连接关闭时的槽/事件状态），
  **不是 F2 回归**。登记为观测（未定位到行）。

## 5. 残余（未解决，不许当已收口）

1. **R1 半开泄漏**（本轮未修）：原始 SYN/对端放弃重试后，`T_SYN_RCVD` 槽无老化（被动构建）；
   真实对端在重试期间会以同四元组 SYN 原地回收，但放弃后永久占槽。未来方案 = fast 侧
   `ack_seen` 半开回收 + HLS `i_slot_dead` 掩码（不写 cfg），见 `REVIEW_FINDINGS.md` §A。
2. **R3 pending 单槽**（本轮未修）：长 TX busy 下同时两个 SYN 只处理一个（csim ARM_B2 已证）。
3. FIN 分支不校验 seq（F2 扩大了伪造 FIN 的暴露面）。
4. `tcp_stat_no_slot` 仍不可板读（无观测几何变化，本轮未动 Tier A）。
5. `T_LAST_ACK` 老化结构性不可达（若未来需要，用专用计时器）。

## 6. 文件索引

- 源码：`hls/src/layer_tcp.cpp`（宏 + 分支）、`hls/run_hls.tcl`（cflags）、
  `hls/tb/udp_echo_tb.cpp`（ZDFIN 用例 + 臂名）。
- 构建：`run_build_0x3C.bat`、`board/p11_build_cfg.tcl`（`p11fix_fin`）、`board/wrapper_p4.v`（BID 0x3C）。
- 位流/报告：`bits/`、`build_ok_0x3C/`、`hls_archive_p11fix_fin/`、`hls_build/`。
- 板级：`leak_then_rawprobe.sh`、`raw_probe_table.sh`、`raw_syn_burst.py`、`verify_0x3C_f2.sh`、`raw/`。
- 负臂原始件：`raw/verify_f2_neg_0x3B.txt`（.4 轮后 .2 8×4GiB 探针 2/8→0/8，历史签名复现）。

## 7. 收尾板态（2026-11-06 02:3x 现读，fresh 8×256 MB 回归之后）

```
BID=0x0000003c  SCRATCH(0x08)=0x00000000  W6=0x00000038  W7=0x00000011
W52=0x002d0000（高半 = ADD/DEL 事件 45；低半 = 当前 ESTAB 0）
CARRIER_P1=1  CARRIER_P0=1
```

- ⇒ 板 = **0x3C + `0x08=0` + 两 carrier=1**；当前无已建立连接（W52 低半 0）。
  fresh 8×256 MB 的 8 条均带数据正常关闭 ⇒ 按 F2 各自释放槽（W7 为累计 SYN-ACK 数，不是空闲槽读数）。
- **未再跑破坏性探针**（原始 SYN 探针会给表留半开槽），故收尾态按"干净"留板；QSPI 零写入。
