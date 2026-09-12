module nbody_accel (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    output logic         in_ready,
    input  logic signed [31:0] dx,
    input  logic signed [31:0] dy,
    input  logic signed [31:0] dz,
    input  logic        [31:0] mass_j,
    output logic         out_valid,
    input  logic         out_ready,
    output logic signed [31:0] fx,
    output logic signed [31:0] fy,
    output logic signed [31:0] fz
);

    logic signed [63:0] d2;
    logic signed [63:0] inv_r3;
    logic signed [63:0] scale;

    assign in_ready = out_ready | ~out_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            fx <= '0;
            fy <= '0;
            fz <= '0;
        end else if (in_valid && in_ready) begin
            d2 <= dx*dx + dy*dy + dz*dz + 64'sd65536;
            inv_r3 <= (64'sd1 <<< 40) / d2;
            scale <= inv_r3 * $signed({1'b0, mass_j});
            fx <= (dx * scale) >>> 24;
            fy <= (dy * scale) >>> 24;
            fz <= (dz * scale) >>> 24;
            out_valid <= 1'b1;
        end else if (out_valid && out_ready) begin
            out_valid <= 1'b0;
        end
    end

endmodule
