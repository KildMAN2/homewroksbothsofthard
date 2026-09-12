`timescale 1ns/1ps

module tb_nbody_accel;
    localparam integer MAX_TRANSACTIONS = 64;
    localparam integer EXPECTED_LATENCY = 5;

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

    logic signed [31:0] expected_dvix [0:MAX_TRANSACTIONS-1];
    logic signed [31:0] expected_dviy [0:MAX_TRANSACTIONS-1];
    logic signed [31:0] expected_dviz [0:MAX_TRANSACTIONS-1];
    logic signed [31:0] expected_dvjx [0:MAX_TRANSACTIONS-1];
    logic signed [31:0] expected_dvjy [0:MAX_TRANSACTIONS-1];
    logic signed [31:0] expected_dvjz [0:MAX_TRANSACTIONS-1];
    integer expected_tolerance [0:MAX_TRANSACTIONS-1];
    integer expected_accept_cycle [0:MAX_TRANSACTIONS-1];
    integer expected_group [0:MAX_TRANSACTIONS-1];
    logic expected_latency_check [0:MAX_TRANSACTIONS-1];

    integer cycle_count = 0;
    integer queue_head = 0;
    integer queue_tail = 0;
    integer errors = 0;
    integer transfers_checked = 0;
    integer last_transfer_cycle = -1;
    integer last_transfer_group = -1;

    logic signed [31:0] held_dvix;
    logic signed [31:0] held_dviy;
    logic signed [31:0] held_dviz;
    logic signed [31:0] held_dvjx;
    logic signed [31:0] held_dvjy;
    logic signed [31:0] held_dvjz;

    nbody_accel_v2 dut (.*);

    always #5 clk = ~clk;

    function automatic logic [32:0] absolute_difference(
        input logic signed [31:0] actual,
        input logic signed [31:0] expected
    );
        logic signed [32:0] difference;
        begin
            difference = {actual[31], actual} - {expected[31], expected};
            if (difference < 0) begin
                absolute_difference = -difference;
            end else begin
                absolute_difference = difference;
            end
        end
    endfunction

    function automatic logic signed [31:0] real_to_q16(input real value);
        real scaled;
        integer rounded;
        begin
            scaled = value * 65536.0;
            if (scaled >= 2147483647.0) begin
                real_to_q16 = 32'sh7fff_ffff;
            end else if (scaled <= -2147483648.0) begin
                real_to_q16 = 32'sh8000_0000;
            end else begin
                if (scaled >= 0.0) begin
                    rounded = $rtoi(scaled + 0.5);
                end else begin
                    rounded = $rtoi(scaled - 0.5);
                end
                real_to_q16 = rounded;
            end
        end
    endfunction

    task automatic record_expected(
        input logic signed [31:0] request_dx,
        input logic signed [31:0] request_dy,
        input logic signed [31:0] request_dz,
        input logic        [31:0] request_mass_i,
        input logic        [31:0] request_mass_j,
        input logic        [31:0] request_dt,
        input integer tolerance,
        input integer group_id,
        input logic check_latency
    );
        real real_dx;
        real real_dy;
        real real_dz;
        real real_mass_i;
        real real_mass_j;
        real real_dt;
        real distance_squared;
        real inverse_r3;
        real scale_i;
        real scale_j;
        begin
            if (queue_tail >= MAX_TRANSACTIONS) begin
                $display("FAIL: scoreboard capacity exceeded");
                errors = errors + 1;
            end else begin
                real_dx = $itor(request_dx) / 65536.0;
                real_dy = $itor(request_dy) / 65536.0;
                real_dz = $itor(request_dz) / 65536.0;
                real_mass_i = $itor(request_mass_i) / 65536.0;
                real_mass_j = $itor(request_mass_j) / 65536.0;
                real_dt = $itor(request_dt) / 65536.0;
                distance_squared = real_dx*real_dx + real_dy*real_dy + real_dz*real_dz;

                if (distance_squared == 0.0) begin
                    inverse_r3 = 0.0;
                end else begin
                    inverse_r3 = 1.0 / (distance_squared * $sqrt(distance_squared));
                end
                scale_i = real_dt * real_mass_j * inverse_r3;
                scale_j = real_dt * real_mass_i * inverse_r3;

                expected_dvix[queue_tail] = real_to_q16(-real_dx * scale_i);
                expected_dviy[queue_tail] = real_to_q16(-real_dy * scale_i);
                expected_dviz[queue_tail] = real_to_q16(-real_dz * scale_i);
                expected_dvjx[queue_tail] = real_to_q16( real_dx * scale_j);
                expected_dvjy[queue_tail] = real_to_q16( real_dy * scale_j);
                expected_dvjz[queue_tail] = real_to_q16( real_dz * scale_j);
                expected_tolerance[queue_tail] = tolerance;
                expected_accept_cycle[queue_tail] = cycle_count + 1;
                expected_group[queue_tail] = group_id;
                expected_latency_check[queue_tail] = check_latency;
                queue_tail = queue_tail + 1;
            end
        end
    endtask

    task automatic drive_request(
        input logic signed [31:0] request_dx,
        input logic signed [31:0] request_dy,
        input logic signed [31:0] request_dz,
        input logic        [31:0] request_mass_i,
        input logic        [31:0] request_mass_j,
        input logic        [31:0] request_dt,
        input integer tolerance,
        input integer group_id,
        input logic check_latency
    );
        begin
            @(negedge clk);
            while (!in_ready) @(negedge clk);
            in_valid = 1'b1;
            dx = request_dx;
            dy = request_dy;
            dz = request_dz;
            mass_i = request_mass_i;
            mass_j = request_mass_j;
            dt = request_dt;
            record_expected(request_dx, request_dy, request_dz, request_mass_i,
                            request_mass_j, request_dt, tolerance, group_id, check_latency);
        end
    endtask

    task automatic stop_input;
        begin
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    task automatic insert_gap(input integer cycles);
        integer gap_cycle;
        begin
            @(negedge clk);
            in_valid = 1'b0;
            for (gap_cycle = 0; gap_cycle < cycles; gap_cycle = gap_cycle + 1) begin
                @(negedge clk);
            end
        end
    endtask

    task automatic wait_for_drain;
        integer timeout;
        begin
            timeout = 0;
            while ((queue_head != queue_tail || out_valid) && timeout < 100) begin
                @(negedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout == 100) begin
                $display("FAIL: timeout waiting for pipeline to drain");
                errors = errors + 1;
            end
        end
    endtask

    task automatic compare_component(
        input string name,
        input logic signed [31:0] actual,
        input logic signed [31:0] expected,
        input integer tolerance
    );
        begin
            if (absolute_difference(actual, expected) > tolerance) begin
                $display("FAIL: transaction %0d %s actual=%0d expected=%0d tolerance=%0d",
                         queue_head, name, actual, expected, tolerance);
                errors = errors + 1;
            end
        end
    endtask

    // Scoreboard checks the payload at the rising edge where a transfer can occur.
    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (rst_n && out_valid) begin
            if (queue_head >= queue_tail) begin
                $display("FAIL: unexpected output with an empty scoreboard");
                errors = errors + 1;
            end else begin
                compare_component("dvix", dvix, expected_dvix[queue_head], expected_tolerance[queue_head]);
                compare_component("dviy", dviy, expected_dviy[queue_head], expected_tolerance[queue_head]);
                compare_component("dviz", dviz, expected_dviz[queue_head], expected_tolerance[queue_head]);
                compare_component("dvjx", dvjx, expected_dvjx[queue_head], expected_tolerance[queue_head]);
                compare_component("dvjy", dvjy, expected_dvjy[queue_head], expected_tolerance[queue_head]);
                compare_component("dvjz", dvjz, expected_dvjz[queue_head], expected_tolerance[queue_head]);

                if (expected_latency_check[queue_head] &&
                    cycle_count - expected_accept_cycle[queue_head] != EXPECTED_LATENCY) begin
                    $display("FAIL: latency=%0d expected=%0d",
                             cycle_count - expected_accept_cycle[queue_head], EXPECTED_LATENCY);
                    errors = errors + 1;
                end

                if (out_ready) begin
                    if (expected_group[queue_head] >= 0 &&
                        expected_group[queue_head] == last_transfer_group &&
                        cycle_count - last_transfer_cycle != 1) begin
                        $display("FAIL: throughput gap=%0d cycles in consecutive group %0d",
                                 cycle_count - last_transfer_cycle, expected_group[queue_head]);
                        errors = errors + 1;
                    end
                    last_transfer_cycle = cycle_count;
                    last_transfer_group = expected_group[queue_head];
                    queue_head = queue_head + 1;
                    transfers_checked = transfers_checked + 1;
                end
            end
        end
    end

    initial begin
        // Reset must clear valid and all externally visible data.
        repeat (3) @(posedge clk);
        #1;
        if (out_valid !== 1'b0 || dvix !== 0 || dviy !== 0 || dviz !== 0 ||
            dvjx !== 0 || dvjy !== 0 || dvjz !== 0) begin
            $display("FAIL: reset did not clear output state");
            errors = errors + 1;
        end
        rst_n = 1'b1;
        @(negedge clk);
        if (!in_ready) begin
            $display("FAIL: in_ready was not asserted after reset");
            errors = errors + 1;
        end

        // Single exact request also establishes the unstalled pipeline latency.
        drive_request(32'sd65536, 0, 0, 32'd131072, 32'd196608, 32'd32768, 0, -1, 1'b1);
        stop_input();
        wait_for_drain();

        // Input gaps and a non-axis-aligned distance exercise numerical tolerance.
        insert_gap(2);
        drive_request(32'sd98304, -32'sd147456, 32'sd49152,
                      32'd262144, 32'd163840, 32'd8192, 16, -1, 1'b0);
        stop_input();
        wait_for_drain();

        // Four consecutive requests test throughput, signs, masses, and distances.
        drive_request(-32'sd131072, 0, 0, 32'd262144, 32'd131072, 32'd65536, 0, 1, 1'b0);
        drive_request(0, 32'sd196608, 32'sd262144,
                      32'd65536, 32'd163840, 32'd16384, 3, 1, 1'b0);
        drive_request(-32'sd196608, -32'sd262144, 0,
                      32'd196608, 32'd327680, 32'd32768, 3, 1, 1'b0);
        drive_request(32'sd32768, 32'sd65536, -32'sd131072,
                      32'd98304, 32'd229376, 32'd12288, 16, 1, 1'b0);
        stop_input();
        wait_for_drain();

        // Queue three requests with the consumer blocked before any output appears.
        out_ready = 1'b0;
        drive_request(32'sd65536, 0, 0, 32'd65536, 32'd131072, 32'd32768, 0, 2, 1'b0);
        drive_request(0, -32'sd65536, 0, 32'd196608, 32'd65536, 32'd16384, 0, 2, 1'b0);
        drive_request(0, 0, 32'sd131072, 32'd131072, 32'd262144, 32'd32768, 0, 2, 1'b0);
        stop_input();
        wait (out_valid);
        #1;
        held_dvix = dvix;
        held_dviy = dviy;
        held_dviz = dviz;
        held_dvjx = dvjx;
        held_dvjy = dvjy;
        held_dvjz = dvjz;
        repeat (3) begin
            @(negedge clk);
            if (!out_valid || in_ready || dvix !== held_dvix || dviy !== held_dviy ||
                dviz !== held_dviz || dvjx !== held_dvjx || dvjy !== held_dvjy ||
                dvjz !== held_dvjz) begin
                $display("FAIL: output changed or input remained ready during backpressure");
                errors = errors + 1;
            end
        end
        out_ready = 1'b1;
        wait_for_drain();

        // Zero distance follows the documented finite policy and returns zero updates.
        drive_request(0, 0, 0, 32'd65536, 32'd131072, 32'd65536, 0, -1, 1'b0);
        stop_input();

        // Large scale values exercise positive and negative output saturation.
        drive_request(32'sd65536, 0, 0,
                      32'h7fff0000, 32'h7fff0000, 32'h7fff0000, 0, -1, 1'b0);
        drive_request(-32'sd65536, 0, 0,
                      32'h7fff0000, 32'h7fff0000, 32'h7fff0000, 0, -1, 1'b0);
        stop_input();
        wait_for_drain();

        if (transfers_checked != 12) begin
            $display("FAIL: checked %0d transfers, expected 12", transfers_checked);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("NBODY_ACCEL_TEST=PASS transfers=%0d latency=%0d throughput=1/cycle",
                     transfers_checked, EXPECTED_LATENCY);
            $finish;
        end else begin
            $display("NBODY_ACCEL_TEST=FAIL errors=%0d", errors);
            $fatal(1, "Self-checking testbench failed");
        end
    end
endmodule