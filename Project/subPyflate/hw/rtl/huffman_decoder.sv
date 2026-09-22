// -----------------------------------------------------------------------------
// huffman_decoder.sv
// Top-level canonical Huffman decoder for the pyflate accelerator.
//
// Composition:
//   * huff_lut     -- precomputed canonical Huffman LUT (indexed by the
//                     next MAX_BITS bits of the stream).
//   * bit_shifter  -- MSB-first rolling bit buffer that mirrors bzip2's
//                     `RBitfield` (see rtl/bit_shifter.sv).
//
// External protocol:
//   * table_wr_*  : one-address-per-cycle upload of the LUT (before decode).
//   * start / max_symbols : begin a decode session that stops after
//                     `max_symbols` output symbols.
//   * byte_*     : streaming input bytes; byte_ready = the shifter can take
//                     a byte this cycle.
//   * symbol_*   : one output pulse per decoded symbol.
//   * done       : one-cycle pulse when the session finishes normally.
//   * error      : latched when the LUT returns bits==0 (unknown code) or
//                     the bit shifter under-runs; the driver falls back to
//                     the software decoder for that symbol.
//
// The decode FSM is deliberately kept simple (throughput ~ 1 symbol per two
// clocks: SNOOP -> LATCH). Deeper pipelining is documented in
// docs/13_hardware_performance.md as a future improvement.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module huffman_decoder #(
    parameter int MAX_BITS      = 15,
    parameter int SYMBOL_WIDTH  = 16,
    parameter int CODE_BITS_W   = 5,
    parameter int BUF_W         = 32,
    parameter int COUNTER_W     = 32
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // LUT load port.
    input  logic                          table_wr_en,
    input  logic [MAX_BITS-1:0]           table_wr_addr,
    input  logic [SYMBOL_WIDTH-1:0]       table_wr_symbol,
    input  logic [CODE_BITS_W-1:0]        table_wr_bits,

    // Control.
    input  logic                          start,
    input  logic [COUNTER_W-1:0]          max_symbols,

    // Streaming input bytes.
    input  logic                          byte_valid,
    input  logic [7:0]                    byte_data,
    output logic                          byte_ready,

    // Streaming output symbols.
    output logic                          symbol_valid,
    output logic [SYMBOL_WIDTH-1:0]       symbol_out,
    output logic [CODE_BITS_W-1:0]        symbol_bits,

    // Session status.
    output logic                          busy,
    output logic                          done,
    output logic                          error
);

    typedef enum logic [1:0] {
        S_IDLE, S_ISSUE, S_WAIT, S_CONSUME
    } state_t;

    state_t state, state_n;

    // ---- Bit shifter ----
    localparam int SHIFT_CONS_W = $clog2(MAX_BITS+1);

    logic                          bs_flush;
    logic                          bs_can_accept;
    logic [MAX_BITS-1:0]           bs_snoop;
    logic                          bs_snoop_ready;
    logic [$clog2(BUF_W+1)-1:0]    bs_bits_avail;
    logic                          bs_need_byte;
    logic                          bs_under_run;
    logic [SHIFT_CONS_W-1:0]       bs_consume;

    bit_shifter #(.MAX_BITS(MAX_BITS), .BUF_W(BUF_W)) u_shift (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (bs_flush),
        .byte_valid     (byte_valid),
        .byte_data      (byte_data),
        .can_accept_byte(bs_can_accept),
        .consume        (bs_consume),
        .snoop          (bs_snoop),
        .snoop_ready    (bs_snoop_ready),
        .bits_avail     (bs_bits_avail),
        .need_byte      (bs_need_byte),
        .under_run      (bs_under_run)
    );

    // ---- LUT ----
    logic                          lut_rd_en;
    logic [MAX_BITS-1:0]           lut_rd_addr;
    logic [SYMBOL_WIDTH-1:0]       lut_rd_symbol;
    logic [CODE_BITS_W-1:0]        lut_rd_bits;
    logic                          lut_rd_valid;

    huff_lut #(
        .MAX_BITS    (MAX_BITS),
        .SYMBOL_WIDTH(SYMBOL_WIDTH),
        .CODE_BITS_W (CODE_BITS_W)
    ) u_lut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (table_wr_en),
        .wr_addr   (table_wr_addr),
        .wr_symbol (table_wr_symbol),
        .wr_bits   (table_wr_bits),
        .rd_en     (lut_rd_en),
        .rd_addr   (lut_rd_addr),
        .rd_symbol (lut_rd_symbol),
        .rd_bits   (lut_rd_bits),
        .rd_valid  (lut_rd_valid)
    );

    logic [COUNTER_W-1:0] symbols_left, symbols_left_q;

    // Byte backpressure: accept a byte whenever the shifter can hold one.
    assign byte_ready = bs_can_accept;

    // Default outputs; per-state overrides below.
    always_comb begin
        state_n       = state;
        lut_rd_en     = 1'b0;
        lut_rd_addr   = bs_snoop;
        bs_consume    = '0;
        bs_flush      = 1'b0;
        symbol_valid  = 1'b0;
        symbol_out    = lut_rd_symbol;
        symbol_bits   = lut_rd_bits;
        busy          = (state != S_IDLE);
        done          = 1'b0;
        error         = 1'b0;
        symbols_left  = symbols_left_q;

        case (state)
            S_IDLE: begin
                if (start) begin
                    symbols_left = max_symbols;
                    bs_flush     = 1'b1;
                    state_n      = S_ISSUE;
                end
            end
            S_ISSUE: begin
                if (bs_snoop_ready) begin
                    lut_rd_en   = 1'b1;
                    lut_rd_addr = bs_snoop;
                    state_n     = S_WAIT;
                end
            end
            S_WAIT: begin
                if (lut_rd_valid) begin
                    if (lut_rd_bits == '0) begin
                        error   = 1'b1;
                        state_n = S_IDLE;
                    end else begin
                        state_n = S_CONSUME;
                    end
                end
            end
            S_CONSUME: begin
                bs_consume   = lut_rd_bits[SHIFT_CONS_W-1:0];
                symbol_valid = 1'b1;
                symbols_left = symbols_left_q - {{(COUNTER_W-1){1'b0}}, 1'b1};
                if (symbols_left_q == {{(COUNTER_W-1){1'b0}}, 1'b1}) begin
                    done    = 1'b1;
                    state_n = S_IDLE;
                end else begin
                    state_n = S_ISSUE;
                end
            end
            default: state_n = S_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            symbols_left_q <= '0;
        end else begin
            state          <= state_n;
            symbols_left_q <= symbols_left;
        end
    end

endmodule
