`timescale 1ns / 1ps

module tb_alu_fp;
    reg [31:0] a, b;
    reg [4:0]  control;
    wire [31:0] c;

    // Instantiate your PURELY COMBINATIONAL ALU
    ALU uut (
        .a(a), 
        .b(b),
        .control(control),
        .c(c)
    );

    task test_fp;
        input [4:0]  ctrl_in;
        input [31:0] a_in;
        input [31:0] b_in;
        input [31:0] expected_out;
        input [8*10:1] op_name;
        begin
            control = ctrl_in;
            a = a_in;
            b = b_in;
            
            #10; // Wait a few nanoseconds for combinational logic to settle
            
            if (c == expected_out)
                $display("[PASS] %s: %h op %h = %h", op_name, a_in, b_in, c);
            else
                $display("[FAIL] %s: %h op %h = %h (Expected: %h)", op_name, a_in, b_in, c, expected_out);
        end
    endtask

    initial begin
        a = 0; b = 0; control = 0;
        
        #10;
        $display("========================================");
        $display("   STARTING FP32 ALU VERIFICATION       ");
        $display("========================================");

        // FADD.S (11): 2.5 + 1.25 = 3.75
        test_fp(5'd11, 32'h40200000, 32'h3FA00000, 32'h40700000, "FADD.S");

        // FSUB.S (12): 2.5 - 1.25 = 1.25
        test_fp(5'd12, 32'h40200000, 32'h3FA00000, 32'h3FA00000, "FSUB.S");

        // FMUL.S (13): 2.0 * 3.0 = 6.0
        test_fp(5'd13, 32'h40000000, 32'h40400000, 32'h40C00000, "FMUL.S");

        $finish;
    end
endmodule