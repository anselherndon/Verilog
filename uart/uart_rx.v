`timescale 1ns / 1ps

module uart_rx (
  input clk, reset, wren, rden,
  input rxin, // serial data in
  input [2:0] addr,
  input [7:0] din,
  output reg [8:0] dout
);

  parameter PERIOD = 8'h1A; // must have this initial value
  
//Baud Rate Generator***********************************************************************************************************************
    reg [7:0] PR_dout, TMR_dout; 
    wire tmr_match;
    reg tmr_en, baudclk;
    //Period Register
    wire ldPR;
    assign ldPR = wren & (addr == 3'b100);
    always @(posedge clk or posedge reset) begin
        if(reset) PR_dout <= PERIOD;
        else begin
            if(ldPR) PR_dout <= din;
        end
    end
    //Timer Register
    reg tmr_sclr; 
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
wire [8:0] douta, fifo_dout, fifo_din;
reg fifo_wren, fifo_sclr;
wire fifo_rden;
assign fifo_rden = rden & ~empty;

dpmem u1 (
    .clka(clk),
    .ena(fifo_wren),
    .wea(1'b1),
    .addra(waddr),
    .dina(fifo_din),
    .douta(douta),
    .clkb(clk),
    .enb(fifo_rden && (!empty)),
    .web(1'b0),
    .addrb(raddr),
    .dinb(fifo_din),
    .doutb(fifo_dout)
);
//Write counter
always @(posedge clk or posedge reset) begin
    if (reset) waddr <= 3'b000;
    else begin 
        if (fifo_wren) waddr <= waddr + 1'b1;
        if (fifo_sclr) waddr <= 3'b000;
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
        if (fifo_sclr) raddr <= 3'b000;       
    end
end
assign empty = (waddr == raddr);
assign full = ((waddr + 1'b1) == raddr);
//*******************************************************************************************************************************************

//*******************************************************************************************************************************************
//Bit Counter
reg [3:0] bitcnt;
reg bitcnt_en, bitcnt_sclr;
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
reg bittimer_en, bittimer_sclr;
always @ (posedge clk or posedge reset) begin
	  if (reset) begin
	    bittimer <= 4'b0000;
	  end else begin
	    if (bittimer_sclr) bittimer <= 4'b0000;
	    else if (bittimer_en) bittimer <= bittimer + 1;
   end
end
//********************************************************************************************************************
//Shift Register
reg [9:0] sreg;
reg sreg_en;
reg sdin, rxin_q1;

always @(posedge clk)begin
    rxin_q1 <= rxin;
end

always @(posedge clk)begin
    sdin <= rxin_q1;
end

always @ (posedge clk or posedge reset) begin
  if (reset) begin
    sreg <= 10'b1111111111;
  end else begin
    if (sreg_en) sreg <= {sdin, sreg[9:1]};
  end
end

assign fifo_din = sreg[9:1]; 

//RXEN bit
wire rxen;
assign rxen = rden & (addr == 3'b101);

//OVERRUN bit
reg overrun;
always @(*) begin
    if(~rxen) overrun = 1'b0;
    if(full) overrun = 1'b1;
end

//Read Logic
reg [2:0] addrq;
reg rdenq;
always @ (posedge clk) begin
addrq <= addr;
rdenq <= rden;
end

always @ (*) begin
    dout = 9'd0;
    if (rdenq) begin
      case (addrq) 
          3'b000: dout = PR_dout; 
          3'b101: dout = fifo_dout;
          3'b011: dout = {5'b00000, overrun, ~empty, rxen}; // Status/Control
        endcase
    end
end

//FSM Combinational Logic******************************************************************************************************************************
`define STATE_INPUT_WAIT    3'b000
//`define STATE_START
`define STATE_SHIFT1        3'b001
`define STATE_SHIFT2        3'b010
`define STATE_DATA          3'b011
`define STATE_STOP          3'b100
`define STATE_OVERRUN       3'b101

reg [2:0] nstate, pstate;
always @(posedge clk or posedge reset)begin
    if(reset) begin
        pstate <= `STATE_INPUT_WAIT;
    end else begin
        pstate <= nstate;
    end
end

always @(*) begin
    //Default values
    fifo_wren = 0;
    fifo_sclr = 0;
    sreg_en = 0;
    tmr_en = 0;
    tmr_sclr = 0;
    bittimer_en = 0;
    bittimer_sclr = 0;
    bitcnt_en = 0;
    bitcnt_sclr = 0;
    //rxen = 0;
    //overrun = 0;
    case(pstate)
        `STATE_INPUT_WAIT: begin
            tmr_sclr = 1;
            bitcnt_sclr = 1;
            bittimer_sclr = 1;
            fifo_sclr = 1;
            if(rxen) begin
                if(sdin == 1'b0) nstate = `STATE_SHIFT1; 
            end 
        end
        /*`STATE_START: begin
            tmr_en = 1;
            bittimer_en = 1;
            if(rxen) begin
                if(bittimer == 4'h08) begin
                    if(sdin == 1'b0) begin
                        sreg_en = 1;
                        bitcnt_en = 1;
                        nstate = `STATE_DATA;
                    end 
                end
            end else begin
                nstate = `STATE_INPUT_WAIT;
            end
        end  */
        `STATE_SHIFT1: begin
            tmr_en = 1;            
            if (rxen) begin
                if (bitcnt == 4'b1010) begin
                    nstate = `STATE_INPUT_WAIT;
                end else if (baudclk) begin
                    bittimer_en = 1;
                    nstate = `STATE_SHIFT2;
                end
            end else begin
                nstate = `STATE_INPUT_WAIT;
            end
        end
        `STATE_SHIFT2: begin
            tmr_en = 1;           
            if (rxen) begin
                if(baudclk == 0) begin
                    if(bittimer == 0) begin
                      bitcnt_en = 1;
                      sreg_en = 1;  
                    end
                end
                nstate = `STATE_SHIFT1;
            end else begin
                nstate = `STATE_INPUT_WAIT;
            end   
        end
        `STATE_DATA: begin
            tmr_en = 1;
            bittimer_en = 1;
            if (rxen) begin
                if(bittimer == 4'h08) begin
                    sreg_en = 1;
                    bitcnt_en = 1;
                end
                if (bitcnt == 4'h09) begin  //Could be > 8?
                    nstate = `STATE_STOP;
                end
            end else begin
                nstate = `STATE_INPUT_WAIT;
            end
        end
        `STATE_STOP: begin
            tmr_en = 1;
            bittimer_en = 1;
            if (rxen) begin
                if(bittimer == 4'h08) begin
                    if(full) begin
                        nstate = `STATE_OVERRUN;
                    end else if (sdin) begin
                        sreg_en = 1;
                        fifo_wren = 1;
                    end
                end
            end else begin
                nstate = `STATE_INPUT_WAIT;
            end
        end
        `STATE_OVERRUN: begin
            if(~rxen) nstate = `STATE_INPUT_WAIT;
        end
    endcase
end

endmodule
