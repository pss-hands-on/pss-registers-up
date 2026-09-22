// ---- env -----------------------------------------------------------------
//
// Four pieces, assembled here:
//
//   m_init  -- the fwvip-wb initiator agent. Its config is set by hvl_top over
//              the host transactor's interface, so every access it drives is a
//              real Wishbone cycle into the DUT's WB0 slave port.
//   ral     -- the generated register model, with the VIP's uvm_reg_adapter
//              between it and m_init's sequencer.
//   mem     -- backdoor access to the two RAMs backing the DUT's master ports.
//   sb      -- the scoreboard.
//
// The RAL sequencer binding happens in connect_phase because the agent (and so
// its sequencer) does not exist until build_phase has run.
class wb_dma_env extends uvm_env;
    `uvm_component_utils(wb_dma_env)

    fwvip_wb_initiator  m_init;
    wb_dma_ral_cfg      ral;
    wb_dma_mem_agent    mem;
    wb_dma_scoreboard   sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_init = fwvip_wb_initiator::type_id::create("m_init", this);
        sb     = wb_dma_scoreboard::type_id::create("sb", this);

        ral = wb_dma_ral_cfg::type_id::create("ral");
        ral.build_model();

        mem = wb_dma_mem_agent::type_id::create("mem");
        mem.connect_vifs(this);
        sb.mem = mem;
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        ral.set_sequencer(m_init.m_seqr);
    endfunction
endclass
