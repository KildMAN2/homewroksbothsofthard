// -----------------------------------------------------------------------------
// bit_shifter.sv
// Rolling MSB-first bit buffer for the pyflate accelerator.
//
// This module mirrors the software `RBitfield` used by bzip2:
//   * bytes arrive one at a time and are shifted into the LOW 8 bits, while
//     the previous buffer contents shift UP by 8 (matches `_more()`),
//   * `snoop` exposes the top MAX_BITS bits — the bits that will be consumed
//     next — matching `snoopbits(MAX_BITS)`,
//   * `consume` advances the read pointer by 0..MAX_BITS bits, matching
//     `readbits(consume)`.
//
// The buffer is BUF_W bits wide. BUF_W >= MAX_BITS + 8 guarantees that a
// full-width snoop plus one refill byte always fit.
//
// The module raises `snoop_ready` only when bits_avail >= MAX_BITS. The
// driver / top FSM must wait for `snoop_ready` before latching the LUT
// address, and must issue `byte_valid` refills whenever `need_byte` is high.
//
// Consume happens in the SAME cycle that the caller acts on `snoop`: on the
// next rising edge the buffer forgets the top `consume` bits and, if
// `byte_valid` is high, appends the new byte in the low 8 bits.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module bit_shifter #(
    parameter int MAX_BITS = 15,
    parameter int BUF_W    = 32   // must be >= MAX_BITS + 8
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Clear buffer (between decode sessions).
    input  logic                          flush,

    // Byte upload from CPU/DMA.
    input  logic                          byte_valid,
    input  logic [7:0]                    byte_data,
    output logic                          can_accept_byte,

    // Consume up to MAX_BITS bits per cycle.
    input  logic [$clog2(MAX_BITS+1)-1:0] consume,

    // Output view.
    output logic [MAX_BITS-1:0]           snoop,
    output logic                          snoop_ready,
    output logic [$clog2(BUF_W+1)-1:0]    bits_avail,
    output logic                          need_byte,
    output logic                          under_run   // consume > bits_avail
);

    localparam logic [BUF_W-1:0] ONE = { {(BUF_W-1){1'b0}}, 1'b1 };

    logic [BUF_W-1:0]                     buffer;
    logic [$clog2(BUF_W+1)-1:0]           bits_q;

    logic [$clog2(BUF_W+1)-1:0]           bits_after_consume;
    logic [BUF_W-1:0]                     buf_after_consume;

    assign can_accept_byte = (bits_q + 8) <= BUF_W;
    assign need_byte       = (bits_q < MAX_BITS);
    assign snoop_ready     = (bits_q >= MAX_BITS);
    assign under_run       = (consume > bits_q);
    assign bits_avail      = bits_q;

    // Top MAX_BITS bits (bits_q-1 downto bits_q-MAX_BITS). Only meaningful
    // when snoop_ready is high.
    always_comb begin
        if (bits_q >= MAX_BITS) begin
            snoop = buffer[bits_q-1 -: MAX_BITS];
        end else begin
            snoop = '0;
        end
    end

    // Compute the bit-count and buffer contents after the requested consume.
    // The buffer's top `consume` valid bits are dropped by masking to the
    // lower (bits_q - consume) bits: `mask = (1 << bits_after_consume) - 1`.
    always_comb begin
        if (consume != 0 && !under_run) begin
            bits_after_consume = bits_q - consume;
            buf_after_consume  = buffer & ((ONE << bits_after_consume) - ONE);
        end else begin
            bits_after_consume = bits_q;
            buf_after_consume  = buffer;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buffer <= '0;
            bits_q <= '0;
        end else if (flush) begin
            buffer <= '0;
            bits_q <= '0;
        end else begin
            // Optionally append a new byte to the low 8 bits after shifting
            // the current buffer up by 8, exactly like RBitfield._more().
            if (byte_valid && (bits_after_consume + 8) <= BUF_W) begin
                buffer <= (buf_after_consume << 8) | { {(BUF_W-8){1'b0}}, byte_data };
                bits_q <= bits_after_consume + 8;
            end else begin
                buffer <= buf_after_consume;
                bits_q <= bits_after_consume;
            end
        end
    end

endmodule
