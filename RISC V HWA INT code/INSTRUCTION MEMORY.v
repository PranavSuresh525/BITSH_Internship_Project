`timescale 1ns/1ps

module INSTRUCTION_MEMORY(
    input clk, 
    input reset,
    input [31:0] pc,
    output [31:0] instruction
);
    reg [31:0] instruction_memory [0:511];
    initial begin
        $readmemh("firmware.hex", instruction_memory);
    end
    assign instruction = instruction_memory[pc[31:2]]; 

endmodule