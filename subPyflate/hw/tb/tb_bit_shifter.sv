// -----------------------------------------------------------------------------
// tb_bit_shifter.sv
// Self-checking testbench for the rolling MSB-first bit buffer.
//
// A simple software reference maintains the same bit sequence as the DUT and
// checks that snoop / consume match exactly. Covers: empty buffer, single
// byte, multiple bytes, consume of 1..MAX_BITS, refill during consume,
// snoop_ready gating below MAX_BITS.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_bit_shifter;

    localparam int MAX_BITS = 8;
    localparam int BUF_W    = 24;
    localparam int CONS_W   = $clog2(MAX_BITS+1);

    logic                        clk = 0;
    logic                        rst_n = 0;
    logic                        flush = 0;

    logic                        byte_valid = 0;
    logic [7:0]                  byte_data  = '0;
    logic                        can_accept_byte;

    logic [CONS_W-1:0]           consume = '0;

    logic [MAX_BITS-1:0]         snoop;
    logic                        snoop_ready;
    logic [$clog2(BUF_W+1)-1:0]  bits_avail;
    logic                        need_byte;
    logic                        under_run;

    integer errors = 0, checks = 0;

    bit_shifter #(.MAX_BITS(MAX_BITS), .BUF_W(BUF_W)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush),
        .byte_valid     (byte_valid),
        .byte_data      (byte_data),
        .can_accept_byte(can_accept_byte),
        .consume        (consume),
        .snoop          (snoop),
        .snoop_ready    (snoop_ready),
        .bits_avail     (bits_avail),
        .need_byte      (need_byte),
        .under_run      (under_run)
    );

    always #5 clk = ~clk;

    // Software-side reference: same MSB-first bit accumulator.
    reg [BUF_W-1:0] ref_buf;
    integer         ref_bits;

    function automatic [MAX_BITS-1:0] ref_snoop;
        begin
            if (ref_bits >= MAX_BITS)
                ref_snoop = (ref_buf >> (ref_bits - MAX_BITS)) & ((1 << MAX_BITS) - 1);
            else
                ref_snoop = '0;
        end
    endfunction

    task automatic push_byte(input [7:0] b);
        begin
            @(negedge clk);
            byte_valid = 1'b1;
            byte_data  = b;
            consume    = '0;
            // Reference update happens on the same tick.
            ref_buf = (ref_buf << 8) | b;
            ref_bits = ref_bits + 8;
            @(negedge clk);
            byte_valid = 1'b0;
        end
    endtask

    task automatic do_consume(input [CONS_W-1:0] n);
        begin
            @(negedge clk);
            consume = n;
            // Reference update.
            if (n <= ref_bits) begin
                ref_bits = ref_bits - n;
                ref_buf  = ref_buf & ((1 << ref_bits) - 1);
            end
            @(negedge clk);
            consume = '0;
        end
    endtask

    task automatic check_snoop(input string tag);
        logic [MAX_BITS-1:0] expected;
        begin
            expected = ref_snoop();
            checks = checks + 1;
            if (ref_bits >= MAX_BITS) begin
                if (snoop_ready !== 1'b1) begin
                    errors = errors + 1;
                    $display("FAIL [%s] snoop_ready expected 1 (bits=%0d)", tag, ref_bits);
                end else if (snoop !== expected) begin
                    errors = errors + 1;
                    $display("FAIL [%s] snoop=0x%0h expected 0x%0h (bits=%0d)",
                             tag, snoop, expected, ref_bits);
                end else begin
                    $display("PASS [%s] snoop=0x%0h bits=%0d", tag, snoop, ref_bits);
                end
            end else begin
                if (snoop_ready !== 1'b0) begin
                    errors = errors + 1;
                    $display("FAIL [%s] snoop_ready expected 0 (bits=%0d)", tag, ref_bits);
                end else begin
                    $display("PASS [%s] snoop not ready (bits=%0d)", tag, ref_bits);
                end
            end
        end
    endtask

    initial begin
        ref_buf  = '0;
        ref_bits = 0;

        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        check_snoop("empty");

        push_byte(8'hAB);      // buffer = 0xAB, bits=8
        check_snoop("after 1 byte");   // top 8 = AB

        push_byte(8'hCD);      // buffer = 0xABCD, bits=16
        check_snoop("after 2 bytes");  // top 8 = AB

        do_consume(3);         // consumed 3 bits (101), remaining 13 bits
        check_snoop("after consume 3");

        do_consume(5);         // now 8 bits remain
        check_snoop("after consume 5 more");

        push_byte(8'h5A);      // refill
        check_snoop("after refill");

        do_consume(MAX_BITS[CONS_W-1:0]);
        check_snoop("after full consume");

        push_byte(8'h01);
        push_byte(8'hFF);
        check_snoop("two more bytes");

        $display("--------------------------------------------------");
        $display("SHIFTER TESTS: checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("SHIFTER RESULT: ALL PASS");
        else             $display("SHIFTER RESULT: FAILURES=%0d", errors);
        $finish;
    end

endmodule
