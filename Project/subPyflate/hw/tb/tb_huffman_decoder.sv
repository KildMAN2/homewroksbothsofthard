// -----------------------------------------------------------------------------
// tb_huffman_decoder.sv
// Self-checking end-to-end testbench for the canonical Huffman decoder.
//
// Builds a small canonical Huffman table (5 symbols, max_bits = 3), loads it
// into the LUT, streams a hand-computed input byte stream, and checks that
// the decoded symbol sequence matches the reference exactly.
//
// Canonical codes (MSB-first, matching bzip2 / `reversed=False`):
//   symbol 0 -> "00"   (2 bits)
//   symbol 1 -> "01"   (2 bits)
//   symbol 2 -> "10"   (2 bits)
//   symbol 3 -> "110"  (3 bits)
//   symbol 4 -> "111"  (3 bits)
//
// Reference message: [0, 1, 2, 3, 4, 0, 4, 1]
//   Concatenated bits: 00 01 10 110 111 00 111 01  (19 bits)
//   Padded to 3 bytes (LSB-side zero pad): 0001 1011 0111 0011 1010 0000
//                                        = 0x1B 0x73 0xA0
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_huffman_decoder;

    localparam int MAX_BITS     = 3;
    localparam int SYMBOL_WIDTH = 16;
    localparam int CODE_BITS_W  = 5;
    localparam int BUF_W        = 32;
    localparam int COUNTER_W    = 32;

    logic                        clk = 0;
    logic                        rst_n = 0;

    logic                        table_wr_en = 0;
    logic [MAX_BITS-1:0]         table_wr_addr = '0;
    logic [SYMBOL_WIDTH-1:0]     table_wr_symbol = '0;
    logic [CODE_BITS_W-1:0]      table_wr_bits = '0;

    logic                        start = 0;
    logic [COUNTER_W-1:0]        max_symbols = 0;

    logic                        byte_valid = 0;
    logic [7:0]                  byte_data = '0;
    logic                        byte_ready;

    logic                        symbol_valid;
    logic [SYMBOL_WIDTH-1:0]     symbol_out;
    logic [CODE_BITS_W-1:0]      symbol_bits;
    logic                        busy, done, error;

    integer errors = 0, checks = 0;

    // Reference sequence and byte stream.
    // (Element-by-element initialization for tool portability.)
    localparam int NSYM  = 8;
    localparam int NBYTES = 3;
    logic [SYMBOL_WIDTH-1:0] ref_seq [NSYM];
    logic [7:0]              byte_stream [NBYTES];
    logic [SYMBOL_WIDTH-1:0] got_seq [NSYM];
    int                      got_idx;

    initial begin
        ref_seq[0] = 16'd0;
        ref_seq[1] = 16'd1;
        ref_seq[2] = 16'd2;
        ref_seq[3] = 16'd3;
        ref_seq[4] = 16'd4;
        ref_seq[5] = 16'd0;
        ref_seq[6] = 16'd4;
        ref_seq[7] = 16'd1;
        byte_stream[0] = 8'h1B;
        byte_stream[1] = 8'h73;
        byte_stream[2] = 8'hA0;
    end

    // Collector: on every posedge, if the DUT asserted symbol_valid last
    // cycle, capture symbol_out. This uses the standard nonblocking-sample
    // semantics so we see the value that was driven during the S_CONSUME
    // cycle, not after the state transitions out.
    always @(posedge clk) begin
        if (rst_n && symbol_valid && got_idx < NSYM) begin
            got_seq[got_idx] <= symbol_out;
            got_idx          <= got_idx + 1;
        end
    end

    huffman_decoder #(
        .MAX_BITS    (MAX_BITS),
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .CODE_BITS_W (CODE_BITS_W),
        .BUF_W       (BUF_W),
        .COUNTER_W   (COUNTER_W)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .table_wr_en     (table_wr_en),
        .table_wr_addr   (table_wr_addr),
        .table_wr_symbol (table_wr_symbol),
        .table_wr_bits   (table_wr_bits),
        .start           (start),
        .max_symbols     (max_symbols),
        .byte_valid      (byte_valid),
        .byte_data       (byte_data),
        .byte_ready      (byte_ready),
        .symbol_valid    (symbol_valid),
        .symbol_out      (symbol_out),
        .symbol_bits     (symbol_bits),
        .busy            (busy),
        .done            (done),
        .error           (error)
    );

    always #5 clk = ~clk;

    task automatic load_entry(input [MAX_BITS-1:0] addr,
                              input [SYMBOL_WIDTH-1:0] sym,
                              input [CODE_BITS_W-1:0] bits);
        begin
            @(negedge clk);
            table_wr_en     = 1'b1;
            table_wr_addr   = addr;
            table_wr_symbol = sym;
            table_wr_bits   = bits;
            @(negedge clk);
            table_wr_en     = 1'b0;
        end
    endtask

    initial begin
        int    byte_idx;
        int    bytes_sent;
        int    guard;

        got_idx = 0;
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // Load the LUT (canonical Huffman, MAX_BITS=3):
        // symbol 0 (bits=2, code=00) -> indices 000, 001
        // symbol 1 (bits=2, code=01) -> indices 010, 011
        // symbol 2 (bits=2, code=10) -> indices 100, 101
        // symbol 3 (bits=3, code=110) -> index 110
        // symbol 4 (bits=3, code=111) -> index 111
        load_entry(3'b000, 16'd0, 5'd2);
        load_entry(3'b001, 16'd0, 5'd2);
        load_entry(3'b010, 16'd1, 5'd2);
        load_entry(3'b011, 16'd1, 5'd2);
        load_entry(3'b100, 16'd2, 5'd2);
        load_entry(3'b101, 16'd2, 5'd2);
        load_entry(3'b110, 16'd3, 5'd3);
        load_entry(3'b111, 16'd4, 5'd3);

        // Kick off decode.
        @(negedge clk);
        start       = 1'b1;
        max_symbols = NSYM;
        @(negedge clk);
        start       = 1'b0;

        // Byte-streaming loop: refill whenever the shifter can accept a
        // byte. The collector process above records symbols independently.
        byte_idx   = 0;
        bytes_sent = 0;
        guard      = 0;
        while (got_idx < NSYM && guard < 1000) begin
            @(negedge clk);
            if (byte_ready && byte_idx < NBYTES) begin
                byte_valid = 1'b1;
                byte_data  = byte_stream[byte_idx];
                byte_idx   = byte_idx + 1;
                bytes_sent = bytes_sent + 1;
            end else begin
                byte_valid = 1'b0;
            end
            guard = guard + 1;
        end
        @(negedge clk);
        byte_valid = 1'b0;

        // Give the FSM a couple of extra cycles to raise `done`.
        repeat (4) @(negedge clk);

        // Score results.
        for (int i = 0; i < NSYM; i++) begin
            checks = checks + 1;
            if (got_seq[i] !== ref_seq[i]) begin
                errors = errors + 1;
                $display("FAIL [%0d] got=%0d exp=%0d", i, got_seq[i], ref_seq[i]);
            end else begin
                $display("PASS [%0d] symbol=%0d", i, got_seq[i]);
            end
        end
        checks = checks + 1;
        if (error) begin
            errors = errors + 1;
            $display("FAIL error asserted at end of session");
        end else begin
            $display("PASS error clear at end of session");
        end

        $display("--------------------------------------------------");
        $display("DECODER TESTS: checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("DECODER RESULT: ALL PASS");
        else             $display("DECODER RESULT: FAILURES=%0d", errors);
        $finish;
    end

endmodule
