`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// dip_top #(N)
//
// Self-contained NxN BF16 DiP matrix-multiply accelerator, now built on
// real BRAM banks (bf16_bram_bank) instead of a flat register file that's
// read out all-at-once -- the old approach (a single N*N-wide
// combinational bus) cannot map to actual block RAM, which has only 1-2
// ports; this one can.
//
// Storage: N weight banks + N activation banks + N output banks, each
// N-deep. Bank c holds COLUMN c of its matrix (one element per row), so
// reading/writing one address across all N banks in parallel gives a
// whole matrix ROW per cycle -- exactly what dip_fsm/dip_array need, and
// exactly how a real synthesizable design would have to be organized.
//
// Software/driver contract (unchanged from before):
//   1) Write the RAW (unpermuted) weight matrix into the weight banks via
//      weight_wr_en/weight_wr_addr/weight_wr_data (linear address,
//      addr = row*N + col -- decoded into bank=col, row internally). The
//      FSM permutes it on the fly while streaming it into the array.
//   2) Write the raw (unpermuted) activation matrix the same way via
//      input_wr_en/input_wr_addr/input_wr_data.
//   3) Pulse `start` for one cycle.
//   4) Wait for `done` (pulses high for one cycle).
//   5) Read the NxN result out one element at a time via
//      output_rd_addr/output_rd_data (linear address, 1-cycle latency --
//      present an address, the data is valid the cycle after).
//////////////////////////////////////////////////////////////////////////////
module dip_top #(
    parameter N = 16
) (
    input  clk,
    input  rst,

    // ---- weight matrix load (RAW, unpermuted -- FSM permutes it) ----
    input                          weight_wr_en,
    input  [$clog2(N*N)-1:0]       weight_wr_addr,   // row*N + col
    input  [15:0]                  weight_wr_data,

    // ---- activation matrix load (raw, unpermuted) ----
    input                          input_wr_en,
    input  [$clog2(N*N)-1:0]       input_wr_addr,    // row*N + col
    input  [15:0]                  input_wr_data,

    input                          start,
    output                         busy,
    output                         done,

    // ---- result read-out: present an address, data valid 1 cycle later ----
    input  [$clog2(N*N)-1:0]       output_rd_addr,
    output [15:0]                  output_rd_data
);

    localparam ADDR_W = $clog2(N);
    wire array_out_valid;

    genvar c;

    //--------------------------------------------------------------
    // weight banks: write side decodes the linear external address
    // into (bank=col, row); read side driven by dip_fsm (permuted,
    // per-bank address).
    //--------------------------------------------------------------
    wire [ADDR_W-1:0] w_bank_sel = weight_wr_addr % N;       
    wire [ADDR_W-1:0] w_row      = weight_wr_addr / N;

    wire [N*ADDR_W-1:0] weight_rd_addr_flat;
    wire [N*16-1:0]     weight_rd_data_flat;

    generate
        for (c = 0; c < N; c = c + 1) begin : WBANKS
            bf16_bram_bank #(.DEPTH(N)) u_wbank (
                .clk(clk),
                .we(weight_wr_en && (w_bank_sel == c)),
                .wr_addr(w_row),
                .din(weight_wr_data),
                .rd_addr(weight_rd_addr_flat[c*ADDR_W +: ADDR_W]),
                .dout(weight_rd_data_flat[c*16 +: 16])
            );
        end
    endgenerate

    //--------------------------------------------------------------
    // activation banks: write side same pattern; read side driven by
    // dip_fsm (same address across all banks -- no permutation here).
    //--------------------------------------------------------------
    wire [ADDR_W-1:0] i_bank_sel = input_wr_addr % N;
    wire [ADDR_W-1:0] i_row      = input_wr_addr / N;

    wire [ADDR_W-1:0] input_rd_addr;
    wire [N*16-1:0]   input_rd_data_flat;

    generate
        for (c = 0; c < N; c = c + 1) begin : IBANKS
            bf16_bram_bank #(.DEPTH(N)) u_ibank (
                .clk(clk),
                .we(input_wr_en && (i_bank_sel == c)),
                .wr_addr(i_row),
                .din(input_wr_data),
                .rd_addr(input_rd_addr),
                .dout(input_rd_data_flat[c*16 +: 16])
            );
        end
    endgenerate

    //--------------------------------------------------------------
    // output banks: write side driven by dip_fsm (captures dip_array's
    // result, one bank per column, same row address across all banks);
    // read side decodes the external linear address into (bank, row),
    // muxing the selected bank's dout out 1 cycle later.
    //--------------------------------------------------------------
    wire                output_we;
    wire [ADDR_W-1:0]   output_wr_addr;
    wire [N*16-1:0]     output_wr_data_flat;

    wire [ADDR_W-1:0] o_bank_sel = output_rd_addr % N;
    wire [ADDR_W-1:0] o_row      = output_rd_addr / N;
    reg  [ADDR_W-1:0] o_bank_sel_d1;
    always @(posedge clk) o_bank_sel_d1 <= o_bank_sel;

    wire [15:0] output_bank_dout [0:N-1];
    generate
        for (c = 0; c < N; c = c + 1) begin : OBANKS
            bf16_bram_bank #(.DEPTH(N)) u_obank (
                .clk(clk),
                .we(output_we),
                .wr_addr(output_wr_addr),
                .din(output_wr_data_flat[c*16 +: 16]),
                .rd_addr(o_row),
                .dout(output_bank_dout[c])
            );
        end
    endgenerate

    assign output_rd_data = output_bank_dout[o_bank_sel_d1];

    //--------------------------------------------------------------
    // controller + array
    //--------------------------------------------------------------
    wire                load_en;
    wire [ADDR_W-1:0]   load_row_idx;
    wire [N*16-1:0]     weight_bus_flat;
    wire                row0_valid;
    wire [N*16-1:0]     row0_act_bus_flat;
    wire [N*16-1:0]     result_flat;

    dip_fsm #(.N(N)) u_fsm (
        .clk(clk), .rst(rst), .start(start),
        .weight_rd_addr_flat(weight_rd_addr_flat), .weight_rd_data_flat(weight_rd_data_flat),
        .input_rd_addr(input_rd_addr), .input_rd_data_flat(input_rd_data_flat),
        .output_we(output_we), .output_wr_addr(output_wr_addr), .output_wr_data_flat(output_wr_data_flat),
        .load_en(load_en), .load_row_idx(load_row_idx), .weight_bus_flat(weight_bus_flat),
        .row0_valid(row0_valid), .row0_act_bus_flat(row0_act_bus_flat),
        .result_flat(result_flat),
        .array_out_valid(array_out_valid),
        .busy(busy), .done(done)
    );


    dip_array #(.N(N)) u_array (
        .clk(clk), .rst(rst),
        .array_en(busy), 
        .load_en(load_en), .load_row_idx(load_row_idx), .weight_bus_flat(weight_bus_flat),
        .row0_valid(row0_valid), .row0_act_bus_flat(row0_act_bus_flat),
        .result_flat(result_flat),
        .array_out_valid(array_out_valid)
    );

endmodule