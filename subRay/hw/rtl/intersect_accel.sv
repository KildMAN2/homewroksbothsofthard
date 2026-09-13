// -----------------------------------------------------------------------------
// intersect_accel.sv
// Top-level ray-intersection accelerator.
//
// For a single input ray, iterates over NUM_SPHERES spheres (streamed one at a
// time through a shared sphere_intersect unit), performs the plane intersection,
// and reduces to the nearest valid hit.
//
// Modes:
//   mode = 0 (closest-hit): validity threshold = -epsilon, reports nearest hit.
//   mode = 1 (visibility) : validity threshold = +epsilon, `vis_clear` = 1 when
//                           NO blocker was found (i.e. light is visible).
//
// Numeric format: signed Q16.16 fixed-point throughout (see module comments in
// sphere_intersect.sv / fxp_sqrt.sv for scaling proofs).
//
// Scene inputs are passed as flattened packed vectors and sliced by index so the
// port list stays portable across simulators.
// -----------------------------------------------------------------------------
module intersect_accel #(
    parameter int WIDTH       = 32,
    parameter int FRAC        = 16,
    parameter int NUM_SPHERES = 4,
    parameter int ID_W        = 8
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          start,
    input  logic                          mode,     // 0=closest-hit, 1=visibility
    input  logic signed [WIDTH-1:0]       epsilon,  // Q16.16, positive

    // ray
    input  logic signed [WIDTH-1:0]       ray_ox, ray_oy, ray_oz,
    input  logic signed [WIDTH-1:0]       ray_dx, ray_dy, ray_dz,

    // spheres (flattened)
    input  logic signed [NUM_SPHERES*WIDTH-1:0] sph_cx_flat,
    input  logic signed [NUM_SPHERES*WIDTH-1:0] sph_cy_flat,
    input  logic signed [NUM_SPHERES*WIDTH-1:0] sph_cz_flat,
    input  logic signed [NUM_SPHERES*WIDTH-1:0] sph_r_flat,
    input  logic        [NUM_SPHERES*ID_W-1:0]  sph_id_flat,

    // plane
    input  logic signed [WIDTH-1:0]       plane_nx, plane_ny, plane_nz,
    input  logic        [ID_W-1:0]        plane_id,

    // results
    output logic                          done,
    output logic                          busy,
    output logic                          hit_valid,
    output logic [1:0]                     hit_kind,  // 0=none,1=sphere,2=plane
    output logic [ID_W-1:0]               hit_id,
    output logic signed [WIDTH-1:0]       hit_t,     // Q16.16
    output logic                          vis_clear
);

    localparam int IDX_W = (NUM_SPHERES <= 1) ? 1 : $clog2(NUM_SPHERES);

    typedef enum logic [2:0] {
        T_IDLE, T_SPH_START, T_SPH_WAIT, T_PLANE, T_FIN
    } state_t;
    state_t state;

    logic [IDX_W:0] idx; // one extra bit so it can reach NUM_SPHERES

    // Selected sphere fields (combinational slice by idx).
    logic signed [WIDTH-1:0] sel_cx, sel_cy, sel_cz, sel_r;
    logic        [ID_W-1:0]  sel_id;

    always_comb begin
        sel_cx = sph_cx_flat[idx*WIDTH +: WIDTH];
        sel_cy = sph_cy_flat[idx*WIDTH +: WIDTH];
        sel_cz = sph_cz_flat[idx*WIDTH +: WIDTH];
        sel_r  = sph_r_flat [idx*WIDTH +: WIDTH];
        sel_id = sph_id_flat[idx*ID_W  +: ID_W];
    end

    // Validity threshold depends on mode.
    logic signed [WIDTH-1:0] thr;
    always_comb begin
        thr = mode ? epsilon : -epsilon;
    end

    // sphere_intersect interface
    logic                    s_start;
    logic                    s_done;
    logic                    s_hit_valid;
    logic signed [WIDTH-1:0] s_t;

    sphere_intersect #(.WIDTH(WIDTH), .FRAC(FRAC)) u_sphere (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (s_start),
        .px       (ray_ox), .py(ray_oy), .pz(ray_oz),
        .dx       (ray_dx), .dy(ray_dy), .dz(ray_dz),
        .cx       (sel_cx), .cy(sel_cy), .cz(sel_cz),
        .r        (sel_r),
        .thr      (thr),
        .done     (s_done),
        .hit_valid(s_hit_valid),
        .t_out    (s_t)
    );

    // Min-reduction registers.
    logic                    best_valid;
    logic signed [WIDTH-1:0] best_t;
    logic [1:0]              best_kind;
    logic [ID_W-1:0]         best_id;

    // ---- Plane intersection (combinational) ----
    // proj = dot(D, N); t_plane = 1 / (-proj).
    logic signed [63:0]      proj_q32;
    logic signed [WIDTH-1:0] proj16;
    logic signed [63:0]      neg_proj;
    logic signed [63:0]      t_plane_q64;   // 2^(2*FRAC) / (-proj16) -> Q16.16
    logic signed [WIDTH-1:0] t_plane;
    logic                    plane_hit;

    always_comb begin
        proj_q32 = ($signed(ray_dx) * $signed(plane_nx))
                 + ($signed(ray_dy) * $signed(plane_ny))
                 + ($signed(ray_dz) * $signed(plane_nz));
        proj16   = proj_q32 >>> FRAC;             // Q16.16
        neg_proj = -$signed({{32{proj16[WIDTH-1]}}, proj16}); // sign-extend then negate

        if (proj16 == '0) begin
            // Ray parallel to plane: no intersection.
            t_plane_q64 = '0;
            t_plane     = '0;
            plane_hit   = 1'b0;
        end else begin
            // (1.0 in Q16.16)^2 numerator = 2^(2*FRAC) gives a Q16.16 quotient.
            t_plane_q64 = ($signed(64'sd1) <<< (2*FRAC)) / neg_proj;
            t_plane     = t_plane_q64[WIDTH-1:0];
            plane_hit   = (t_plane > thr);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= T_IDLE;
            idx        <= '0;
            s_start    <= 1'b0;
            done       <= 1'b0;
            busy       <= 1'b0;
            best_valid <= 1'b0;
            best_t     <= '0;
            best_kind  <= 2'd0;
            best_id    <= '0;
            hit_valid  <= 1'b0;
            hit_kind   <= 2'd0;
            hit_id     <= '0;
            hit_t      <= '0;
            vis_clear  <= 1'b0;
        end else begin
            done    <= 1'b0;
            s_start <= 1'b0;
            case (state)
                T_IDLE: begin
                    if (start) begin
                        idx        <= '0;
                        best_valid <= 1'b0;
                        best_t     <= '0;
                        best_kind  <= 2'd0;
                        best_id    <= '0;
                        busy       <= 1'b1;
                        state      <= T_SPH_START;
                    end
                end
                T_SPH_START: begin
                    // Launch intersection for sphere[idx].
                    s_start <= 1'b1;
                    state   <= T_SPH_WAIT;
                end
                T_SPH_WAIT: begin
                    if (s_done) begin
                        // Update nearest-hit reduction with this sphere.
                        if (s_hit_valid &&
                            (!best_valid || (s_t < best_t))) begin
                            best_valid <= 1'b1;
                            best_t     <= s_t;
                            best_kind  <= 2'd1;      // sphere
                            best_id    <= sel_id;
                        end
                        if (idx == NUM_SPHERES-1) begin
                            state <= T_PLANE;
                        end else begin
                            idx   <= idx + 1'b1;
                            state <= T_SPH_START;
                        end
                    end
                end
                T_PLANE: begin
                    if (plane_hit &&
                        (!best_valid || (t_plane < best_t))) begin
                        best_valid <= 1'b1;
                        best_t     <= t_plane;
                        best_kind  <= 2'd2;          // plane
                        best_id    <= plane_id;
                    end
                    state <= T_FIN;
                end
                T_FIN: begin
                    hit_valid <= best_valid;
                    hit_kind  <= best_valid ? best_kind : 2'd0;
                    hit_id    <= best_id;
                    hit_t     <= best_t;
                    // In visibility mode a "hit" means a blocker; clear = no blocker.
                    vis_clear <= ~best_valid;
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    state     <= T_IDLE;
                end
                default: state <= T_IDLE;
            endcase
        end
    end

endmodule
