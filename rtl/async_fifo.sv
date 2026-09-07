`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/05/2026 10:14:39 PM
// Design Name: 
// Module Name: async_fifo
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


module async_fifo #(
    parameter int DEPTH = 16,
    parameter int DATA_WIDTH = 8
) (
    input logic wclk,
    input logic rclk,
    input logic wrst,
    input logic rrst,
    input logic wr_en,
    input logic rd_en,
    input logic [DATA_WIDTH-1:0] din,
    output logic full,
    output logic empty,
    output logic [DATA_WIDTH-1:0] dout
);
    localparam int PTR_WIDTH = $clog2(DEPTH);
    logic [PTR_WIDTH:0] wptr_gray = '0;
    logic [PTR_WIDTH:0] wptr_gray_sync = '0;
    logic [PTR_WIDTH:0] rptr_gray = '0;
    logic [PTR_WIDTH:0] rptr_gray_sync = '0;
    logic [PTR_WIDTH:0] wptr = '0;
    logic [PTR_WIDTH:0] rptr = '0;
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    logic rrst_sync, wrst_sync;
    
    assign empty = (rptr_gray == wptr_gray_sync);
    assign full = (wptr_gray == {~rptr_gray_sync[PTR_WIDTH:PTR_WIDTH-1], rptr_gray_sync[PTR_WIDTH-2:0]});
    assign dout = mem[rptr[PTR_WIDTH-1:0]];
    
    sync_ff2 #(.WIDTH($clog2(DEPTH)+1)) wptr_sync (.clk(rclk), .rst(rrst_sync), .async_in(wptr_gray), .async_out(wptr_gray_sync));
    sync_ff2 #(.WIDTH($clog2(DEPTH)+1)) rptr_sync (.clk(wclk), .rst(wrst_sync), .async_in(rptr_gray), .async_out(rptr_gray_sync));
    rst_sync dut_sync_rrst (.clk(rclk), .rst(rrst), .sync_out(rrst_sync));
    rst_sync dut_sync_wrst (.clk(wclk), .rst(wrst), .sync_out(wrst_sync));
    
    always_ff@ (posedge wclk or posedge wrst_sync) begin
        if (wrst_sync) begin
            wptr <= '0;
            wptr_gray <= '0;
        end else if (!full && wr_en) begin
            mem[wptr[PTR_WIDTH-1:0]] <= din; 
            wptr <= wptr + 1;
            wptr_gray <= (wptr + 1) ^ ((wptr + 1) >> 1);
        end
    end
    
    always_ff@ (posedge rclk or posedge rrst_sync) begin
        if (rrst_sync) begin
            rptr <= '0;
            rptr_gray <= '0;
        end else if (!empty && rd_en) begin
            rptr <= rptr + 1;
            rptr_gray <= (rptr + 1) ^ ((rptr + 1) >> 1);
        end
    end
    
endmodule

module sync_ff2 #(
    parameter int WIDTH = 4
) (
    input logic clk,
    input logic rst,
    input logic [WIDTH-1:0] async_in,
    output logic [WIDTH-1:0] async_out
);
    logic [WIDTH-1:0] sync_ff;
    
    always_ff@(posedge clk or posedge rst) begin 
        if (rst) begin
            sync_ff <= '0;
            async_out <= '0;
        end else begin
            sync_ff <= async_in;
            async_out <= sync_ff;
        end
    end
endmodule

module rst_sync (
    input logic clk,
    input logic rst,
    output logic sync_out
);
    logic sync_ff;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_ff  <= 1'b1;
            sync_out <= 1'b1;
        end else begin
            sync_ff  <= 1'b0;
            sync_out <= sync_ff;
        end
    end
endmodule
