=== 0x29 拆刀: 两行改动 (恰两处; 逐字) ===
文件: board/wrapper_p4.v  (CRLF 5025 / loneLF 0 前后一致)

(1) :2185  tcp_tx_frame 例化 -- persist 总开关翻面
-    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b1)) u_tcp_tx (
+    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b0)) u_tcp_tx (

(2) :4377  BUILD_ID_V 常量 + 行尾注释换代 (同一行内)
-        .BUILD_ID_V (32'h00000028),     // ... E12 观测计数器 = 0x28)
+        .BUILD_ID_V (32'h00000029),     // ... PERSIST_EN 拆刀（persist＝关；0x28 内容）= 0x29)

sha256 链:
  before = 3b39c85f509c09b0ce5ffb31014034f34d976f36bd1a2954b504c6e323dd68a2  (= 0x28 轮落盘值, 与 p9_build_0x28 REPORT §① 逐字同)
  after  = dc40acb62c9cac6f7110b68ab3241ab48ad0e3cca91cce8f50bb9fcb947b748f

git diff --numstat = 2 2 (2 插入 / 2 删除; hunk 数 = 2 ⇒ 无其它行被碰)

⛔ 纪律: 不许改任何其它行 -- 满足 (全文件 diff = 两 hunk)。
⚠️ 登记 (非偏离, 供 TL 知): :2170-2184 的上下文注释块 (写 `.PERSIST_EN(1'b1)` = persist **开** 与
   "回退点 = 这一处改回 1'b0") 现描述的是 0x24 起的默认面; 本拆刀把例化翻回 1'b0 后, 该注释块
   与活行**语义相反** (它仍说"现役构建 persist 开")。为守"恰两处"未被改动 ⇒ 建议下一轮
   (无论回退还是再拆) 同批更新该注释块。
