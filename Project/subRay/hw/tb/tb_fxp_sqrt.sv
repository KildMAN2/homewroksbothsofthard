// -----------------------------------------------------------------------------
// tb_fxp_sqrt.sv
// Self-checking testbench for the iterative integer square root.
// Compares DUT output against floor(sqrt(radicand)) for several radicands,
// including zero and perfect squares. Exact integer comparison.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_fxp_sqrt;

    logic        clk = 0;
    logic        rst_n = 0;
    logic        start = 0;
    logic [63:0] radicand = 0;
    logic [31:0] root;
    logic        done;

    integer errors = 0;
    integer checks = 0;

    fxp_sqrt dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .radicand(radicand), .root(root), .done(done)
    );

    always #5 clk = ~clk;

    // Reference floor-sqrt via a simple loop (avoids real-precision issues).
    function automatic [31:0] ref_isqrt(input [63:0] x);
        logic [63:0] r;
        r = 0;
        // increase r while (r+1)^2 <= x, bounded by 32 bits
        while (((r + 1) * (r + 1)) <= x && r < 64'hFFFFFFFF) r = r + 1;
        return r[31:0];
    endfunction

    task automatic run_one(input [63:0] x);
        logic [31:0] expected;
        begin
            expected = ref_isqrt(x);
            @(negedge clk);
            radicand = x;
            start = 1;
            @(negedge clk);
            start = 0;
            // wait for done
            wait (done == 1'b1);
            @(negedge clk);
            checks = checks + 1;
            if (root !== expected) begin
                errors = errors + 1;
                $display("FAIL sqrt(%0d): got %0d expected %0d", x, root, expected);
            end else begin
                $display("PASS sqrt(%0d) = %0d", x, root);
            end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        run_one(64'd0);
        run_one(64'd1);
        run_one(64'd2);
        run_one(64'd4);
        run_one(64'd15);
        run_one(64'd16);
        run_one(64'd17);
        run_one(64'd100);
        run_one(64'd123456);
        run_one(64'd4294836225); // 65535^2
        run_one(64'h0000_0004_0000_0000); // 4 * 2^32 -> root 2^17 (Q16.16 of 2.0)

        $display("--------------------------------------------------");
        $display("SQRT TESTS: checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("SQRT RESULT: ALL PASS");
        else             $display("SQRT RESULT: FAILURES=%0d", errors);
        $finish;
    end

endmodule
