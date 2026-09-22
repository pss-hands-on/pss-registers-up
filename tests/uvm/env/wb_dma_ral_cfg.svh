// ---- register model bring-up ---------------------------------------------
//
// Builds the generated wb_dma_regs block, wires it to the fwvip-wb initiator
// through the VIP's uvm_reg_adapter, and hands the result to the env.
//
// BASE ADDRESS 0. The initiator transactor is bound directly at the DUT's WB0
// slave (register) port, so accesses carry raw device offsets; there is no
// interconnect in front of the device to offset them.
//
// AUTO-PREDICT IS OFF, deliberately, and every status decode in this bench goes
// through get_field() below rather than through the mirror. Three properties of
// this device make the mirror untrustworthy for anything hardware writes:
//
//   * CHn_CSR.INT_{ERR,DONE,CHK_DONE} are `rclr` (generated as "RC"): reading
//     the register CONSUMES the event. A completion check must therefore read
//     CHn_CSR exactly ONCE and work entirely off that one returned value --
//     a second read to "confirm" would come back clear.
//   * CH_EN and STOP are `hwclr`: hardware clears them on done/err/abort, so
//     the mirror still says 1 long after the bit is 0. This is why arming is a
//     plain write() of a composed value and never update(): update() compares
//     desired against a mirror the hardware has already invalidated, decides
//     nothing needs writing, and silently issues no bus cycle.
//   * BUSY/DONE/ERR are hardware-written status with no software write path.
//
// Configuration registers (SZ, ADR0, AM0, ...) have none of these problems;
// their mirror is fine, and write() keeps it current.
class wb_dma_ral_cfg extends uvm_object;
    `uvm_object_utils(wb_dma_ral_cfg)

    wb_dma_regs             regs;
    fwvip_wb_reg_adapter    adapter;

    function new(string name = "wb_dma_ral_cfg");
        super.new(name);
    endfunction

    // Build + lock the model. Called from the env's build_phase; the sequencer
    // is attached later (connect_phase), once the agent exists.
    function void build_model();
        regs = new("regs");
        regs.build();
        regs.lock_model();
        regs.default_map.set_base_addr(0);
        regs.default_map.set_auto_predict(0);
        adapter = fwvip_wb_reg_adapter::type_id::create("adapter");
    endfunction

    // Point the map at the initiator agent's sequencer. Every front-door access
    // from here on is a real Wishbone cycle into the DUT's WB0 slave port.
    function void set_sequencer(uvm_sequencer_base seqr);
        regs.default_map.set_sequencer(seqr, adapter);
    endfunction

    // Extract one field from a value just read off the bus.
    //
    // The position and width come from the generated model, so this restates
    // nothing: move a field in the RDL and this follows. It reads the RETURNED
    // value rather than the mirror, which is what makes it safe for the RC and
    // hwclr fields described above.
    static function uvm_reg_data_t get_field(uvm_reg_field f, uvm_reg_data_t v);
        return (v >> f.get_lsb_pos()) & ((1 << f.get_n_bits()) - 1);
    endfunction
endclass
