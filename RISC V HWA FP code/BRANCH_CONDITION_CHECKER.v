`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 07:05:36 PM
// Design Name: 
// Module Name: BRANCH_CONDITION_CHECKER
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


module BRANCH_CONDITION_CHECKER(
input [31:0]input1,
input [31:0]input2,
input [2:0] funct_3,

output reg branch_cond
    );
    
    always @(*)
    begin
        case(funct_3)
            0:branch_cond=(input1 == input2);
            1:branch_cond=(input1 != input2);
            4:branch_cond=($signed(input1)<$signed(input2));
            5:branch_cond=($signed(input1)>=$signed(input2));
            6:branch_cond=(input1<input2);
            7:branch_cond=(input1>=input2);
            default:branch_cond=0;
        endcase
    end
    
endmodule
