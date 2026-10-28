`timescale 1ns / 1ps

module DATA_MEMORY_tb;

    // Inputs
    reg clk;
    
    // Arbiter Control
    reg hwa_active;
    
    // CPU Ports
    reg [31:0] cpu_address;
    reg [31:0] cpu_write_data;
    reg        cpu_mem_read;
    reg        cpu_mem_write;
    
    // HWA Ports
    reg [31:0] hwa_address;
    reg [31:0] hwa_write_data;
    reg        hwa_mem_read;
    reg        hwa_mem_write;

    // Outputs
    wire [31:0] read_data;

    // Instantiate the Unit Under Test (UUT)
    DATA_MEMORY uut (
        .clk(clk),
        .hwa_active(hwa_active),
        
        .cpu_address(cpu_address),
        .cpu_write_data(cpu_write_data),
        .cpu_mem_read(cpu_mem_read),
        .cpu_mem_write(cpu_mem_write),
        
        .hwa_address(hwa_address),
        .hwa_write_data(hwa_write_data),
        .hwa_mem_read(hwa_mem_read),
        .hwa_mem_write(hwa_mem_write),
        
        .read_data(read_data)
    );

    // 100 MHz Clock Generation
    always #5 clk = ~clk;

    initial begin
        // Initialize all Inputs
        clk = 0;
        hwa_active = 0;
        
        cpu_address = 0;
        cpu_write_data = 0;
        cpu_mem_read = 0;
        cpu_mem_write = 0;
        
        hwa_address = 0;
        hwa_write_data = 0;
        hwa_mem_read = 0;
        hwa_mem_write = 0;

        // Wait 100 ns for global reset to finish
        #100;
        
        $display("==================================================");
        $display(" Starting 1MB Dual-Port Memory Arbiter Testbench ");
        $display("==================================================");

        // -----------------------------------------------------------
        // PHASE 1: Normal CPU Operations (hwa_active = 0)
        // -----------------------------------------------------------
        $display("\n[PHASE 1] Testing CPU Memory Access...");
        
        // CPU Writes data to address 0x0000_0004
        @(posedge clk);
        cpu_address = 32'd4;
        cpu_write_data = 32'hDEADBEEF;
        cpu_mem_write = 1;
        
        @(posedge clk);
        cpu_mem_write = 0; // Deassert write
        
        // CPU Reads from address 0x0000_0004
        @(posedge clk);
        cpu_address = 32'd4;
        cpu_mem_read = 1;
        
        // Wait combinational delay, then check
        #1; 
        if (read_data == 32'hDEADBEEF) $display("  -> CPU Write/Read SUCCESS: %h", read_data);
        else $display("  -> CPU Write/Read FAILED! Got: %h", read_data);
        cpu_mem_read = 0;

       // -----------------------------------------------------------
        // PHASE 2: Hardware Accelerator Operations (hwa_active = 1)
        // -----------------------------------------------------------
        $display("\n[PHASE 2] Testing Accelerator Memory Access...");
        hwa_active = 1; // HWA TAKES CONTROL!
        
        // HWA Writes data to deep memory (Testing 1MB boundary limit)
        // 1MB = 1048576 bytes. Highest 32-bit aligned address is 1048572
        @(posedge clk);
        hwa_address = 32'd1048572;   // Last valid 32-bit aligned byte address in 1MB
        hwa_write_data = 32'hCAFEBA00;
        hwa_mem_write = 1
        
        @(posedge clk);
        hwa_mem_write = 0;
        
        // HWA Reads from deep memory
        @(posedge clk);
        hwa_address = 32'd1048572;   // Read from the same address ✅
        hwa_mem_read = 1;
        
        #1;
        if (read_data == 32'hCAFEBA00) $display("  -> HWA Write/Read SUCCESS (1MB Boundary verified): %h", read_data);
        else $display("  -> HWA Write/Read FAILED! Got: %h", read_data);
        hwa_mem_read = 0;
        // -----------------------------------------------------------
        // PHASE 3: The Arbiter Clash (Proving CPU gets locked out)
        // -----------------------------------------------------------
        $display("\n[PHASE 3] Testing Arbiter Lockout (CPU vs HWA Clash)...");
        
        // Ensure HWA is still active
        hwa_active = 1; 
        
        // Both try to write at the EXACT same time to different addresses
        @(posedge clk) #1; // Small delay to ensure we are in the same cycle
        cpu_address = 32'd100;
        cpu_write_data = 32'h11111111; // CPU tries to write 1's
        cpu_mem_write = 1;
        
        hwa_address = 32'd200;
        hwa_write_data = 32'h22222222; // HWA tries to write 2's
        hwa_mem_write = 1;
        
        @(posedge clk) #1; // Wait for the cycle to complete
        cpu_mem_write = 0;
        hwa_mem_write = 0;
        
        // Now, drop HWA active so CPU can look around
        hwa_active = 0; 
        
        // CPU checks address 100 (Its own write should have been ignored!)
        @(posedge clk) #1;
        cpu_address = 32'd100;
        cpu_mem_read = 1;
        #1;
        if (read_data == 32'h00000000) $display("  -> Arbiter SUCCESS: CPU write was correctly BLOCKED.");
        else $display("  -> Arbiter FAILED: CPU managed to write while HWA was active! Got: %h", read_data);
        
        // CPU checks address 200 (HWA's write should be there!)
        @(posedge clk) #1;
        cpu_address = 32'd200;
        #1;
        if (read_data == 32'h22222222) $display("  -> Arbiter SUCCESS: HWA write was correctly ALLOWED.");
        else $display("  -> Arbiter FAILED: HWA write did not go through! Got: %h", read_data);
        cpu_mem_read = 0;

        $display("\n==================================================");
        $display(" Testbench Finished! ");
        $display("==================================================");
        
        #50;
        $finish;
    end

endmodule