//Ansel Herndon
//ECE480 Fall 2022

`timescale 1ns / 1ps

module fifo(clk, reset, sclr, wren, rden, full, empty, din, dout );
input clk, reset, sclr, wren, rden;
input [7:0] din;
output full, empty;
output [7:0] dout;

reg [2:0] waddr, raddr;
wire [7:0] douta, doutb;
dpmem u1 (
    .clka(clk),
    .ena(wren && (!full)),
    .wea(1'b1),
    .addra(waddr),
    .dina(din),
    .douta(douta),
    .clkb(clk),
    .enb(rden && (!empty)),
    .web(1'b0),
    .addrb(raddr),
    .dinb(din),
    .doutb(dout)
);

//Write counter
always @(posedge clk or posedge reset) begin
    if (reset) waddr <= 3'b000;
    else begin 
        if (wren && !full) waddr <= waddr + 1'b1;
        if (sclr) waddr <= 3'b000;
    end
end
//Read counter
always @(posedge clk or posedge reset) begin
    if (reset) begin
        raddr <= 3'b000;
        //dout = 0;
    end
    else begin 
        if (rden && !empty) begin
            //dout = doutb;
            raddr <= raddr + 1'b1;
        end
        if (sclr) raddr <= 3'b000;       
    end
end

assign empty = (waddr == raddr);
assign full = ((waddr + 1'b1) == raddr);


endmodule
