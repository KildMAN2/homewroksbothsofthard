// -----------------------------------------------------------------------------
// tb_intersect_accel.sv
// Self-checking testbench for the top intersection accelerator.
//
// A real-valued reference model replicates the DUT's fixed-point formulas
// (sphere: t = v - sqrt(disc); plane quirk from the original raytracer:
// t = 1 / (-dot(D,N)) ). DUT results are compared to the reference:
//   - hit_valid / hit_kind / hit_id checked exactly
//   - hit_t checked within a fixed-point tolerance
//   - visibility mode checks vis_clear
//
// Covered cases: direct hit, plane-only hit, no-hit (ray escapes),
// off-axis / small-component direction, several consecutive rays (FSM
// re-entry), and visibility mode blocked vs clear.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module tb_intersect_accel;

    localparam int WIDTH = 32;
    localparam int FRAC  = 16;
    localparam int NUM   = 4;
    localparam int ID_W  = 8;

    real EPS = 0.001;
    real TOL = 0.05;

    logic clk = 0, rst_n = 0, start = 0, mode = 0;
    logic signed [WIDTH-1:0] epsilon;
    logic signed [WIDTH-1:0] ray_ox, ray_oy, ray_oz, ray_dx, ray_dy, ray_dz;
    logic signed [NUM*WIDTH-1:0] sph_cx_flat, sph_cy_flat, sph_cz_flat, sph_r_flat;
    logic        [NUM*ID_W-1:0]  sph_id_flat;
    logic signed [WIDTH-1:0] plane_nx, plane_ny, plane_nz;
    logic        [ID_W-1:0]  plane_id;

    logic                    done, busy, hit_valid, vis_clear;
    logic [1:0]              hit_kind;
    logic [ID_W-1:0]         hit_id;
    logic signed [WIDTH-1:0] hit_t;

    integer errors = 0, checks = 0;

    // Scene (real, for reference).
    real scx [NUM]; real scy [NUM]; real scz [NUM]; real sr [NUM];
    integer sid [NUM];

    intersect_accel #(.WIDTH(WIDTH), .FRAC(FRAC), .NUM_SPHERES(NUM), .ID_W(ID_W)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .mode(mode), .epsilon(epsilon),
        .ray_ox(ray_ox), .ray_oy(ray_oy), .ray_oz(ray_oz),
        .ray_dx(ray_dx), .ray_dy(ray_dy), .ray_dz(ray_dz),
        .sph_cx_flat(sph_cx_flat), .sph_cy_flat(sph_cy_flat),
        .sph_cz_flat(sph_cz_flat), .sph_r_flat(sph_r_flat), .sph_id_flat(sph_id_flat),
        .plane_nx(plane_nx), .plane_ny(plane_ny), .plane_nz(plane_nz), .plane_id(plane_id),
        .done(done), .busy(busy), .hit_valid(hit_valid), .hit_kind(hit_kind),
        .hit_id(hit_id), .hit_t(hit_t), .vis_clear(vis_clear)
    );

    always #5 clk = ~clk;

    // ---- fixed-point conversion helpers ----
    function automatic logic signed [WIDTH-1:0] f2q(input real x);
        return $rtoi(x * 65536.0);
    endfunction
    function automatic real q2f(input logic signed [WIDTH-1:0] x);
        return real'(x) / 65536.0;
    endfunction

    // ---- reference model: closest hit ----
    task automatic ref_closest(
        input real ox, oy, oz, dx, dy, dz,
        output bit rvalid, output int rkind, output int rid, output real rt
    );
        real cpx, cpy, cpz, v, cp2, disc, st, proj, tp;
        bit have; real bestt; int bk, bid;
        begin
            have = 0; bestt = 0.0; bk = 0; bid = 0;
            for (int i = 0; i < NUM; i++) begin
                cpx = scx[i] - ox; cpy = scy[i] - oy; cpz = scz[i] - oz;
                v   = cpx*dx + cpy*dy + cpz*dz;
                cp2 = cpx*cpx + cpy*cpy + cpz*cpz;
                disc = sr[i]*sr[i] - (cp2 - v*v);
                if (disc >= 0.0) begin
                    st = v - $sqrt(disc);
                    if (st > -EPS) begin
                        if (!have || st < bestt) begin
                            have = 1; bestt = st; bk = 1; bid = sid[i];
                        end
                    end
                end
            end
            // plane quirk: t = 1 / (-dot(D,N)), N=(0,1,0)
            proj = dx*0.0 + dy*1.0 + dz*0.0;
            if (proj != 0.0) begin
                tp = 1.0 / (-proj);
                if (tp > -EPS) begin
                    if (!have || tp < bestt) begin
                        have = 1; bestt = tp; bk = 2; bid = 9;
                    end
                end
            end
            rvalid = have; rkind = have ? bk : 0; rid = bid; rt = bestt;
        end
    endtask

    // ---- reference model: visibility (any blocker with t > +EPS) ----
    task automatic ref_visible(
        input real ox, oy, oz, dx, dy, dz, output bit clear
    );
        real cpx, cpy, cpz, v, cp2, disc, st, proj, tp;
        bit blocked;
        begin
            blocked = 0;
            for (int i = 0; i < NUM; i++) begin
                cpx = scx[i] - ox; cpy = scy[i] - oy; cpz = scz[i] - oz;
                v   = cpx*dx + cpy*dy + cpz*dz;
                cp2 = cpx*cpx + cpy*cpy + cpz*cpz;
                disc = sr[i]*sr[i] - (cp2 - v*v);
                if (disc >= 0.0) begin
                    st = v - $sqrt(disc);
                    if (st > EPS) blocked = 1;
                end
            end
            proj = dy;
            if (proj != 0.0) begin
                tp = 1.0 / (-proj);
                if (tp > EPS) blocked = 1;
            end
            clear = ~blocked;
        end
    endtask

    // Normalize a direction then drive one ray, wait, and check.
    task automatic run_ray(input string name, input bit vmode,
                           input real ox, oy, oz, dx, dy, dz);
        real nrm, ndx, ndy, ndz;
        bit  rvalid; int rkind; int rid; real rt; bit rclear;
        begin
            nrm = $sqrt(dx*dx + dy*dy + dz*dz);
            ndx = dx / nrm; ndy = dy / nrm; ndz = dz / nrm;

            @(negedge clk);
            mode   = vmode;
            ray_ox = f2q(ox); ray_oy = f2q(oy); ray_oz = f2q(oz);
            ray_dx = f2q(ndx); ray_dy = f2q(ndy); ray_dz = f2q(ndz);
            start  = 1'b1;
            @(negedge clk);
            start  = 1'b0;
            wait (done == 1'b1);
            @(negedge clk);

            checks = checks + 1;
            if (!vmode) begin
                ref_closest(ox, oy, oz, ndx, ndy, ndz, rvalid, rkind, rid, rt);
                if (hit_valid !== rvalid) begin
                    errors = errors + 1;
                    $display("FAIL [%s] valid: got %0d exp %0d", name, hit_valid, rvalid);
                end else if (rvalid) begin
                    if (hit_kind !== rkind[1:0] || hit_id !== rid[ID_W-1:0]) begin
                        errors = errors + 1;
                        $display("FAIL [%s] kind/id: got kind=%0d id=%0d exp kind=%0d id=%0d",
                                 name, hit_kind, hit_id, rkind, rid);
                    end else if ((q2f(hit_t) - rt) > TOL || (rt - q2f(hit_t)) > TOL) begin
                        errors = errors + 1;
                        $display("FAIL [%s] t: got %f exp %f", name, q2f(hit_t), rt);
                    end else begin
                        $display("PASS [%s] kind=%0d id=%0d t=%f (exp %f)",
                                 name, hit_kind, hit_id, q2f(hit_t), rt);
                    end
                end else begin
                    $display("PASS [%s] no-hit", name);
                end
            end else begin
                ref_visible(ox, oy, oz, ndx, ndy, ndz, rclear);
                if (vis_clear !== rclear) begin
                    errors = errors + 1;
                    $display("FAIL [%s] vis_clear: got %0d exp %0d", name, vis_clear, rclear);
                end else begin
                    $display("PASS [%s] vis_clear=%0d", name, vis_clear);
                end
            end
        end
    endtask

    initial begin
        // Scene definition.
        scx[0] =  0.0; scy[0] = 0.0; scz[0] = -10.0; sr[0] = 2.0; sid[0] = 1;
        scx[1] =  3.0; scy[1] = 0.0; scz[1] = -10.0; sr[1] = 1.0; sid[1] = 2;
        scx[2] = -3.0; scy[2] = 0.0; scz[2] = -10.0; sr[2] = 1.0; sid[2] = 3;
        scx[3] =  0.0; scy[3] = 3.0; scz[3] = -10.0; sr[3] = 1.0; sid[3] = 4;

        sph_cx_flat = { f2q(scx[3]), f2q(scx[2]), f2q(scx[1]), f2q(scx[0]) };
        sph_cy_flat = { f2q(scy[3]), f2q(scy[2]), f2q(scy[1]), f2q(scy[0]) };
        sph_cz_flat = { f2q(scz[3]), f2q(scz[2]), f2q(scz[1]), f2q(scz[0]) };
        sph_r_flat  = { f2q(sr[3]),  f2q(sr[2]),  f2q(sr[1]),  f2q(sr[0])  };
        sph_id_flat = { 8'd4, 8'd3, 8'd2, 8'd1 };

        plane_nx = f2q(0.0); plane_ny = f2q(1.0); plane_nz = f2q(0.0);
        plane_id = 8'd9;
        epsilon  = f2q(EPS);

        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // Consecutive rays exercise FSM re-entry (back-to-back).
        run_ray("A_direct_sphere",  1'b0,  0.0, 0.0, 0.0,   0.0, 0.0, -1.0);
        run_ray("B_plane_only",     1'b0,  0.0, 5.0, 0.0,   0.0,-1.0,  0.0);
        run_ray("C_escape_no_hit",  1'b0,  0.0, 0.0, 0.0,   0.0, 1.0,  0.0);
        run_ray("D_offaxis_small",  1'b0,  0.0, 0.0, 0.0,   0.2, 0.0, -1.0);
        run_ray("E_side_sphere",    1'b0,  3.0, 0.0, 0.0,   0.0, 0.0, -1.0);

        // Visibility mode.
        run_ray("F_vis_blocked",    1'b1,  3.0, 0.0, 0.0,   0.0, 0.0, -1.0);
        run_ray("G_vis_clear",      1'b1, 10.0,10.0, 0.0,   0.0, 0.0, -1.0);

        $display("--------------------------------------------------");
        $display("ACCEL TESTS: checks=%0d errors=%0d", checks, errors);
        if (errors == 0) $display("ACCEL RESULT: ALL PASS");
        else             $display("ACCEL RESULT: FAILURES=%0d", errors);
        $finish;
    end

endmodule
