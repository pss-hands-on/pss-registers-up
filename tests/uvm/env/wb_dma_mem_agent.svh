// ---- data-memory backdoor -------------------------------------------------
//
// The DUT masters into two combinational 0-wait-state SV RAMs (wb_ram_slv, in
// tb/). Those RAMs already expose poke/peek/inject_err as interface functions,
// so this class is just the indirection that lets a sequence or the scoreboard
// say "interface 0" or "interface 1" instead of holding two vifs.
//
// `if_sel` matches the device's own numbering: CHn_CSR.SRC_SEL / DST_SEL select
// interface 0 or 1, and those are exactly WB0 (u_ram0) and WB1 (u_ram1).
//
// Addresses are BYTE addresses throughout, matching the register model and the
// RAM's own word-aligned indexing.
class wb_dma_mem_agent extends uvm_object;
    `uvm_object_utils(wb_dma_mem_agent)

    virtual wb_ram_slv #(32, 32) ram[2];

    function new(string name = "wb_dma_mem_agent");
        super.new(name);
    endfunction

    // Seat the two RAM interfaces published by hvl_top.
    function void connect_vifs(uvm_component ctxt);
        if (!uvm_config_db #(virtual wb_ram_slv #(32, 32))::get(ctxt, "", "ram0", ram[0]))
            `uvm_fatal("MEM", "no ram0 vif in config_db")
        if (!uvm_config_db #(virtual wb_ram_slv #(32, 32))::get(ctxt, "", "ram1", ram[1]))
            `uvm_fatal("MEM", "no ram1 vif in config_db")
    endfunction

    function void poke(bit if_sel, logic [31:0] adr, logic [31:0] dat);
        ram[if_sel].poke(adr, dat);
    endfunction

    function logic [31:0] peek(bit if_sel, logic [31:0] adr);
        return ram[if_sel].peek(adr);
    endfunction

    // Fill n words from `base` with a reproducible pattern. The seed is mixed
    // with the word index so a scoreboard can recompute the expected value
    // without holding a copy.
    function void fill(bit if_sel, logic [31:0] base, int n, logic [31:0] seed);
        for (int i = 0; i < n; i++)
            poke(if_sel, base + (i * 4), pattern(seed, i));
    endfunction

    // Clear n words from `base` -- so a stale result from a previous iteration
    // cannot be mistaken for a correct copy.
    function void clear(bit if_sel, logic [31:0] base, int n);
        for (int i = 0; i < n; i++)
            poke(if_sel, base + (i * 4), 32'h0);
    endfunction

    static function logic [31:0] pattern(logic [31:0] seed, int i);
        return {seed[15:0], 16'(i)};
    endfunction

    // Arm the RAM's injected-error address (byte address). The RAM asserts ERR
    // instead of ACK on a hit, and its err output is wired to the DUT's
    // wb*_err_i, so the engine aborts the transfer.
    function void inject_err(bit if_sel, logic [31:0] adr);
        ram[if_sel].inject_err(adr);
    endfunction
endclass
