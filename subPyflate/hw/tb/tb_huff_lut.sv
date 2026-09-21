// -----------------------------------------------------------------------------
// tb_huff_lut.sv
// Self-checking testbench for the Huffman LUT storage module.
// Writes a handful of entries, reads each one back on the following cycle,
// and checks the returned (symbol, bits) matches the write data exactly.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_huff_lut;

    localparam int MAX_BITS     = 5;   // small depth for quick simulation
    localparam int SYMBOL_WIDTH = 16;
    localparam int CODE_BITS_W  = 5;
    localparam int DEPTH        = 1 << MAX_BITS;

    logic                          clk = 0;
    logic                          rst_n = 0;

    logic                          wr_en = 0;
    logic [MAX_BITS-1:0]           wr_addr;
    logic [SYMBOL_WIDTH-1:0]       wr_symbol;
    logic [CODE_BITS_W-1:0]        wr_bits;

    logic                          rd_en = 0;
    logic [MAX_BITS-1:0]           rd_addr;
    logic [SYMBOL_WIDTH-1:0]       rd_symbol;
    logic [CODE_BITS_W-1:0]        rd_bits;
    logic                          rd_valid;

    integer errors = 0, checks = 0;

    huff_lut #(
        .MAX_BITS    (MAX_BITS),
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .CODE_BITS_W (CODE_BITS_W)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (wr_en),
        .wr_addr   (wr_addr),
        .wr_symbol (wr_symbol),
        .wr_bits   (wr_bits),
        .rd_en     (rd_en),
        .rd_addr   (rd_addr),
        .rd_symbol (rd_symbol),
        .rd_bits   (rd_bits),
        .rd_valid  (rd_valid)
    );

    always #5 clk = ~clk;

    task automatic do_write(input [MAX_BITS-1:0] addr,
                            input [SYMBOL_WIDTH-1:0] sym,
                            input [CODE_BITS_W-1:0] bits);
        begin
            @(negedge clk);
            wr_en     = 1'b1;
            wr_addr   = addr;
            wr_symbol = sym;
            wr_bits   = bits;
            @(negedge clk);
            wr_en     = 1'b0;
        end
    endtask

    task automatic do_read(input [MAX_BITS-1:0] addr,
                           input [SYMBOL_WIDTH-1:0] expect_sym,
                           input [CODE_BITS_W-1:0] expect_bits);
        begin
            @(negedge clk);
            rd_en   = 1'b1;
            rd_addr = addr;
            @(negedge clk);
            rd_en   = 1'b0;
            @(negedge clk);
            checks = checks + 1;
            if (rd_symbol !== expect_sym || rd_bits !== expect_bits) begin
                errors = errors + 1;
                $display("FAIL lut[%0d]: got sym=%0d bits=%0d expected sym=%0d bits=%0d",
                         addr, rd_symbol, rd_bits, expect_sym, expect_bits);
            end else begin
                $display("PASS lut[%0d] = (sym=%0d bits=%0d)", addr, rd_symbol, rd_bits);
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        do_write(5'd0,  16'd42, 5'd3);
        do_write(5'd1,  16'd7,  5'd4);
        do_write(5'd7,  16'd257,5'd5);
        do_write(5'd15, 16'd0,  5'd1);
        do_write(5'd31, 16'd65535, 5'd15);

        do_read(5'd0,  16'd42, 5'd3);
        do_read(5'd1,  16'd7,  5'd4);
        do_read(5'd7,  16'd257,5'd5);
        do_read(5'd15, 16'd0,  5'd1);
        do_read(5'd31, 16'd65535, 5'd15);

        $display("--------------------------------------------------");
        $display("LUT TESTS: checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("LUT RESULT: ALL PASS");
        else             $display("LUT RESULT: FAILURES=%0d", errors);
        $finish;
    end

endmodule
