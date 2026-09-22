// ======================================================================
// wb_dma_env_pkg -- the UVM environment for the OpenCores wb_dma RTL.
//
// A plain signal-level bench: one DUT view (the RTL), a UVM RAL generated from
// src/rdl as the register front door, the fwvip-wb initiator agent as the bus
// engine underneath it, and backdoor access to the two SV RAMs that back the
// DUT's master ports.
//
// The contents form a single linear dependency chain; the includes below are in
// that topological order:
//
//   ral_cfg    -- builds + locks the generated register block, creates the
//                 fwvip-wb reg adapter, points default_map at the initiator's
//                 sequencer. Also the home of the field-extraction helper every
//                 status decode goes through.
//   mem_agent  -- backdoor over the two wb_ram_slv virtual interfaces.
//   scoreboard -- memory-vs-memory copy check + completion accounting.
//   env        -- assembles the above with the initiator agent.
//
// One class per .svh, no `ifndef guards (the project convention); the package is
// compiled once into the shared env SimLib. Scenario sequences and tests live in
// wb_dma_tests_pkg.
// ======================================================================
`include "uvm_macros.svh"

package wb_dma_env_pkg;
    import uvm_pkg::*;
    import fwvip_wb_xtor_pkg::*;   // ADDR_WIDTH_MAX / DATA_WIDTH_MAX
    import fwvip_wb_pkg::*;        // initiator agent, transaction, reg adapter
    // The UVM RAL generated from src/rdl by the `ral` export: wb_dma_regs (with
    // wb_dma_ch_regs bank[4]) and one uvm_reg class per register type. This is
    // the WHOLE register map -- no offset, width or bit position is restated
    // anywhere in this bench.
    import wb_dma_ral_pkg::*;
    export wb_dma_ral_pkg::*;      // scenarios name wb_dma_regs / wb_dma_csr

    // Where the scenarios put their source and destination buffers. Both RAMs
    // are 8192 words (32 KiB), so these are comfortably inside either.
    localparam logic [31:0] SRC_BASE = 32'h0000_0000;
    localparam logic [31:0] DST_BASE = 32'h0000_4000;

    // How a channel ended. Distinguishing DONE from ERR is the reason completion
    // is decoded from CHn_CSR rather than from INT_SRC: the interrupt-source bit
    // is cause-BLIND -- a completion and an abort set the same bit -- so a test
    // that only asked "did it interrupt?" would pass on an errored channel.
    typedef enum {
        WB_DMA_DONE,        // transfer completed normally
        WB_DMA_ERR,         // channel stopped on an error
        WB_DMA_TIMEOUT      // no interrupt within the poll budget
    } wb_dma_status_e;

    `include "wb_dma_ral_cfg.svh"
    `include "wb_dma_mem_agent.svh"
    `include "wb_dma_scoreboard.svh"
    `include "wb_dma_env.svh"
endpackage
