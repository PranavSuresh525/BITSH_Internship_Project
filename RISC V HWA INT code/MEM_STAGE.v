`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2024 10:32:58 PM
// Design Name: 
// Module Name: MEM_STAGE
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


module MEM_STAGE(
input clk,
input reset,

input [31:0]address,
input [1:0]mem_control,

input [31:0]write_data,

output [31:0]read_data
    );
    
    (*ram_style = "block" *) reg [7:0]mem[1023:0];
    
    assign read_data= mem_control[1]?{mem[address+3],mem[address+2],mem[address+1],mem[address]}:0;
    
    always @(posedge clk)
    begin
        if(reset)
        begin
            mem[4]<=1;
            mem[5]<=0;
            mem[6]<=0;
            mem[7]<=0;
        end
        
        else
        begin
            if(mem_control[0]==1)
                {mem[address+3],mem[address+2],mem[address+1],mem[address]}=write_data;
        end
        
    end
endmodule
