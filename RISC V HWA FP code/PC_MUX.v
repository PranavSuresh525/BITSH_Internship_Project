`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/12/2024 04:47:53 AM
// Design Name: 
// Module Name: PC_MUX
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PC_MUX(
input [31:0]pc,
input [31:0]branch_address,
input [31:0]jump_address,
input branch,
input jump, 
output reg [31:0]next_pc
    );
    
    always @(*)
    begin
            if(branch)
            next_pc=branch_address;
            else 
            begin
            if(jump)next_pc= jump_address;
            else next_pc=pc+4;
            end
    end

endmodule
