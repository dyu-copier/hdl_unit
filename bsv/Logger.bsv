// Logger.bsv - no-op override so BSC 2026.01 can compile axi4_types.bsv.
// The bsv_axi library version uses `$display fmt` (Verilog style, no parens)
// and references cfg_verbosity which is not declared in all modules that use
// the macro. This file shadows the library copy via the leading '.' in BSC_PATH.
`ifndef LOGGER_BSV
`define LOGGER_BSV
`define logLevel(mod, lvl, fmt) begin end
`define logTimeLevel(mod, lvl, fmt) begin end
`endif
