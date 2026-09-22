// ---- scoreboard -----------------------------------------------------------
//
// Two checks, both end-of-transfer:
//
//   check_copy()       -- the destination region holds what the source region
//                         held, word for word, read back through the memory
//                         backdoor.
//   check_done_count() -- the expected number of channels reported completion.
//
// WHAT THIS DOES NOT CHECK. There is no reference model and no bus monitor
// here, so nothing asserts the ORDER in which the engine moved the data, nor
// that arbitration honoured strict priority. The reference project gets those
// from an always-on passive SPL model compared transaction-by-transaction
// against the RTL on the master buses; that machinery is inseparable from the
// SPL class model, which this bench deliberately does not carry. Recorded in
// docs/rtl-uvm-tb-design.md §9 D3 and §10 so it stays a known gap rather than
// an assumed capability.
class wb_dma_scoreboard extends uvm_component;
    `uvm_component_utils(wb_dma_scoreboard)

    wb_dma_mem_agent mem;
    int unsigned     errors;
    int unsigned     done_count;   // completions reported since the last reset

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Called by a sequence each time a channel reports completion.
    function void note_done();
        done_count++;
    endfunction

    function void reset_counts();
        done_count = 0;
    endfunction

    // Compare n words at dst against n words at src, through the backdoor.
    // Reports at most 8 mismatches per call -- a wrong base address would
    // otherwise produce one message per word.
    function void check_copy(bit src_if, logic [31:0] src,
                             bit dst_if, logic [31:0] dst, int n);
        int shown = 0;
        for (int i = 0; i < n; i++) begin
            logic [31:0] exp = mem.peek(src_if, src + (i * 4));
            logic [31:0] act = mem.peek(dst_if, dst + (i * 4));
            if (exp !== act) begin
                errors++;
                if (shown < 8) begin
                    shown++;
                    `uvm_error("SB", $sformatf(
                        "copy mismatch if%0d:0x%08h -> if%0d:0x%08h word %0d: exp 0x%08h act 0x%08h",
                        src_if, src, dst_if, dst, i, exp, act))
                end
            end
        end
    endfunction

    function void check_done_count(int unsigned expected);
        if (done_count != expected) begin
            errors++;
            `uvm_error("SB", $sformatf("done count %0d, expected %0d", done_count, expected))
        end
    endfunction
endclass
