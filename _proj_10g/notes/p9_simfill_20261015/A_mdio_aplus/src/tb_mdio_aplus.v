//=============================================================================
// tb_mdio_aplus.v -- mdio A+ variant arm (E7), TOP-LEVEL functional simulation.
//=============================================================================
// Round: _proj_10g/notes/p9_simfill_20261015 (SIM BACKFILL, 2026-10-15).
// Basis: _proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2r4.md (v2r2+v2r3+v2r4)
//        §2.2 (E7/E8) + §4.3 (A+ variant arm, P1/P2/P3) + §4.2-J-D.
//
// WHY THIS TB EXISTS (and what it is NOT):
//   §4.3's A+ arm is a BOARD arm (variant bitstream: DIV=65537 via the build
//   generic). This round is forbidden from opening Vivado, so the ARM IS MOVED
//   TO xsim: same two DUT configurations, same two questions, no bitstream.
//     * P1 equivalent -- `param_bad` (probe bit 20): 0 on the production config,
//       1 on the variant config. This is the cross-config contrast the design
//       asks for (a clamped/miswired bit cannot flip with the build).
//     * P2 equivalent -- the transaction duration: 128*DIV_SAFE clk cycles
//       (25 -> 3200 = 32 us; 65537 -> clamped 65536 -> 8388608 = 83.886 ms).
//       Measuring it also pins the CLAMP (a silent truncation would show as
//       128*1 cycles, the exact defect the DIV guard was added for).
//     * P3 equivalent -- `stat_start_lost` (probe bit 21): 0 without stimulus,
//       1 after a start pulse lands while busy (sticky), 0 again after the next
//       ACCEPTED start. The board cannot produce this stimulus by hand (busy
//       window 32 us << JTAG commit interval); in xsim the commit is just a
//       cycle-accurate write to the VIO output reg, so the arm is real here.
//
// TWO INSTANCES, ONE ELABORATION (same-session contrast):
//   u_prod -- mdio_vio_top with the E7 DEFAULT (no override). The design keeps
//             the default at 25 so production elaboration is unchanged; taking
//             the default here means that promise is exercised, not bypassed.
//   u_var  -- mdio_vio_top #(.DIV(65537)). Same file, same wiring, one parameter.
//   The only difference between the arms is that parameter, so the flip of bit
//   20 and the 2621x frame stretch are attributable to it alone.
//
// BOTH BITS ARE READ AT THEIR CABLE-END POSITION (u_*/u_vio/probe_in0[21:20]),
// i.e. through the real concat in mdio_vio_top.v -- this TB is the top-level
// wiring test that tb_mdio_master.v (module-level) structurally cannot be.
//
// What is NOT modelled (report "not observed"): the real vio_0 IP core, JTAG
// commit latency, a PHY (the MDIO line is held by a pullup; read data is
// therefore all-ones and is not judged), and the 330 ms phy_rstn counter (not
// waited on -- it does not gate mdio_master).
//
// Verdict contract (grepped by run_mdio_aplus_gate.bat):
//   "APL SUMMARY PROD ..." / "APL SUMMARY VAR ..." -- one line per arm, values
//      are the MEASURED ones (no literals), four bit fields per arm
//   "APL VERDICT PROD=PASS|FAIL" / "... VAR=..." / "APL VERDICT ALL=..."
//   "APL MISMATCH <check> exp=<b> got=<b>" -- one line per failed check
//=============================================================================

