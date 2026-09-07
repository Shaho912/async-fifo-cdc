`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/06/2026 01:36:03 AM
// Design Name: 
// Module Name: async_fifo_tb
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


module async_fifo_tb();
    logic wclk = 0, rclk = 0, wrst = 0, rrst = 0, wr_en = 0, rd_en = 0;
    logic [7:0] din, dout;
    logic full, empty;
    
    async_fifo #(
        .DEPTH(16),
        .DATA_WIDTH(8)
    ) dut1(
        .wclk(wclk),
        .rclk(rclk),
        .wrst(wrst), // raw async resets
        .rrst(rrst), 
        .wr_en(wr_en),
        .rd_en(rd_en),
        .din(din),
        .full(full),
        .empty(empty),
        .dout(dout)
    );
    
    always #100 wclk = ~wclk;
    always #66 rclk = ~rclk;
    
    task write_byte(input logic [7:0] data);
        @(posedge wclk) #1 begin
            wr_en = 1;
            din = data;
        end
        @(posedge wclk) #1 wr_en = 0;   
    endtask
    
    task read_byte();
        @(posedge rclk) #1 rd_en = 1;
        @(posedge rclk) #1 rd_en = 0;
    endtask
    
    task attempt_read_now();
        rd_en = 1;              // assert immediately, no waiting
        @(posedge rclk) #1 rd_en = 0;
    endtask
    
    initial begin
        $monitor("Time %0t - empty: %b, full: %b, rd_en: %b, dout: %h", 
            $time, empty, full, rd_en, dout);
        $display("Initial Reset");
        @(posedge wclk) #1 begin
            wrst = 1;
            @(posedge wclk) #1 wrst = 0;
        end
        @(posedge rclk) #1 begin
            rrst = 1;
            @(posedge rclk) #1 rrst = 0;
        end
        wait(!dut1.wrst_sync && !dut1.rrst_sync);
        
        $display("Begin Tests");
        
        $display("Test 1: Normal write/read");
        write_byte(8'hAA); // dout should instantly show AA
        attempt_read_now(); 
        $display("Test 1 (collision) first read should fail - empty flag: %b = 1 and dout %h = aa", 
            empty, dout); 
        wait(!empty);
        read_byte();
        $display("Test 1 successful read: %h = xx", dout);
        
        $display("Reset 1");
        @(posedge wclk) #1 begin
            wrst = 1;
            @(posedge wclk) #1 wrst = 0;
        end
        @(posedge rclk) #1 begin
            rrst = 1;
            @(posedge rclk) #1 rrst = 0;
        end
        wait(!dut1.wrst_sync && !dut1.rrst_sync);
        
        $display("Test 2: Read when empty");
        #1 read_byte();
        $display("Test 2 empty flag: %b = 1 and dout %h = aa", empty, dout); 
        
        $display("Test 3: Full fifo");
        for (int i = 0; i < 16; i++) begin
            write_byte(8'(i));
        end
        $display("Test 3 full flag %b = 1 and dout %h = 00", full, dout); 
        
        $display("Test 4: Write when full"); 
        #1 write_byte(8'hBB);
        $display("Test 4 full flag: %b = 1 and dout %h = 00", full, dout); 
        
        $display("Test 5: Reads when full"); 
        #1 read_byte();
        $display("Test 5 full flag needs 2 wclk cycles: %b = 1, empty flag: %b = 0, and dout %h = 01", full, empty, dout); 
        wait(!full);
        $display("Test 5 full flag now updated: %b = 0, empty flag: %b = 0, and dout %h = 01", full, empty, dout); 
        #1 read_byte();
        $display("Test 5 (2nd read) full flag: %b = 0, empty flag: %b = 0, and dout %h = 02", full, empty, dout);
        
        $display("Reset 2");
        @(posedge wclk) #1 begin
            wrst = 1;
            @(posedge wclk) #1 wrst = 0;
        end
        @(posedge rclk) #1 begin
            rrst = 1;
            @(posedge rclk) #1 rrst = 0;
        end
        wait(!dut1.wrst_sync && !dut1.rrst_sync);
        
        $display("Test 6: Successful same-cycle read + write");
        #1 write_byte(8'hCC); // write a byte first to ensure fifo is not empty
        wait(!empty);
        fork
            write_byte(8'hDD);
            read_byte();
        join
        wait(!empty);
        $display("SIMUL full flag: %b = 0, empty flag: %b = 0, and dout %h = dd", 
        full, empty, dout); // wait a while to ensure all values settle on both clock cycles
        
        $finish;
    end
    

endmodule
