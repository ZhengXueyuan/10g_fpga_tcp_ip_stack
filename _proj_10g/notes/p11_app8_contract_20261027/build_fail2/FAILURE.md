# 0x34 构建 #3（app8 pblock 实验）：仍 TIMING_FAIL，且**更差**

- 输入：同 #2 + `board/ku5p_p7b_app8.xdc`（`u_app` pblock `SLICE_X0Y0:SLICE_X49Y79`）
- 读数：**WNS −0.644 / setup 失败 13,282 / WHS +0.001 / hold·PW 0**（对照 #2：−0.337 / 6,642）
- 结论：pblock 隔离**没有**缓解 DP 布线拥塞，反而把 8×app 的可选布局压小 ⇒ 更差。
  该实验**否定**（新输入的实测结果；不是"重跑到过"）。
- 处置：位流 quarantine（禁烧）；0x35 仍不同批；板级 A/B 仍暂停。
- 下一候选（未实施，登记）：
  1. **8×app 组独立 156.25MHz 域 + CDC**（把 15,328 LUT 完全移出 DP 的 route 竞争；
     需 app TX/RX 两侧 AXIS FIFO；改动大，作为下一轮首选）；
  2. `app_multi8` 的 8 路聚合统计（4×8→1 32 位加）打拍（先定向 STA 确认是否命中）；
  3. 8 个 `app_pattern` TX/RX 图案逻辑降面积/共享（产品级）；
  4. `Performance_Explore` 策略（设计件允许的"另一输入"一次；0x33 的 Explore 曾 −0.023
     vs Extra +0.008，本轮 Extra 已 −0.337 ⇒ 期望不高，但可作对照记录）。
- 口径：F1/OCC/8×12KB 的**板级**仍未做；单元门/变异门读数仍有效（见 build_fail1/FAILURE.md 与 README）。
