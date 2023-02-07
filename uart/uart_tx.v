`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    15:37:23 10/06/2014 
// Design Name: 
// Module Name:    uart 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module uart_tx(clk, reset, wren, rden, din, dout, txout, addr);
input clk, reset, wren, rden;
input [7:0] din;
output [7:0] dout;
output txout;       //serial data out
input [2:0] addr;

reg [7:0] dout;

parameter PERIOD = 8'h1A;  

reg baudclk;
reg [3:0] bitcnt, bittmr;

//Control Declarations************************************************************************************************************************************
`define STATE_INPUT_WAIT    2'b00
`define STATE_LDSHIFT       2'b01
`define STATE_SHIFT1        2'b10
`define STATE_SHIFT2        2'b11
reg [1:0] nstate, pstate;
reg fifo_rden, bittimer_en, bittimer_sclr, bitcnt_en, bitcnt_sclr, sreg_ld, sreg_en, tmr_en, tmr_sclr, txdone_set;

//*******************************************************************************************************************************************

//Bit Counter
reg [3:0] bitcnt;
always @ (posedge clk or posedge reset) begin
	  if (reset) begin
	    bitcnt <= 4'b0000;
	  end else begin
	    if (bitcnt_sclr)  bitcnt <= 4'b0000;
	    else if (bitcnt_en)  bitcnt <= bitcnt + 1;
	  end
end
//Bit Timer
reg [3:0] bittimer;
always @ (posedge clk or posedge reset) begin
	  if (reset) begin
	    bittimer <= 4'b0000;
	  end else begin
	    if (bittimer_sclr) bittimer <= 4'b0000;
	    else if (bittimer_en) bittimer <= bittimer + 1;
   end
end

//Status/Control Register********************************************************************************************************************
/*reg [7:0] ctrl;
always @(*) begin
    ctrl[7:2] = 6'b000000;
end */
//TXFULL bit
reg txfull;
always @(posedge clk or posedge reset) begin
    if(reset) txfull = 0;
    else begin
        if(addr == 3'b011) txfull = full;
    end
end 
//TXDONE bit
wire txdone_clr;
reg txdone;

always @ (posedge clk or posedge reset) begin
if (reset) begin
  txdone <= 1'b0;
end else begin
  if (txdone_set) txdone <= 1'b1;
  if (txdone_clr) txdone <= 1'b0; 
end
end

assign txdone_clr = (wren & (addr == 3'b011) & (din[1]==1'b0));

reg [2:0] addrq;
reg rdenq;

always @ (posedge clk) begin
addrq <= addr;
rdenq <= rden;
end

//******************************************************************************************************************************************

//Baud Rate Generator***********************************************************************************************************************
    reg [7:0] PR_dout, TMR_dout; 
    wire tmr_match;
    //Period Register
    wire ldPR;
    assign ldPR = wren & (addr == 3'b000);
    always @(posedge clk or posedge reset) begin
        if(reset) PR_dout <= PERIOD;
        else begin
            if(ldPR) PR_dout <= din;
        end
    end
    //Timer Register
    wire tmr_sclr; 
    always @(posedge clk or posedge reset) begin
        if(reset) TMR_dout <= 8'h00;
        else begin              
            if (tmr_sclr) TMR_dout <= 32'h00000000;
            if (tmr_en) begin
                if (tmr_match == 1) TMR_dout <= 32'h00000000;
                else TMR_dout <= TMR_dout + 1;
            end
        end
    end
    //Comparator, Toggle FF
    assign tmr_match = (TMR_dout == PR_dout);
    always @(posedge clk or posedge reset)begin
        if(reset) baudclk = 0;
        else begin
            if(tmr_match && tmr_en) baudclk <= ~baudclk;
        end
    end
//******************************************************************************************************************************************

//FIFO Implementation***********************************************************************************************************************
reg [2:0] waddr, raddr;
wire [7:0] douta, fifo_dout;
wire fifo_wren;
assign fifo_wren = wren & (addr == 3'b001) & ~full;
//wire sclr = 0;
dpmem u1 (
    .clka(clk),
    .ena(fifo_wren),
    .wea(1'b1),
    .addra(waddr),
    .dina(din),
    .douta(douta),
    .clkb(clk),
    .enb(fifo_rden && (!empty)),
    .web(1'b0),
    .addrb(raddr),
    .dinb(din),
    .doutb(fifo_dout)
);
//Write counter
always @(posedge clk or posedge reset) begin
    if (reset) waddr <= 3'b000;
    else begin 
        if (fifo_wren) waddr <= waddr + 1'b1;
        //if (sclr) waddr <= 3'b000;
    end
end
//Read counter
always @(posedge clk or posedge reset) begin
    if (reset) begin
        raddr <= 3'b000;
    end
    else begin 
        if (fifo_rden && !empty) begin
            raddr <= raddr + 1'b1;
        end
        //if (sclr) raddr <= 3'b000;       
    end
end
assign empty = (waddr == raddr);
assign full = ((waddr + 1'b1) == raddr);
//*******************************************************************************************************************************************
//Append start stop bits
wire [9:0] fifo_data;
assign fifo_data = {1'b1, fifo_dout, 1'b0};

//10 bit TX shift register
reg [9:0] sreg;
assign txout = sreg[0];
always @ (posedge clk or posedge reset) begin
  if (reset) begin
    sreg <= 10'b1111111111;
  end else begin
    if (sreg_ld) sreg <= fifo_data;
    else if (sreg_en) sreg <= {1'b1,sreg[9:1]};
  end
end

//Dout MUX
always @ (*) begin
dout = 8'h00;
    if (rdenq) begin
      case (addrq) 
          3'b000: dout = PR_dout; // Period register
          3'b011: dout = {6'b000000,txdone, txfull}; // Status/Control
        endcase
    end
end

//Control******************************************************************************************
always @(posedge clk or posedge reset)begin
    if(reset) begin
        pstate <= `STATE_INPUT_WAIT;
    end else begin
        pstate <= nstate;
    end
end
always @(*) begin
    //default values
    fifo_rden = 0;
    sreg_ld = 0;
    sreg_en = 0;
    tmr_en = 0;
    tmr_sclr = 0;
    txdone_set = 0;
    bittimer_en = 0;
    bittimer_sclr = 0;
    bitcnt_en = 0;
    bitcnt_sclr = 0;
    nstate = pstate;
    case(pstate)
        `STATE_INPUT_WAIT: begin
            tmr_sclr = 1;
            bitcnt_sclr = 1;
            bittimer_sclr = 1;
            if(!empty) begin
                fifo_rden = 1;
                nstate = `STATE_LDSHIFT; 
            end 
        end
        `STATE_LDSHIFT: begin
            sreg_ld = 1;
            nstate = `STATE_SHIFT1;
        end
        `STATE_SHIFT1: begin
            tmr_en = 1;
            if (bitcnt == 4'b1010) begin
                txdone_set = 1;
                nstate = `STATE_INPUT_WAIT;
            end else if (baudclk) begin
                bittimer_en = 1;
                nstate = `STATE_SHIFT2;
            end
        end
        `STATE_SHIFT2: begin
            tmr_en = 1;
            if(baudclk == 0) begin
                if(bittimer == 0) begin
                  bitcnt_en = 1;
                  sreg_en = 1;  
                end
            end
            nstate = `STATE_SHIFT1;
        end
    endcase
end

endmodule
