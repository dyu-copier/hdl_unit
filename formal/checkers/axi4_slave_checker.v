// ============================================================================
// axi4_slave_checker — formal protocol checker for an AXI4 **slave** DUT
//
// Binds to the master-facing side of an AXI4 slave:
//   assume()  — constrains the free-variable master stimulus to obey AXI4
//               (`AXI4_MASTER_RULE`), so the solver explores only legal
//               master behavior.
//   assert()  — checks the DUT's slave-driven outputs are protocol
//               compliant (`AXI4_SLAVE_RULE`).
//
// The rule set itself lives in axi4_checker_rules.vh, shared verbatim with
// axi4_master_checker.v (same rules, assert/assume swapped). Rule IDs and
// the deliberate simplifications (synchronous-reset R3/R4 treatment,
// bounded tracking capacity, exclusive access off by default, optional
// bounded liveness) are documented in AXI4_rules.md at the repo root and
// in the .vh header.
//
// Verified for the template's 32-bit address / 32-bit data configuration;
// re-check the literal widths in the shared body before using other sizes.
//
// Author: project-wide shared checker (not IP-specific; not a copier
// template — plain Verilog, parameterized by ID/address/data width).
// ============================================================================
`default_nettype none

module axi4_slave_checker #(
    parameter C_AXI_ID_WIDTH    = 4,
    parameter C_AXI_ADDR_WIDTH  = 32,
    parameter C_AXI_DATA_WIDTH  = 32,
    parameter F_MAX_OUTSTANDING = 4,  // max in-flight write bursts tracked
    parameter F_MAX_PER_ID      = 2,  // max in-flight read bursts per ID
    parameter F_OPT_EXCLUSIVE   = 0,  // 1: enable X1-X3; 0: forbid AxLOCK/EXOKAY
    parameter F_OPT_MAX_STALL   = 0   // >0: bounded-liveness stall limit
) (
    input wire i_clk,
    input wire i_axi_reset_n,

    // Write address channel
    input wire                        i_axi_awvalid,
    input wire                        i_axi_awready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_awid,
    input wire [C_AXI_ADDR_WIDTH-1:0] i_axi_awaddr,
    input wire [7:0]                  i_axi_awlen,
    input wire [2:0]                  i_axi_awsize,
    input wire [1:0]                  i_axi_awburst,
    input wire                        i_axi_awlock,
    input wire [3:0]                  i_axi_awcache,
    input wire [2:0]                  i_axi_awprot,
    input wire [3:0]                  i_axi_awqos,
    input wire [3:0]                  i_axi_awregion,

    // Write data channel
    input wire                          i_axi_wvalid,
    input wire                          i_axi_wready,
    input wire [C_AXI_DATA_WIDTH-1:0]   i_axi_wdata,
    input wire [C_AXI_DATA_WIDTH/8-1:0] i_axi_wstrb,
    input wire                          i_axi_wlast,

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
    input wire [2:0]                  i_axi_arsize,
    input wire [1:0]                  i_axi_arburst,
    input wire                        i_axi_arlock,
    input wire [3:0]                  i_axi_arcache,
    input wire [2:0]                  i_axi_arprot,
    input wire [3:0]                  i_axi_arqos,
    input wire [3:0]                  i_axi_arregion,

    // Read data channel
    input wire                        i_axi_rvalid,
    input wire                        i_axi_rready,
    input wire [C_AXI_ID_WIDTH-1:0]   i_axi_rid,
    input wire [C_AXI_DATA_WIDTH-1:0] i_axi_rdata,
    input wire [1:0]                  i_axi_rresp,
    input wire                        i_axi_rlast
);

// DUT is the slave: master obligations constrain the environment (assume),
// slave obligations are checked against the DUT (assert).
`define AXI4_MASTER_RULE(x) assume(x)
`define AXI4_SLAVE_RULE(x)  assert(x)
`define AXI4_CHK_DUT_IS_SLAVE

`include "axi4_checker_rules.vh"

`undef AXI4_MASTER_RULE
`undef AXI4_SLAVE_RULE
`undef AXI4_CHK_DUT_IS_SLAVE

endmodule
`default_nettype wire
