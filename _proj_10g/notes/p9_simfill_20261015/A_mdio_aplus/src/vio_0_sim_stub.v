// vio_0_sim_stub.v -- behavioral xsim stand-in for the vio_0 IP core.
//
// Round: _proj_10g/notes/p9_simfill_20261015 (mdio A+ variant arm, sim level).
//
// Port list / widths / directions are copied from the REAL (22-bit patched) stub
// notes/p9_fix_mdio_impl_20261015/gate_elab_22/vio_0.v so the TB can elaborate
// mdio_vio_top unmodified. Differences vs that stub, on purpose:
//   * probe_out* are plain regs with NO driver after their initial value, so the
//     TB may poke them through hierarchical assignment -- this models the host
//     writing a VIO output over JTAG (a VIO output holds its value until the
//     next commit; there is no "return to zero").
//   * one [21:20] convenience view is NOT added: the TB reads probe_in0[21:20]
//     straight off the port, because that is where the bit-position claim lives.
//
// NOT modelled (registered as "not observed" in the round report): the real VIO
// core, BSCAN/JTAG commit latency, and the .ltx probe metadata.

`timescale 1ns / 1ps

module vio_0 (
    input  wire        clk,
    input  wire [21:0] probe_in0,

    output reg  [0:0]  probe_out0,
    output reg  [1:0]  probe_out1,
    output reg  [4:0]  probe_out2,
    output reg  [4:0]  probe_out3,
    output reg  [15:0] probe_out4
);

    initial begin
        probe_out0 = 1'b0;
        probe_out1 = 2'b00;
        probe_out2 = 5'd0;
        probe_out3 = 5'd0;
        probe_out4 = 16'd0;
    end

endmodule
