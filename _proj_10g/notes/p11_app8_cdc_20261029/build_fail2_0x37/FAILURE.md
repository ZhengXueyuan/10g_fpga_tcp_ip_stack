# 0x37 build (CDC + OCC=1) — TIMING_FAIL

- Date: 2026-10-29 03:51–05:25 (build wrapper started 03:51; synth 03:53–04:07; impl 04:07–05:25)
- Inputs: `P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=1 P11_APP8_CDC=1 P11_IMPL_STRATEGY=Performance_ExtraTimingOpt`, BID 0x37.
- Verdict: **P7B_VERDICT = TIMING_FAIL**; bitstream quarantined `.TIMING_FAIL` (**not burnable**).
- Timing: **WNS −0.629 / TNS (per summary) / WHS +0.010 / WPWS ... (setup fail endpoints >0)**.
  - Worst path: `u_tcp_tx2/u_fifo_b/rptr_reg[6]/C → u_app2/stg_reg[9]/D` (g_hw.clk_out0, 6.400 ns;
    data 7.107 ns = logic 2.023 / route 5.084 (71.5%)).
  - **Note**: the worst path is the **port1 app (u_app2) staging path**, i.e., the OCC=1
    per-connection occupancy/tready logic added into the DP domain; the CDC wrapper itself
    (dp↔app False Path, app self-domain +0.39) is not the failing object.
- Routing: **congestion-bound** — `Route 35-448`: estimated global/short congestion level 5;
  `Route 35-443`: CLB routing congestion; `iter_120_CongestedCLBsAndNets.txt` generated.
  Route overlapped thousands of nodes for ~60 min before depositing.
- Utilization (routed): LUT 138,332 / FF 107,368 / LUTRAM 15,304 / BRAM 109
  (vs 0x36: +2,264 LUT / +888 FF / +16 LUTRAM) ⇒ OCC=1 adds ~2.3k LUT into the DP domain.
- Post-synth gates passed: `SLOTS_OK=15`, `P11_STA_WPM_REL_WNS=1.930`, no 12-4739.
- Decision: **no L-5 retry this round**. Rationale: (a) gap 0.63 ns; (b) congestion level 5 and a
  ~75-min build; (c) the OCC A/B is independently blocked (RX stall hook ineffective, open item
  §0-81), so a 0x37 bitstream would only support identity/smoke tests. A retry with
  `Congestion_SpreadLogic_high` (or an OCC-side area/layout change) is a **new input for next round**.
- Reports archived here (stdout/timing/util/DRC/clkinteract/runme synth+impl/console).
