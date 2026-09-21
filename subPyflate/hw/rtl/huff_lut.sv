// -----------------------------------------------------------------------------
// huff_lut.sv
// Canonical Huffman lookup table for the pyflate accelerator.
//
// The table is a synchronous, single-clock BRAM-shaped memory with:
//   * a load port used by the CPU to write one entry per cycle after building
//     the canonical table in software, and
//   * a read port used by the decoder FSM.
//
// Each entry is `{code_bits[4:0], symbol[15:0]}`, matching the pyflate
// software's `(symbol, code_bits)` LUT layout. Entries whose `code_bits == 0`
// mark unused slots (no code of any length maps to that index) — the software
// fallback in the accelerator's driver handles those cases by re-issuing the
// symbol through the pure-Python decoder.
//
// The address width follows MAX_BITS. For MAX_BITS = 15 (fits DEFLATE and
// almost every bzip2 Huffman group we have observed) the depth is 32768 and
// the total storage is ~84 KiB per table — well within a single UltraRAM
// block or a handful of BRAMs on a modern FPGA.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module huff_lut #(
    parameter int MAX_BITS      = 15,
    parameter int SYMBOL_WIDTH  = 16,
    parameter int CODE_BITS_W   = 5   // ceil(log2(MAX_BITS+1))
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Load port (CPU-driven table upload).
    input  logic                          wr_en,
    input  logic [MAX_BITS-1:0]           wr_addr,
    input  logic [SYMBOL_WIDTH-1:0]       wr_symbol,
    input  logic [CODE_BITS_W-1:0]        wr_bits,

    // Read port (decoder-driven lookup).
    input  logic                          rd_en,
    input  logic [MAX_BITS-1:0]           rd_addr,
    output logic [SYMBOL_WIDTH-1:0]       rd_symbol,
    output logic [CODE_BITS_W-1:0]        rd_bits,
    output logic                          rd_valid
);

    localparam int ENTRY_W = SYMBOL_WIDTH + CODE_BITS_W;
    localparam int DEPTH   = 1 << MAX_BITS;

    // BRAM-inferrable storage.
    logic [ENTRY_W-1:0] mem [0:DEPTH-1];

    logic [ENTRY_W-1:0] rd_data_q;
    logic               rd_valid_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_data_q  <= '0;
            rd_valid_q <= 1'b0;
        end else begin
            rd_valid_q <= 1'b0;
            if (wr_en) begin
                mem[wr_addr] <= {wr_bits, wr_symbol};
            end
            if (rd_en) begin
                rd_data_q  <= mem[rd_addr];
                rd_valid_q <= 1'b1;
            end
        end
    end

    assign rd_symbol = rd_data_q[SYMBOL_WIDTH-1:0];
    assign rd_bits   = rd_data_q[ENTRY_W-1:SYMBOL_WIDTH];
    assign rd_valid  = rd_valid_q;

endmodule
