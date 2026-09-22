// -----------------------------------------------------------------------------
// sphere_intersect.sv
// Ray/sphere intersection for a single sphere in signed Q16.16 fixed-point.
//
// Given a ray  P + t*D  (D assumed normalized by software) and a sphere with
// center C and radius r, this computes the nearest intersection distance:
//
//   CP   = C - P
//   v    = dot(CP, D)
//   cp2  = dot(CP, CP)
//   disc = r*r - (cp2 - v*v)
//   if disc < 0        -> no hit
//   t    = v - sqrt(disc)
//   hit  = (t > threshold)
//
// Fixed-point scaling:
//   Inputs are Q16.16. A product of two Q16.16 values is Q32.32 (64-bit).
//   v is reduced back to Q16.16 (v16) before squaring so that cp2, r2 and v*v
//   all share the Q32.32 domain. `disc` is therefore Q32.32 and is fed directly
//   to fxp_sqrt, which returns the root already scaled to Q16.16.
//
// Multi-cycle: latency = a few control cycles + 32 sqrt cycles.
// -----------------------------------------------------------------------------
module sphere_intersect #(
    parameter int WIDTH = 32,
    parameter int FRAC  = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      start,
    // ray
    input  logic signed [WIDTH-1:0]   px, py, pz,
    input  logic signed [WIDTH-1:0]   dx, dy, dz,
    // sphere
    input  logic signed [WIDTH-1:0]   cx, cy, cz,
    input  logic signed [WIDTH-1:0]   r,
    // validity threshold (Q16.16). Caller passes -epsilon or +epsilon.
    input  logic signed [WIDTH-1:0]   thr,
    output logic                      done,
    output logic                      hit_valid,
    output logic signed [WIDTH-1:0]   t_out
);

    typedef enum logic [1:0] {S_IDLE, S_CALC, S_SQRT, S_FIN} state_t;
    state_t state;

    // Latched ray/sphere inputs.
    logic signed [WIDTH-1:0] lpx, lpy, lpz, ldx, ldy, ldz;
    logic signed [WIDTH-1:0] lcx, lcy, lcz, lr, lthr;

    // Combinational geometry (from latched inputs).
    logic signed [WIDTH-1:0] cpx, cpy, cpz;
    logic signed [63:0]      v_q32;     // Q32.32
    logic signed [63:0]      cp2_q32;   // Q32.32
    logic signed [63:0]      r2_q32;    // Q32.32
    logic signed [WIDTH-1:0] v16;       // Q16.16
    logic signed [63:0]      vv_q32;    // Q32.32
    logic signed [63:0]      disc_q32;  // Q32.32

    always_comb begin
        cpx = lcx - lpx;
        cpy = lcy - lpy;
        cpz = lcz - lpz;

        v_q32   = ($signed(cpx) * $signed(ldx))
                + ($signed(cpy) * $signed(ldy))
                + ($signed(cpz) * $signed(ldz));

        cp2_q32 = ($signed(cpx) * $signed(cpx))
                + ($signed(cpy) * $signed(cpy))
                + ($signed(cpz) * $signed(cpz));

        r2_q32  = $signed(lr) * $signed(lr);

        // Reduce v from Q32.32 to Q16.16 (arithmetic shift keeps sign).
        v16     = v_q32 >>> FRAC;
        vv_q32  = $signed(v16) * $signed(v16);

        disc_q32 = r2_q32 - cp2_q32 + vv_q32;
    end

    // sqrt interface
    logic        sq_start;
    logic [63:0] sq_rad;
    logic [31:0] sq_root;
    logic        sq_done;

    fxp_sqrt u_sqrt (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (sq_start),
        .radicand (sq_rad),
        .root     (sq_root),
        .done     (sq_done)
    );

    logic signed [WIDTH-1:0] v16_reg; // hold v16 while sqrt runs

    // Candidate near intersection distance once the root is available.
    logic signed [WIDTH-1:0] t_calc;
    assign t_calc = v16_reg - $signed(sq_root);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            done      <= 1'b0;
            hit_valid <= 1'b0;
            t_out     <= '0;
            sq_start  <= 1'b0;
            sq_rad    <= '0;
            v16_reg   <= '0;
            {lpx,lpy,lpz,ldx,ldy,ldz} <= '0;
            {lcx,lcy,lcz,lr,lthr}     <= '0;
        end else begin
            done     <= 1'b0;
            sq_start <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        lpx <= px; lpy <= py; lpz <= pz;
                        ldx <= dx; ldy <= dy; ldz <= dz;
                        lcx <= cx; lcy <= cy; lcz <= cz;
                        lr  <= r;  lthr <= thr;
                        state <= S_CALC;
                    end
                end
                S_CALC: begin
                    // disc_q32 now valid from latched inputs.
                    if (disc_q32 < 0) begin
                        hit_valid <= 1'b0;
                        t_out     <= '0;
                        done      <= 1'b1;
                        state     <= S_IDLE;
                    end else begin
                        v16_reg  <= v16;
                        sq_rad   <= disc_q32[63:0]; // non-negative here
                        sq_start <= 1'b1;
                        state    <= S_SQRT;
                    end
                end
                S_SQRT: begin
                    if (sq_done) begin
                        // t = v - sqrt(disc), both Q16.16.
                        t_out     <= t_calc;
                        hit_valid <= (t_calc > lthr);
                        done      <= 1'b1;
                        state     <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
