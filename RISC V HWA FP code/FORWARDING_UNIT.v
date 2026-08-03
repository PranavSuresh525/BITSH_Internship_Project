`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 11:05:17 PM
// Design Name: 
// Module Name: FORWARDING_UNIT
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


module FORWARDING_UNIT(
input ex_mem_reg_write,
input mem_wb_reg_write,

input [4:0]ex_mem_rd,
input [4:0]mem_wb_rd,

input [4:0]id_ex_rs1,
input [4:0]id_ex_rs2,

input [6:0]id_ex_opcode,//to specifically check that the instruction is not I type

output reg [1:0]forward_m1,
output reg [1:0]forward_m2
    );
    
    initial forward_m1=0;
    initial forward_m2=0;
    
    always @(*)
    begin
    if(!((id_ex_opcode==7'b1101111)|(id_ex_opcode==7'b010111)))
    begin
    
            if((ex_mem_reg_write)&(id_ex_rs1==ex_mem_rd) & (ex_mem_rd!=0))
            begin
               forward_m1=2'b01;
            end
            
            else if((mem_wb_reg_write)&(id_ex_rs1==mem_wb_rd) & (mem_wb_rd!=0) ) 
            begin
               forward_m1=2'b10;
            end
            
            else forward_m1=2'b00;
    end
else forward_m1=2'b00;
end
    
    always @(*)
    begin
    if((id_ex_opcode==7'b0110011)|(id_ex_opcode==7'b0100011)|(id_ex_opcode==7'b1100011)|(id_ex_opcode==7'b1010011)|(id_ex_opcode==7'b1000011))
    begin
            if((ex_mem_reg_write)&(id_ex_rs2==ex_mem_rd) & (ex_mem_rd!=0) )
            begin
                forward_m2=2'b01;
            end 
            
            else if((mem_wb_reg_write)&(id_ex_rs2==mem_wb_rd) & (mem_wb_rd!=0) ) 
            begin
                forward_m2=2'b10;
            end
            
            else forward_m2=2'b00;
    end
    
    else    forward_m2=2'b00;
  
    end

    
endmodule