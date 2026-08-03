`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 11:05:02 PM
// Design Name: 
// Module Name: STALLING UNIT
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


module STALLING_UNIT(

input [6:0]if_id_opcode,

input [4:0]id_ex_rd,
input id_ex_mem_read,

input [4:0]if_id_rs1,
input [4:0]if_id_rs2,
input hwa_stall_request,

output stall
    );
    
    reg c1,c2,c3;
    
    always @(*)
    
    begin
    
    c1=(!((if_id_opcode==7'b1101111)|(if_id_opcode==7'b0110111)))&(id_ex_rd==if_id_rs1);
    
    c2=(((if_id_opcode==7'b0110011)|(if_id_opcode==7'b0100011)|(if_id_opcode==7'b1100011))&(id_ex_rd==if_id_rs2));
    
    c3=(id_ex_rd!=0);
    end
    
assign stall=(id_ex_mem_read && (c1 | c2)&&c3)|hwa_stall_request;
    
    
    
endmodule
