`timescale 1ns / 1ps

module tb_uart_rx;

	// Inputs
	reg clk;
	reg reset;
	reg wren;
	reg rden;
	reg [7:0] din;
	reg rxin;
	reg [2:0] addr;

	// Outputs
	wire [8:0] dout;
	
	parameter CLK_PERIOD=20;       //clock period in ns.  20 ns = 50 MHZ
   //parameter UUT_PERIOD=8'h1A;    //57600 baudrate
   parameter UUT_PERIOD=8'h0C;    //115200 baudrate

   parameter CLK16X_PERIOD=(CLK_PERIOD*(UUT_PERIOD+1)*2);
   parameter CHARACTER_PERIOD = (CLK16X_PERIOD * 16 * 10);

	// Instantiate the Unit Under Test (UUT)
	uart_rx uut (
		.clk(clk), 
		.reset(reset), 
		.wren(wren), 
		.rden(rden), 
		.din(din), 
		.dout(dout), 
		.rxin(rxin), 
		.addr(addr)
	);
	
	`define FSIZE 1024

	integer infifo[(`FSIZE-1):0];
	integer head,tail;
	
	integer errors;
	
	initial begin
	 clk = 0;
	 #100   //reset delay
	 forever #10 clk = ~clk;
	end
	
	//timeout process
	initial begin
	
		#(CHARACTER_PERIOD*35);   //wait 35 characters

		if (head !== tail) begin		
		 $display("%t: TIMEOUT, not all characters processed.",$time);
		 $display("The timeout is probably due to the DATARDY bit never going high.");
	   end
	
	end
	
	reg [9:0] shiftdata;
	integer i;
	
	task putserialdata;
	 input [8:0] outdata;
	 
	 begin
	 
	  infifo[head] = outdata;
	  head = head + 1;	
     if (head 	=== `FSIZE) head = 0;
	  
	  shiftdata ={1'b1,outdata[7:0],1'b0};
	  i = 0;
	  while (i !== 10) begin
	   rxin = shiftdata[0];
		#(CLK16X_PERIOD*16);  //wait one bit time
		i = i + 1;
		shiftdata = {1'b1,shiftdata[9:1]};	  
	  end	 
	  //delay for at least one extra bit to accomodate clock differences
	  #(CLK16X_PERIOD*16);  //wait one bit time
	  rxin = 1;
	 end
	endtask 
	
	task putserialdata_badstop;
	 input [8:0] outdata;
	 
	 begin
	 
	  infifo[head] = outdata;
	  head = head + 1;	
     if (head 	=== `FSIZE) head = 0;
	  
	  shiftdata ={1'b1,outdata[7:0],1'b0};
	  i = 0;
	  while (i !== 10) begin
	   if (i === 9) rxin = 0;
	   else rxin = shiftdata[0];
		#(CLK16X_PERIOD*16);  //wait one bit time
		i = i + 1;
		shiftdata = {1'b1,shiftdata[9:1]};	  
	  end	 
	  	 //delay for at least one extra bit to accomodate clock differences
	 #(CLK16X_PERIOD*16);  //wait one bit time
	 rxin = 1;
	 #(CLK16X_PERIOD*16);  //wait one bit time
	 #(CLK16X_PERIOD*16);  //wait one bit time
	 end

	 
	endtask 
	
	task putserialdata_badstart;
	 input [8:0] outdata;
	 
	 begin
	 
	  infifo[head] = outdata;
	  head = head + 1;	
     if (head 	=== `FSIZE) head = 0;
	  
	  shiftdata ={1'b1,outdata[7:0],1'b0};
	  i = 0;
	  while (i !== 10) begin
	   if (i === 0) begin
		 rxin = 0;
		 #(CLK16X_PERIOD*2);
		 rxin = 1; //bad start
		 #(CLK16X_PERIOD*14);
		end else begin
	     rxin = shiftdata[0];
		  #(CLK16X_PERIOD*16);  //wait one bit time		
       end
	    i = i + 1;
		shiftdata = {1'b1,shiftdata[9:1]};			 
	 end
	 //delay for at least one extra bit to accomodate clock differences
	  #(CLK16X_PERIOD*16);  //wait one bit time
	end
	endtask 
	
	
	reg [8:0] expecteddata;
	
	task readdata;	
	begin
	  //read status register, wait for TXDONE bit to be set
	  @(negedge clk);
	  rden = 1;	 
     addr = 7;    //status register
	  @(negedge clk);
	  while (dout[1] === 0) begin
	   @(negedge clk); //wait for DataRdy bit
	  end
	  addr = 5;    //FIFO register
	  @(negedge clk);  
	  addr = 7;
	  @(posedge clk); //give entire clock period to read data
	  if (expecteddata[8] === 1) begin
	   //expected framing error, just check ferr bit
		if (dout[8] !== 1) begin
		  errors = errors + 1;
		  $display("%t: FAIL,did not receive expected framing error",$time);
		end else begin
		  $display("%t: PASS,received expected framing error",$time);
		end	  
	  end else begin
	   //no expected framing error
		if (expecteddata !== dout) begin
		  errors = errors + 1;
	     $display("%t: FAIL,expected serial out of %h, found: %h",$time,expecteddata,dout);
		end else begin
		  $display("%t: PASS,got expected serial out of %h (%h)",$time,expecteddata, dout);
		end
	  end
	 
	  @(negedge clk);
	  rden = 0;  //do not drop rden until address changes
	  @(negedge clk);
	  
	
	end
	endtask
	
	task checkdata;
	
	begin
	 while (head !== tail) begin
	  expecteddata = infifo[tail];
	  tail = tail + 1;
	  if (tail === `FSIZE) tail = 0;
	  
	  readdata();	 
	 
	 end
	end
	endtask 
	
	task writerxen;    //this writes a 'expectedbit' to the EN bit of the control register
	input expectedbit;
   begin
	 @(negedge clk);
	 	din = {7'b0000000,expectedbit};
		wren = 1;
		addr = 7;
		@(negedge clk);
		wren = 0;
		rden = 1;
		@(negedge clk);
		@(negedge clk);
		if (dout[0] !== expectedbit) begin
	     errors = errors + 1;
	     $display("%t: FAIL, writing UART RXEN bit = %h failed.",$time,expectedbit);
	   end else begin
	     $display("%t: PASS, writing UART RXEN bit = %h.",$time, expectedbit);
		end 
		rden = 0;
	 @(negedge clk);
	end
	endtask
	
	task rdoverrun;    //read the overrun flag
	input expectedbit;
   begin
	  @(negedge clk);
	   addr = 7;
		rden = 1;
	   @(negedge clk);
	   @(posedge clk);  //give entire clock period to read
		if (dout[2] !== expectedbit) begin
	     errors = errors + 1;
	     $display("%t: FAIL, reading UART OVERRUN bit, expected: %h, actual: %h.",$time,expectedbit,dout[2]);
	   end else begin
	     $display("%t: PASS, reading UART OVERRUN bit: %h.",$time, expectedbit);
		end 
		rden = 0;
	   @(negedge clk);
	 end
	 endtask
	 
	 task rddatardy;    //read the data rdy flag
	input expectedbit;
   begin
	  @(negedge clk);
	   addr = 7;
		rden = 1;
	   @(negedge clk);
		if (dout[1] !== expectedbit) begin
	     errors = errors + 1;
	     $display("%t: FAIL, reading UART DATARDY bit, expected: %h, actual: %h.",$time,expectedbit,dout[1]);
	   end else begin
	     $display("%t: PASS, reading UART DATARDY bit.",$time);
		end 
		rden = 0;
	 end
	 endtask
	 
	 
	 task inituart;
	 begin
	 @(negedge clk);
		//first need to write the period register
		din = UUT_PERIOD;
		wren = 1;
		addr = 4;
		@(negedge clk);
		wren = 0;
		rden = 1;
		@(negedge clk);
		@(negedge clk);
		if (dout !== UUT_PERIOD) begin
	     errors = errors + 1;
	     $display("%t: FAIL, PERIOD register write/read failed: %h, expected: %h",$time,UUT_PERIOD,dout);
	   end else begin
	     $display("%t: PASS, Period register read/write",$time);
		end 
		rden = 0;
		@(negedge clk);
		writerxen(1);   //write a '1' to UART to get it started
	  end
	 endtask
	 
	 
	 integer j;

	initial begin
		// Initialize Inputs
		#1
		clk = 0;
		reset = 1;
		wren = 0;
		rden = 0;
		din = 0;
		rxin = 1;
		addr = 0;
		errors = 0;
		head = 0;
		tail = 0;
		// Wait 100 ns for global reset to finish
		#100;
        
		// Add stimulus here
		reset = 0;
		// Add stimulus here
		@(negedge clk);
		@(negedge clk);
		@(negedge clk);
		@(negedge clk);
		inituart();		
		putserialdata(9'h039);
		checkdata();
		putserialdata(9'h012);
		putserialdata(9'h0D3);
		putserialdata(9'h0B7);
		#(CHARACTER_PERIOD*3)
		#(CLK16X_PERIOD*16)
		checkdata();
		$display("Testing bad stop bit");
		putserialdata_badstop(9'h155);  //test bad stop bit
		checkdata();
		@(negedge clk);
		reset = 1;
		#100;
		@(negedge clk);
		reset = 0;
		@(negedge clk);
		@(negedge clk);
		inituart();
		
		$display("Testing bad start bit");
		putserialdata_badstart(9'h1AA);  //test bad stop bit
		checkdata();
		putserialdata(9'h084);
		checkdata();
		//now test overrun
		j = 0;
		while (j !== 7) begin
		 putserialdata(j+ 9'h030);	
       j = j + 1;		 
		end
		//check the overrun bit
		@(negedge clk);
		@(negedge clk);
		@(negedge clk);
		rdoverrun(0);
		//send one more character, will set the overrun bit.
		putserialdata(j+ 9'h030);
		@(negedge clk);
		@(negedge clk);
		@(negedge clk);
		rdoverrun(1);
		//now reset the uart
		writerxen(0);   //write a '0' to UART RXEN to reset it.
		//overrun should now be 0.
		@(negedge clk);
		@(negedge clk);
		rdoverrun(0);
		//data avaialble bit should be 0 as well
		rddatardy(0);
      //re-enable the modem
		writerxen(1);   //write a '1' to UART RXEN to enable  it.
		//we need flush our internal FIFO 
		head = 0; tail = 0;
		//write one more datum to verify FIFO is restarted
		putserialdata(9'h0A7);
		checkdata();
		$display("%t: All vectors done.",$time);
		if (errors !== 0) 
		  $display("%t: FAIL, had %d errors during simulation.",$time,errors);
		else
		  $display("%t: PASS, no errors during simulation.",$time); 

	end
      
endmodule

