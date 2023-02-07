`timescale 1ns / 1ps

module snake (
  input clk, btnl, btnr, btnu, btnd,
  input [1:0] SW,
  output reg [3:0] VGA_RED, VGA_GREEN, VGA_BLUE,
  output VGA_HS, VGA_VS,
  output [6:0] SSEG_CA,
  output [3:0] SSEG_AN
);

reg food, snake, head, body, border;
wire displayArea;
wire [9:0] xcount, ycount;
reg [3:0] direction, prev_direction;
wire red, blue, green;
reg gameOver, reset, fnd, pause;
reg inputX, inputY;
reg [9:0] foodX, foodY;
reg [9:0] snakeX[0:63]; 
reg [9:0] snakeY[0:63];
wire [9:0] rngX, rngY;
integer i, j, k;
reg [5:0] size;
reg [15:0] score;

// generate 25 MHz clock from board oscillator
  wire clk_25M, refresh;
  clk_wiz_0 clk_25M_gen (
    .clk_out1(clk_25M),
    .clk_in1(clk)
  );
  clock_update updclk (.clk(clk), .refresh(refresh));
  
  //New Game
  initial begin
    snakeX[0] = 10'd100; 
    snakeY[0] = 10'd100;
  end
  
  //Generate food
  randNum rng(.clock(clk_25M), .rX(rngX), .rY(rngY));
  wire eat;
  assign eat = head & food;
  always @(posedge clk_25M) begin
    inputX <= ((xcount > foodX) & (xcount < (foodX + 10))); 
    inputY <= ((ycount > foodY) & (ycount < (foodY + 10)));
    food <= inputX & inputY;
  end
  //Food start position
  always @(posedge clk_25M) begin
    if(gameOver | reset) begin
        foodX <= 300;
        foodY <= 300;
        size <= 4;
        score <= 0;
    end 
    if(eat) begin   //eat food
        foodX <= rngX;
        foodY <= rngY;
        size <= size + 1;
        score <= score + 1;
    end 
  end
  
  
  //Set border
  wire [9:0] b1, b2, b3, b4;
  assign b1 = (xcount >= 0) & (xcount < 11) & (ycount >= 11) & (ycount < 470);      //left bound
  assign b2 = (xcount >= 630) & (xcount < 641) & (ycount >= 11) & (ycount < 470);   //right bound
  assign b3 = (ycount >= 0) & (ycount < 11);        //upper bound
  assign b4 = (ycount >= 470) & (ycount < 480);     //lower bound
  always @(posedge clk_25M) begin
    border <= b1 | b2 | b3 | b4;
  end
  
  //Button Logic
  reg checkH, checkV;
  always @(posedge clk_25M) begin
    if(reset) begin
        direction <= 4'b0000;
        checkH <= 0;
        checkV <= 0;
    end
    else if(gameOver) begin
        direction <= 4'b0000;
        checkH <= 1;
        checkV <= 1;
    end
    else if(btnl & ~checkH) begin
        direction <= 4'b0001;
        checkH <= 1;
        checkV <= 0;
    end
    else if(btnr & ~checkH) begin
        direction <= 4'b0010;
        checkH <= 1;
        checkV <= 0;
    end
    else if(btnu & ~checkV) begin
        direction <= 4'b0100;
        checkH <= 0;
        checkV <= 1;
    end
    else if(btnd & ~checkV) begin
        direction <= 4'b1000;
        checkH <= 0;
        checkV <= 1;
    end
    else direction <= direction;
  end

  //Movement mechanics
  always @(posedge refresh) begin
    if(SW[0] & ~pause & ~gameOver) begin
        for(i = 63; i > 0; i = i-1) begin
            if(i <= size - 1)begin
                snakeX[i] = snakeX[i-1];
                snakeY[i] = snakeY[i-1];
                //score = score + 1;
            end
            case(direction)
                4'b0001: snakeX[0] <= snakeX[0] - 5; //move left
                4'b0010: snakeX[0] <= snakeX[0] + 5; //move right
                4'b0100: snakeY[0] <= snakeY[0] - 5; //move down
                4'b1000: snakeY[0] <= snakeY[0] + 5; //move up
            endcase
        end
    end 
    else if(~SW[0]) begin
        snakeX[0] = 10'd100;
        snakeY[0] = 10'd100;
        for(j = 1; j < 64; j = j+1) begin
            snakeX[j] = 700;
            snakeY[j] = 500;
        end
    end    
  end
  
  //Snake head
  always @(posedge clk_25M) begin
    head <= ((xcount > snakeX[0]) & (xcount < (snakeX[0] + 10))) & ((ycount > snakeY[0]) & (ycount < (snakeY[0] + 10)));
  end
  
  //Snake body
  always @(posedge clk_25M) begin
    fnd = 0;
    for(k = 1; k < size; k = k + 1)begin
        if(~fnd) begin
            snake = ((xcount > snakeX[k] && xcount < snakeX[k]+10) && (ycount > snakeY[k] && ycount < snakeY[k]+10));
            fnd = snake;
        end
    end
  end
  
  //Determine game over
  always @(posedge clk_25M) begin
    if(head & (border)) begin 
        gameOver <= 1;
    end
    else begin
        gameOver <= 0;
    end  
  end
  
  //Pause game with SW1
  always @(posedge clk_25M) begin
    if(SW[1]) pause <= 1;
    else pause <= 0;
  end
  
  vga_sync vga(
    .vga_clk(clk_25M),
    .xcount(xcount), 
    .ycount(ycount),
    .displayArea(displayArea),
    .vga_hsync(VGA_HS), 
    .vga_vsync(VGA_VS)
);

  assign red = displayArea & food;
  assign green = displayArea & (head | snake);
  assign blue = displayArea & border;

always @(posedge clk_25M) begin
    if(SW[0]) begin
        VGA_RED <= {4{red}};
        VGA_BLUE <= {4{blue}};
        VGA_GREEN <= {4{green}};
        reset <= 0;
    end else begin
        VGA_RED <= {4{1'b0}};
        VGA_BLUE <= {4{1'b0}};
        VGA_GREEN <= {4{1'b0}};
        reset <= 1;
    end 
end

  //Display score on seven segment display
  sseg scoreDisplay(
    .clk(clk),
    .reset(reset),
    .din(score),
    .an_out(SSEG_AN),
    .ca_out(SSEG_CA)
  );
  
 
endmodule
//****************************************************************************************************************
module clock_update(
    input clk,
    output reg refresh
);

  reg [21:0] check;
  
  always @(posedge clk) begin
    if(check < 4000000) begin
        check <= check + 1;
        refresh <= 0;
    end else begin
        check <= 0;
        refresh <= 1;
    end
  end
endmodule
//*****************************************************************************************************************
module randNum(
    input clock,
    output reg [9:0] rX, rY
);

reg [9:0] t1 = 15;
reg [9:0] t2 = 450;

always @(posedge clock) begin
    if(t1 < 610) t1 <= t1 + 1'b1;
    else t1 <= 10'b0000000000;
end
always @(posedge clock) begin
    if(t2 > 15) t2 <= t2 - 1'b1;
    else t2 <= 10'd450;
end

always @(*) begin
    rX <= t1;
    rY <= t2;
end

endmodule
//*******************************************************************************************************************
module sseg(
    input clk, reset,
    input [15:0] din,
    output reg [3:0] an_out,
    output reg [6:0] ca_out
);
reg [15:0] dinq;
wire [1:0] anodeCounter;
reg [19:0] pulseCounter;
reg [3:0] digit;

always @(posedge clk or posedge reset) begin
    if(reset) begin
        dinq <= 0;
        pulseCounter <= 0;
    end else begin
        dinq <= din;
        pulseCounter <= pulseCounter + 1;       
    end      
end
assign anodeCounter = pulseCounter[19:18];

always @(*) begin
    an_out = 4'b1111;
    digit = ((dinq % 1000) % 100) % 10;
    //digit = dinq[3:0];
    case(anodeCounter)
        2'b00:  begin
                    an_out = 4'b1110;
                    //digit = dinq[3:0];
                    digit = ((dinq % 1000) % 100) % 10;                    
                end
        2'b01:  begin
                    an_out = 4'b1101;
                    //digit = dinq[7:4];
                    digit = ((dinq % 1000) % 100) / 10;                   
                end
        2'b10:  begin
                    an_out = 4'b1011;
                    //digit = dinq[11:8];
                    digit = (dinq % 1000) / 100;
                end
        2'b11:  begin
                    an_out = 4'b0111;
                    //digit = dinq[15:12];
                    digit = dinq / 1000;
                end
    endcase
end

always @(*) begin
    case(digit)
        0 : ca_out = 7'b1000000;      
        1 : ca_out = 7'b1111001; 
        2 : ca_out = 7'b0100100; 
        3 : ca_out = 7'b0110000; 
        4 : ca_out = 7'b0011001; 
        5 : ca_out = 7'b0010010; 
        6 : ca_out = 7'b0000010; 
        7 : ca_out = 7'b1111000; 
        8 : ca_out = 7'b0000000;    
        9 : ca_out = 7'b0010000; 
        default: ca_out = 7'b1111111; 
    endcase
end

endmodule