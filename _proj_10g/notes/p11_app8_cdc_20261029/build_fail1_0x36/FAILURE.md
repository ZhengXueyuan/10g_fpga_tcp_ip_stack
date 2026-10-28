# 0x36 build #1 — FAILED (dropped CDC constraint; aborted at impl, no bitstream)

- Date: 2026-10-29 ~02:09–02:24
- Inputs: `P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=0 P11_APP8_CDC=1 P11_IMPL_STRATEGY=Performance_ExtraTimingOpt`, BID 0x36.
- Symptom (stdout, `stdout_build1.txt`):
  ```
  WARNING: [Vivado 12-508] No pins matched 'u_appclkgen/u_mmcm/CLKOUT0'.
  WARNING: [Vivado 12-508] No pins matched 'u_clkgen/u_mmcm/CLKOUT0'.
  CRITICAL WARNING: [Vivado 12-4739] set_false_path:No valid object(s) found ...
  ```
  ⇒ both `set_false_path` were dropped; the build bat's `12-4739` gate would have failed it
  regardless of timing. No bitstream was produced (impl killed after the cause was known).
- Root cause: the XDC used the **source-level** instance names. After synthesis the MMCMs are
  inside generate blocks: actual pins are
  `u_appclkgen/g_real.u_mmcm/CLKOUT0` and `u_clkgen/g_hw.u_mmcm/CLKOUT0`
  (measured by `query_mmcm.tcl` on `synth_1/wrapper_p4.dcp`; log in this dir).
- Fix: `board/ku5p_p7b_app8_cdc.xdc` pins updated; comment records the derivation.
- Gate status: **no timing/WNS readings are valid for this run** (CDC path set was timed as
  synchronous). Do not cite this run for timing.
- Post-synth gates that did pass (recorded in stdout): module resolution
  (`app_clk_gen=1/app_multi8_cdc=1`, blackbox 0), `P7B_SNAP_TOP5_SLOTS_OK = 15` (slot 53 included),
  `P11_STA_WPM_REL_WNS = 2.459` / evup0 3.015 / evup1 3.059.
- Next: rebuild 0x36 with the corrected XDC (same strategy; this is a constraint-defect fix,
  not the L-5 timing retry).