`timescale 1ns / 1ps

module tb_mdio_aplus;

    // ---- 100 MHz differential clock (Y1 on the board) ----
    reg  clk_p = 1'b0;
    wire clk_n = ~clk_p;
    always #5 clk_p = ~clk_p;

    // ---- DUT nets (one MDIO line per instance; pullup = the board's 10k) ----
    wire eth_mdc_p, eth_mdc_v;
    wire eth_rstn_p, eth_rstn_v;
    wire eth_mdio_p, eth_mdio_v;
    pullup pu_p (eth_mdio_p);
    pullup pu_v (eth_mdio_v);

    mdio_vio_top u_prod (
        .sys_clk_p (clk_p), .sys_clk_n (clk_n),
        .eth_mdc   (eth_mdc_p),
        .eth_mdio  (eth_mdio_p),
        .eth_rstn  (eth_rstn_p)
    );

    mdio_vio_top #(.DIV(65537)) u_var (
        .sys_clk_p (clk_p), .sys_clk_n (clk_n),
        .eth_mdc   (eth_mdc_v),
        .eth_mdio  (eth_mdio_v),
        .eth_rstn  (eth_rstn_v)
    );

    // ---- check bookkeeping (every field below is a MEASURED value) ----
    integer mism_p = 0;
    integer mism_v = 0;
    integer t_busy, t_mdc1, t_mdc2, t_fall;
    integer fcyc, m1cyc, m2cyc;

    reg r_p_pb0, r_p_s0, r_p_sm, r_p_sd, r_p_sc, r_p_se, r_p_scl;
    reg r_v_pb0, r_v_s0, r_v_sm, r_v_sd, r_v_sc, r_v_se, r_v_scl;

    `define APLCHK(cnt, tag, gotv, expv) \
        if ((gotv) !== (expv)) begin \
            cnt = cnt + 1; \
            $display("APL MISMATCH %s exp=%b got=%b", tag, expv, gotv); \
        end else begin \
            $display("APL OK %s = %b", tag, gotv); \
        end

    // ---- VIO output pokes = "host commit" (one clock of separation) ----
    task poke_prod; begin
        @(negedge u_prod.clk);
        u_prod.u_vio.probe_out0 = 1'b1;
    end endtask

    task poke_prod_lo; begin
        @(negedge u_prod.clk);
        u_prod.u_vio.probe_out0 = 1'b0;
    end endtask

    task poke_var; begin
        @(negedge u_var.clk);
        u_var.u_vio.probe_out0 = 1'b1;
    end endtask

    task poke_var_lo; begin
        @(negedge u_var.clk);
        u_var.u_vio.probe_out0 = 1'b0;
    end endtask

    initial begin
        //====================================================================
        // ARM PROD -- E7 default (DIV=25): param_bad must stay 0, and the
        // stat_start_lost sequence must be observable and clearable.
        //====================================================================
        wait (u_prod.por_n === 1'b1);
        repeat (10) @(posedge u_prod.clk);
        $display("APL ARM=PROD DIV=25 E7-default-no-override");

        u_prod.u_vio.probe_out2 = 5'd1;     // phyad = 1 (board strap)
        u_prod.u_vio.probe_out3 = 5'd4;     // regad = 4
        u_prod.u_vio.probe_out1 = 2'b00;    // force_rst=0, op=0 (read)

        // minimal witness, no stimulus at all:
        r_p_pb0 = u_prod.u_vio.probe_in0[20];   // param_bad
        r_p_s0  = u_prod.u_vio.probe_in0[21];   // stat_start_lost
        `APLCHK(mism_p, "PROD pbad_t0", r_p_pb0, 1'b0)
        `APLCHK(mism_p, "PROD ssl_t0",  r_p_s0,  1'b0)

        // first ACCEPTED start -> busy
        poke_prod;
        @(posedge u_prod.busy);
        t_busy = $time;
        repeat (3) @(posedge u_prod.clk);
        r_p_sm = u_prod.u_vio.probe_in0[21];
        `APLCHK(mism_p, "PROD ssl_mid", r_p_sm, 1'b0)  // negative control: nothing dropped yet

        // DROPPED start: probe_out0 1->0->1 while busy (P3 equivalent)
        poke_prod_lo;
        poke_prod;
        repeat (3) @(posedge u_prod.clk);
        r_p_sd = u_prod.u_vio.probe_in0[21];
        `APLCHK(mism_p, "PROD ssl_drop", r_p_sd, 1'b1) // minimal positive witness

        @(posedge u_prod.mdc); t_mdc1 = $time;
        @(posedge u_prod.mdc); t_mdc2 = $time;
        @(negedge u_prod.busy); t_fall = $time;
        r_p_se = u_prod.u_vio.probe_in0[16];    // done_sticky
        `APLCHK(mism_p, "PROD sticky_end", r_p_se, 1'b1)

        // CLEAN start (idle) must be accepted and clear both sticky flags
        poke_prod_lo;
        poke_prod;
        repeat (3) @(posedge u_prod.clk);
        r_p_sc  = u_prod.u_vio.probe_in0[21];
        r_p_scl = u_prod.u_vio.probe_in0[16];
        `APLCHK(mism_p, "PROD ssl_clean",  r_p_sc,  1'b0)
        `APLCHK(mism_p, "PROD sticky_clr", r_p_scl, 1'b0)

        fcyc  = (t_fall - t_busy) / 10;
        m1cyc = (t_mdc1 - t_busy) / 10;
        m2cyc = (t_mdc2 - t_mdc1) / 10;
        if (fcyc  !== 3200) begin mism_p = mism_p + 1; $display("APL MISMATCH PROD frame_cyc exp=3200 got=%0d", fcyc);  end
        if (m1cyc !== 25)   begin mism_p = mism_p + 1; $display("APL MISMATCH PROD mdc1_cyc exp=25 got=%0d", m1cyc);    end
        if (m2cyc !== 50)   begin mism_p = mism_p + 1; $display("APL MISMATCH PROD mdct_cyc exp=50 got=%0d", m2cyc);    end
        $display("APL SUMMARY PROD pbad_t0=%b ssl_t0=%b ssl_mid=%b ssl_drop=%b ssl_clean=%b sticky_end=%b sticky_clr=%b frame_cyc=%0d mdc1_cyc=%0d mdct_cyc=%0d",
                 r_p_pb0, r_p_s0, r_p_sm, r_p_sd, r_p_sc, r_p_se, r_p_scl, fcyc, m1cyc, m2cyc);
        if (mism_p == 0) $display("APL VERDICT PROD=PASS");
        else             $display("APL VERDICT PROD=FAIL mism=%0d", mism_p);

        //====================================================================
        // ARM VAR -- #(.DIV(65537)): param_bad must be 1 (P1 equivalent),
        // frame must stretch to 128*65536 cycles = 83.886 ms (P2 equivalent,
        // and proof the clamp went to the SLOW end, not to 1).
        //====================================================================
        wait (u_var.por_n === 1'b1);
        repeat (10) @(posedge u_var.clk);
        $display("APL ARM=VAR DIV=65537 clamped-65536");

        u_var.u_vio.probe_out2 = 5'd1;
        u_var.u_vio.probe_out3 = 5'd4;
        u_var.u_vio.probe_out1 = 2'b00;

        r_v_pb0 = u_var.u_vio.probe_in0[20];
        r_v_s0  = u_var.u_vio.probe_in0[21];
        `APLCHK(mism_v, "VAR pbad_t0", r_v_pb0, 1'b1)   // minimal positive witness for param_bad
        `APLCHK(mism_v, "VAR ssl_t0",  r_v_s0,  1'b0)

        poke_var;
        @(posedge u_var.busy);
        t_busy = $time;
        repeat (3) @(posedge u_var.clk);
        r_v_sm = u_var.u_vio.probe_in0[21];
        `APLCHK(mism_v, "VAR ssl_mid", r_v_sm, 1'b0)

        poke_var_lo;
        poke_var;
        repeat (3) @(posedge u_var.clk);
        r_v_sd = u_var.u_vio.probe_in0[21];
        `APLCHK(mism_v, "VAR ssl_drop", r_v_sd, 1'b1)   // minimal positive witness for stat_start_lost

        @(posedge u_var.mdc); t_mdc1 = $time;
        @(posedge u_var.mdc); t_mdc2 = $time;
        @(negedge u_var.busy); t_fall = $time;
        r_v_se = u_var.u_vio.probe_in0[16];
        `APLCHK(mism_v, "VAR sticky_end", r_v_se, 1'b1)

        poke_var_lo;
        poke_var;
        repeat (3) @(posedge u_var.clk);
        r_v_sc  = u_var.u_vio.probe_in0[21];
        r_v_scl = u_var.u_vio.probe_in0[16];
        `APLCHK(mism_v, "VAR ssl_clean",  r_v_sc,  1'b0)
        `APLCHK(mism_v, "VAR sticky_clr", r_v_scl, 1'b0)

        fcyc  = (t_fall - t_busy) / 10;
        m1cyc = (t_mdc1 - t_busy) / 10;
        m2cyc = (t_mdc2 - t_mdc1) / 10;
        if (fcyc  !== 8388608) begin mism_v = mism_v + 1; $display("APL MISMATCH VAR frame_cyc exp=8388608 got=%0d", fcyc); end
        if (m1cyc !== 65536)   begin mism_v = mism_v + 1; $display("APL MISMATCH VAR mdc1_cyc exp=65536 got=%0d", m1cyc);    end
        if (m2cyc !== 131072)  begin mism_v = mism_v + 1; $display("APL MISMATCH VAR mdct_cyc exp=131072 got=%0d", m2cyc);   end
        $display("APL SUMMARY VAR pbad_t0=%b ssl_t0=%b ssl_mid=%b ssl_drop=%b ssl_clean=%b sticky_end=%b sticky_clr=%b frame_cyc=%0d mdc1_cyc=%0d mdct_cyc=%0d",
                 r_v_pb0, r_v_s0, r_v_sm, r_v_sd, r_v_sc, r_v_se, r_v_scl, fcyc, m1cyc, m2cyc);
        if (mism_v == 0) $display("APL VERDICT VAR=PASS");
        else             $display("APL VERDICT VAR=FAIL mism=%0d", mism_v);

        if (mism_p == 0 && mism_v == 0) $display("APL VERDICT ALL=PASS");
        else                            $display("APL VERDICT ALL=FAIL");

        $display("=== done ===");
        $finish;
    end

    // timeout guard (expected total sim time ~85 ms incl. the 84 ms variant frame)
    initial begin
        #300000000;
        $display("TIMEOUT-APL");
        $finish;
    end

endmodule
