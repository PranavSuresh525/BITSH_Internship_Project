`timescale 1ns/1ps

module INSTRUCTION_MEMORY(
    input clk,
    input reset,
    input [31:0] pc,
    output [31:0] instruction
);

    reg [31:0] instruction_memory [0:511]; 

    integer i;

    // Word-aligned fetch
    assign instruction = instruction_memory[pc[10:2]];

    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            instruction_memory[i] = 32'h00000000;
        end
        
        // 2. Load the firmware
        $readmemh("firmware.hex", instruction_memory);
    end

endmodule