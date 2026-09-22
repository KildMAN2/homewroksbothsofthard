// -----------------------------------------------------------------------------
// fxp_sqrt.sv
// Iterative (digit-by-digit) integer square root.
//
// Computes root = floor(sqrt(radicand)) for a 64-bit unsigned radicand,
// producing a 32-bit result. One radicand "pair of bits" is processed per
// clock cycle, so a conversion takes 32 cycles after `start`.
//
// Scaling note (how this yields a Q16.16 root from a Q32.32 value):
//   If the input represents a real value X in Q32.32 fixed-point, then the
//   stored integer is  X * 2^32. Taking the integer square root gives
//   floor( sqrt(X) * 2^16 ), which is exactly sqrt(X) in Q16.16. The caller
//   (sphere_intersect) relies on this identity, so no extra shifting is needed.
//
// This module is synthesizable: fixed 32-iteration loop, no unbounded loops.
// -----------------------------------------------------------------------------
module fxp_sqrt (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,      // pulse to begin a conversion
    input  logic [63:0] radicand,   // unsigned value to take the root of
    output logic [31:0] root,       // floor(sqrt(radicand))
    output logic        done        // 1-cycle pulse when `root` is valid
);

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state;

    logic [63:0] op;    // remaining radicand
    logic [63:0] res;   // accumulating result
    logic [63:0] bitmask; // current "one" position, starts at 1<<62, >>2 each step
    logic [5:0]  iter;  // iteration counter 0..31

    // Combinational next-values for one digit iteration.
    logic [63:0] sum;
    logic [63:0] op_next;
    logic [63:0] res_next;

    always_comb begin
        sum = res + bitmask;
        if (op >= sum) begin
            op_next  = op - sum;
            res_next = (res >> 1) + bitmask;
        end else begin
            op_next  = op;
            res_next = (res >> 1);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            op      <= '0;
            res     <= '0;
            bitmask <= '0;
            iter    <= '0;
            root    <= '0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        op      <= radicand;
                        res     <= '0;
                        // Largest power-of-four <= 2^62. Starting here and doing a
                        // fixed 32 iterations is equivalent to the classic
                        // "shrink bit until <= radicand" pre-loop: while bit>op the
                        // comparison simply shifts res, leaving it zero.
                        bitmask <= 64'h4000_0000_0000_0000;
                        iter    <= '0;
                        state   <= S_RUN;
                    end
                end
                S_RUN: begin
                    op      <= op_next;
                    res     <= res_next;
                    bitmask <= bitmask >> 2;
                    iter    <= iter + 6'd1;
                    if (iter == 6'd31) begin
                        // res_next holds the final root this cycle.
                        root  <= res_next[31:0];
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
