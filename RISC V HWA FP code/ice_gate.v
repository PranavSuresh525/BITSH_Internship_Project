// ice_gate.v — maps to BUFGCE or hard ICG on Xilinx 7-series / UltraScale
module ice_gate (
    input  wire clk_in,
    input  wire en,        // active high enable
    output wire clk_out
);
    // Latch-based ICG — prevents glitches on the gated clock
    // Xilinx will absorb this into BUFGCE automatically
    reg en_lat;
    always @(*) begin
        if (!clk_in) en_lat = en;   // latch on low phase
    end
    assign clk_out = clk_in & en_lat;
endmodule