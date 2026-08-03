`timescale 1ns/1ps

// Generic shift-register FIFO used by ws_array for input/output deskewing.
// DEPTH == 0 is a legal pass-through (zero latency).
module fifo #(
    parameter DEPTH = 1,
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             en,
    input  wire [WIDTH-1:0] data_in,
    output wire [WIDTH-1:0] data_out
);

    generate
        if (DEPTH == 0) begin : passthrough
            assign data_out = data_in;
        end else begin : shift_reg
            reg [WIDTH-1:0] sr [0:DEPTH-1];
            integer i;

            always @(posedge clk or posedge rst) begin
                if (rst) begin
                    for (i = 0; i < DEPTH; i = i + 1)
                        sr[i] <= {WIDTH{1'b0}};
                end else if (en) begin
                    sr[0] <= data_in;
                    for (i = 1; i < DEPTH; i = i + 1)
                        sr[i] <= sr[i-1];
                end
            end

            assign data_out = sr[DEPTH-1];
        end
    endgenerate

endmodule