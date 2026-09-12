`timescale 1ns/1ps

module tb_nbody_accel_v2;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic in_valid = 1'b0;
    logic in_ready;
    logic signed [31:0] dx = '0;
    logic signed [31:0] dy = '0;
    logic signed [31:0] dz = '0;
    logic [31:0] mass_i = '0;
    logic [31:0] mass_j = '0;
    logic [31:0] dt = '0;
    logic out_valid;
    logic out_ready = 1'b1;
    logic signed [31:0] dvix;
    logic signed [31:0] dviy;
    logic signed [31:0] dviz;
    logic signed [31:0] dvjx;
    logic signed [31:0] dvjy;
    logic signed [31:0] dvjz;

    nbody_accel_v2 dut (.*);

    always #5 clk = ~clk;

    task automatic check_outputs(
        input logic signed [31:0] expected_dvix,
        input logic signed [31:0] expected_dvjx
    );
        begin
            if (!out_valid || dvix !== expected_dvix || dviy !== 0 || dviz !== 0 ||
                dvjx !== expected_dvjx || dvjy !== 0 || dvjz !== 0) begin
                $fatal(1, "Output mismatch: valid=%0b dvix=%0d dvjx=%0d", out_valid, dvix, dvjx);
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Transaction 1: delta=1, inv_r3=1, scale_i=1.5, scale_j=1.0.
        @(negedge clk);
        in_valid = 1'b1;
        dx = 32'sd65536;
        mass_i = 32'd131072;
        mass_j = 32'd196608;
        dt = 32'd32768;

        // Transaction 2: delta=-2, inv_r3=1/8, scale_i=0.25, scale_j=0.5.
        @(negedge clk);
        if (!in_ready) $fatal(1, "Pipeline did not accept the second back-to-back transaction");
        dx = -32'sd131072;
        mass_i = 32'd262144;
        mass_j = 32'd131072;
        dt = 32'd65536;

        @(negedge clk);
        in_valid = 1'b0;
        out_ready = 1'b0;

        wait (out_valid);
        #1 check_outputs(-32'sd98304, 32'sd65536);

        // A blocked output must remain valid and bit-for-bit stable.
        repeat (3) begin
            @(posedge clk);
            #1 check_outputs(-32'sd98304, 32'sd65536);
            if (in_ready) $fatal(1, "in_ready asserted while the full pipeline was stalled");
        end

        @(negedge clk);
        out_ready = 1'b1;
        @(posedge clk);
        #1 check_outputs(32'sd32768, -32'sd65536);

        @(posedge clk);
        #1;
        if (out_valid) $fatal(1, "out_valid did not clear after the final output transfer");

        $display("NBODY_ACCEL_V2_TEST=PASS");
        $finish;
    end
endmodule