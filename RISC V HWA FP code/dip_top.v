`timescale 1ns / 1ps
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