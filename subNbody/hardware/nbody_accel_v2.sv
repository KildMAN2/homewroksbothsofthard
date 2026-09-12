module nbody_accel_v2 (
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic                 in_valid,
    output logic                 in_ready,
    input  logic signed [31:0]   dx,
    input  logic signed [31:0]   dy,
    input  logic signed [31:0]   dz,
    input  logic        [31:0]   mass_i,
    input  logic        [31:0]   mass_j,
    input  logic        [31:0]   dt,
    output logic                 out_valid,
    input  logic                 out_ready,
    output logic signed [31:0]   dvix,
    output logic signed [31:0]   dviy,
    output logic signed [31:0]   dviz,
    output logic signed [31:0]   dvjx,
    output logic signed [31:0]   dvjy,
    output logic signed [31:0]   dvjz
);

    localparam logic signed [128:0] Q16_MAX = 129'sh00000000000000000000000007fffffff;
    localparam logic signed [128:0] Q16_MIN = -129'sh000000000000000000000000080000000;

    logic pipeline_advance;
    logic valid_s1;
    logic valid_s2;
    logic valid_s3;
    logic valid_s4;
    logic valid_s5;

    logic [63:0] dx_squared;
    logic [63:0] dy_squared;
    logic [63:0] dz_squared;
    logic [63:0] d2_input;

    logic signed [31:0] dx_s1;
    logic signed [31:0] dy_s1;
    logic signed [31:0] dz_s1;
    logic        [31:0] mass_i_s1;
    logic        [31:0] mass_j_s1;
    logic        [31:0] dt_s1;
    logic        [63:0] d2_s1;

    logic signed [31:0] dx_s2;
    logic signed [31:0] dy_s2;
    logic signed [31:0] dz_s2;
    logic        [31:0] mass_i_s2;
    logic        [31:0] mass_j_s2;
    logic        [31:0] dt_s2;
    logic        [95:0] denominator_s2;

    logic signed [31:0] dx_s3;
    logic signed [31:0] dy_s3;
    logic signed [31:0] dz_s3;
    logic        [31:0] mass_i_s3;
    logic        [31:0] mass_j_s3;
    logic        [31:0] dt_s3;
    logic        [31:0] inv_r3_s3;

    logic signed [31:0] dx_s4;
    logic signed [31:0] dy_s4;
    logic signed [31:0] dz_s4;
    logic        [95:0] scale_i_s4;
    logic        [95:0] scale_j_s4;

    logic signed [128:0] dvi_x_full;
    logic signed [128:0] dvi_y_full;
    logic signed [128:0] dvi_z_full;
    logic signed [128:0] dvj_x_full;
    logic signed [128:0] dvj_y_full;
    logic signed [128:0] dvj_z_full;

    function automatic logic [31:0] integer_sqrt_64(input logic [63:0] value);
        logic [65:0] remainder;
        logic [65:0] trial;
        logic [31:0] root;
        integer bit_pair;
        begin
            remainder = '0;
            root = '0;
            for (bit_pair = 31; bit_pair >= 0; bit_pair = bit_pair - 1) begin
                remainder = (remainder << 2) | ((value >> (bit_pair * 2)) & 64'h3);
                trial = ({34'b0, root} << 2) | 66'd1;
                if (remainder >= trial) begin
                    remainder = remainder - trial;
                    root = (root << 1) | 32'd1;
                end else begin
                    root = root << 1;
                end
            end
            integer_sqrt_64 = root;
        end
    endfunction

    function automatic logic [63:0] square_q32(input logic signed [31:0] value);
        logic signed [63:0] value_wide;
        begin
            value_wide = {{32{value[31]}}, value};
            square_q32 = value_wide * value_wide;
        end
    endfunction

    function automatic logic [95:0] denominator_q48(
        input logic [63:0] d2_value,
        input logic [31:0] root_value
    );
        logic [95:0] d2_wide;
        logic [95:0] root_wide;
        begin
            d2_wide = {32'b0, d2_value};
            root_wide = {64'b0, root_value};
            denominator_q48 = d2_wide * root_wide;
        end
    endfunction

    function automatic logic [31:0] reciprocal_r3_q16(input logic [95:0] denominator);
        logic [96:0] numerator;
        logic [96:0] quotient;
        begin
            numerator = 97'd1 << 64;
            if (denominator == 96'd0) begin
                reciprocal_r3_q16 = 32'hffff_ffff;
            end else begin
                quotient = numerator / {1'b0, denominator};
                if (|quotient[96:32]) begin
                    reciprocal_r3_q16 = 32'hffff_ffff;
                end else begin
                    reciprocal_r3_q16 = quotient[31:0];
                end
            end
        end
    endfunction

    function automatic logic [95:0] scale_q48(
        input logic [31:0] dt_value,
        input logic [31:0] mass_value,
        input logic [31:0] inv_r3_value
    );
        logic [63:0] dt_mass;
        logic [95:0] dt_mass_wide;
        logic [95:0] inv_r3_wide;
        begin
            dt_mass = {32'b0, dt_value} * {32'b0, mass_value};
            dt_mass_wide = {32'b0, dt_mass};
            inv_r3_wide = {64'b0, inv_r3_value};
            scale_q48 = dt_mass_wide * inv_r3_wide;
        end
    endfunction

    function automatic logic signed [128:0] delta_scale_q64(
        input logic signed [31:0] delta_value,
        input logic        [95:0] scale_value
    );
        logic signed [128:0] delta_wide;
        logic signed [128:0] scale_wide;
        begin
            delta_wide = {{97{delta_value[31]}}, delta_value};
            scale_wide = {33'b0, scale_value};
            delta_scale_q64 = delta_wide * scale_wide;
        end
    endfunction

    function automatic logic signed [31:0] round_saturate_q16(
        input logic signed [128:0] value_q64
    );
        logic signed [128:0] magnitude;
        logic signed [128:0] scaled;
        begin
            if (value_q64 >= 0) begin
                scaled = (value_q64 + (129'sd1 <<< 47)) >>> 48;
            end else begin
                magnitude = -value_q64;
                scaled = -((magnitude + (129'sd1 <<< 47)) >>> 48);
            end
            if (scaled > Q16_MAX) begin
                round_saturate_q16 = 32'sh7fff_ffff;
            end else if (scaled < Q16_MIN) begin
                round_saturate_q16 = 32'sh8000_0000;
            end else begin
                round_saturate_q16 = scaled[31:0];
            end
        end
    endfunction

    assign dx_squared = square_q32(dx);
    assign dy_squared = square_q32(dy);
    assign dz_squared = square_q32(dz);
    assign d2_input = dx_squared + dy_squared + dz_squared;

    assign pipeline_advance = out_ready | ~valid_s5;
    assign in_ready = pipeline_advance;
    assign out_valid = valid_s5;

    assign dvi_x_full = -delta_scale_q64(dx_s4, scale_i_s4);
    assign dvi_y_full = -delta_scale_q64(dy_s4, scale_i_s4);
    assign dvi_z_full = -delta_scale_q64(dz_s4, scale_i_s4);
    assign dvj_x_full =  delta_scale_q64(dx_s4, scale_j_s4);
    assign dvj_y_full =  delta_scale_q64(dy_s4, scale_j_s4);
    assign dvj_z_full =  delta_scale_q64(dz_s4, scale_j_s4);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_s3 <= 1'b0;
            valid_s4 <= 1'b0;
            valid_s5 <= 1'b0;
            dvix <= '0;
            dviy <= '0;
            dviz <= '0;
            dvjx <= '0;
            dvjy <= '0;
            dvjz <= '0;
        end else if (pipeline_advance) begin
            // Stage 1: capture one Q16.16 pair and accumulate unsigned Q32.32 d2.
            valid_s1 <= in_valid;
            if (in_valid) begin
                dx_s1 <= dx;
                dy_s1 <= dy;
                dz_s1 <= dz;
                mass_i_s1 <= mass_i;
                mass_j_s1 <= mass_j;
                dt_s1 <= dt;
                d2_s1 <= d2_input;
            end

            // Stage 2: compute floor(sqrt(d2)) in Q16.16 and form Q48.48 d2*sqrt(d2).
            valid_s2 <= valid_s1;
            if (valid_s1) begin
                dx_s2 <= dx_s1;
                dy_s2 <= dy_s1;
                dz_s2 <= dz_s1;
                mass_i_s2 <= mass_i_s1;
                mass_j_s2 <= mass_j_s1;
                dt_s2 <= dt_s1;
                denominator_s2 <= denominator_q48(d2_s1, integer_sqrt_64(d2_s1));
            end

            // Stage 3: divide 2^64 by the Q48.48 denominator to obtain saturated Q16.16 1/r^3.
            valid_s3 <= valid_s2;
            if (valid_s2) begin
                dx_s3 <= dx_s2;
                dy_s3 <= dy_s2;
                dz_s3 <= dz_s2;
                mass_i_s3 <= mass_i_s2;
                mass_j_s3 <= mass_j_s2;
                dt_s3 <= dt_s2;
                inv_r3_s3 <= reciprocal_r3_q16(denominator_s2);
            end

            // Stage 4: form Q48 scale_i=dt*mass_j*inv_r3 and scale_j=dt*mass_i*inv_r3.
            valid_s4 <= valid_s3;
            if (valid_s3) begin
                dx_s4 <= dx_s3;
                dy_s4 <= dy_s3;
                dz_s4 <= dz_s3;
                scale_i_s4 <= scale_q48(dt_s3, mass_j_s3, inv_r3_s3);
                scale_j_s4 <= scale_q48(dt_s3, mass_i_s3, inv_r3_s3);
            end

            // Stage 5: apply opposite signs, round Q64 products to Q16.16, and saturate outputs.
            valid_s5 <= valid_s4;
            if (valid_s4) begin
                dvix <= round_saturate_q16(dvi_x_full);
                dviy <= round_saturate_q16(dvi_y_full);
                dviz <= round_saturate_q16(dvi_z_full);
                dvjx <= round_saturate_q16(dvj_x_full);
                dvjy <= round_saturate_q16(dvj_y_full);
                dvjz <= round_saturate_q16(dvj_z_full);
            end
        end
    end

endmodule