// ============================================================================
// axi4_master_checker — formal protocol checker for an AXI4 master
//
// Mirror image of axi4_slave_checker.v (see that file for the slave-side
// rationale/history). Binds to the slave-facing side of an AXI4 master DUT:
//   assert()  — checks the DUT's master-driven outputs (awvalid/awid/
//               awaddr/awlen, wvalid/wlast, arvalid/arid/araddr/arlen,
//               bready, rready) are protocol-compliant.
//   assume()  — constrains the free-variable slave stimulus (awready,
//               wready, bvalid/bid/bresp, arready, rvalid/rid/rlast/rresp)
//               to obey AXI4 protocol rules, so the solver only explores
//               legal slave behavior.
//
// Scope (intentionally moderate, not full AMBA AXI4 compliance) — same as
// axi4_slave_checker.v:
//   - VALID/payload stability while stalled, on all five channels.
//   - No response (B or R) assumed without a matching accepted request
//     outstanding (constrains the environment; this DUT is a master and
//     doesn't originate responses).
//   - VALID held low during reset, on both the master and slave sides.
// NOT covered: burst length vs. RLAST timing, WSTRB/AWSIZE/AWBURST
// legality, exclusive access, out-of-order ID response matching, QoS/
// region/cache/prot field checks.
//
// Author: project-wide shared checker (not IP-specific; not a copier
// template — plain Verilog, parameterized by ID/address/data width).
// ============================================================================
`default_nettype none

module axi4_master_checker #(
    parameter C_AXI_ID_WIDTH   = 4,
    parameter C_AXI_ADDR_WIDTH = 32,
    parameter C_AXI_DATA_WIDTH = 32
) (
    input wire i_clk,
    input wire i_axi_reset_n,

    // Write address channel
    input wire                        i_axi_awvalid,
    input wire                        i_axi_awready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_awid,
    input wire [C_AXI_ADDR_WIDTH-1:0] i_axi_awaddr,
    input wire [7:0]                  i_axi_awlen,

    // Write data channel
    input wire                        i_axi_wvalid,
    input wire                        i_axi_wready,
    input wire                        i_axi_wlast,

    // Write response channel
    input wire                        i_axi_bvalid,
    input wire                        i_axi_bready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_bid,
    input wire [1:0]                  i_axi_bresp,

    // Read address channel
    input wire                        i_axi_arvalid,
    input wire                        i_axi_arready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_arid,
    input wire [C_AXI_ADDR_WIDTH-1:0] i_axi_araddr,
    input wire [7:0]                  i_axi_arlen,

    // Read data channel
    input wire                        i_axi_rvalid,
    input wire                        i_axi_rready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_rid,
    input wire                        i_axi_rlast,
    input wire [1:0]                  i_axi_rresp
);

    reg f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge i_clk)
        f_past_valid <= 1'b1;

    // ------------------------------------------------------------------
    // Reset: no request or response may be in flight while in reset.
    // ------------------------------------------------------------------
    always @(*) if (!i_axi_reset_n) begin
        assert (!i_axi_awvalid);
        assert (!i_axi_wvalid);
        assert (!i_axi_arvalid);
        assume (!i_axi_bvalid);
        assume (!i_axi_rvalid);
    end

    // ------------------------------------------------------------------
    // VALID/payload stability while stalled — AXI4 spec: once VALID is
    // asserted, it (and the associated payload) must not change until the
    // corresponding READY is seen. Master-driven channels are checked with
    // assert; slave-driven response channels are constrained with assume.
    // ------------------------------------------------------------------

    // AW channel (assert: DUT stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_awvalid) && !$past(i_axi_awready)) begin
            assert (i_axi_awvalid);
            assert ($stable(i_axi_awid));
            assert ($stable(i_axi_awaddr));
            assert ($stable(i_axi_awlen));
        end
    end

    // W channel (assert: DUT stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_wvalid) && !$past(i_axi_wready)) begin
            assert (i_axi_wvalid);
            assert ($stable(i_axi_wlast));
        end
    end

    // AR channel (assert: DUT stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_arvalid) && !$past(i_axi_arready)) begin
            assert (i_axi_arvalid);
            assert ($stable(i_axi_arid));
            assert ($stable(i_axi_araddr));
            assert ($stable(i_axi_arlen));
        end
    end

    // B channel (assume: slave stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_bvalid) && !$past(i_axi_bready)) begin
            assume (i_axi_bvalid);
            assume ($stable(i_axi_bid));
            assume ($stable(i_axi_bresp));
        end
    end

    // R channel (assume: slave stimulus)
    always @(posedge i_clk) if (f_past_valid && $past(i_axi_reset_n)) begin
        if ($past(i_axi_rvalid) && !$past(i_axi_rready)) begin
            assume (i_axi_rvalid);
            assume ($stable(i_axi_rid));
            assume ($stable(i_axi_rlast));
            assume ($stable(i_axi_rresp));
        end
    end

    // ------------------------------------------------------------------
    // No spurious response: BVALID/RVALID assumed not to fire without a
    // matching accepted request outstanding (constrains the environment —
    // this DUT is a master and doesn't originate responses). Does not
    // verify ID matching or response ordering (see NOT covered, above).
    // ------------------------------------------------------------------
    localparam F_CNT_WIDTH = 8;

    reg [F_CNT_WIDTH-1:0] f_outstanding_wr;
    reg [F_CNT_WIDTH-1:0] f_outstanding_rd;

    wire aw_accepted = i_axi_awvalid && i_axi_awready;
    wire b_accepted  = i_axi_bvalid  && i_axi_bready;
    wire ar_accepted = i_axi_arvalid && i_axi_arready;
    wire r_accepted  = i_axi_rvalid  && i_axi_rready && i_axi_rlast;

    always @(posedge i_clk) begin
        if (!i_axi_reset_n) begin
            f_outstanding_wr <= {F_CNT_WIDTH{1'b0}};
            f_outstanding_rd <= {F_CNT_WIDTH{1'b0}};
        end else begin
            f_outstanding_wr <= f_outstanding_wr + aw_accepted - b_accepted;
            f_outstanding_rd <= f_outstanding_rd + ar_accepted - r_accepted;
        end
    end

    always @(posedge i_clk) if (f_past_valid && i_axi_reset_n) begin
        assume (f_outstanding_wr != {F_CNT_WIDTH{1'b1}}); // no underflow
        assume (f_outstanding_rd != {F_CNT_WIDTH{1'b1}}); // no underflow
        // A response this cycle needs either a request already outstanding
        // before this cycle, or one being accepted this same cycle.
        if (i_axi_bvalid) assume (f_outstanding_wr != 0 || aw_accepted);
        if (i_axi_rvalid) assume (f_outstanding_rd != 0 || ar_accepted);
    end

endmodule
`default_nettype wire
