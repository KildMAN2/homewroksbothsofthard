module mdp_transition_accel (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         in_valid,
    output logic         in_ready,
    input  logic [15:0]  prob,
    input  logic signed [31:0] reward,
    input  logic signed [31:0] value_next,
    input  logic [15:0]  gamma,
    output logic         out_valid,
    input  logic         out_ready,
    output logic signed [31:0] score
);

    logic signed [47:0] discount_term;
    logic signed [47:0] reward_plus_v;
    logic signed [63:0] weighted;

    assign in_ready = out_ready | ~out_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            score <= '0;
        end else if (in_valid && in_ready) begin
            discount_term <= $signed(value_next) * $signed({1'b0, gamma});
            reward_plus_v <= $signed(reward <<< 16) + discount_term;
            weighted <= reward_plus_v * $signed({1'b0, prob});
            score <= weighted[63:32];
            out_valid <= 1'b1;
        end else if (out_valid && out_ready) begin
            out_valid <= 1'b0;
        end
    end

endmodule
