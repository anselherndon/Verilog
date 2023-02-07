
//VGA protocol support file for snake.v

module vga_sync (
    input vga_clk,
    output reg [9:0] xcount, ycount,
    output reg displayArea,
    output vga_hsync, vga_vsync
);
  
  reg p_hsync, p_vsync;
    
  parameter hfporch = 640;     //start of horizontal front porch
  parameter hsync = 656;       //start of h sync
  parameter hbporch = 752;     //start of h back porch
  parameter hmax = 800;        //total length

  parameter vfporch = 480;      //start of vertical front porch
  parameter vsync = 491;        //start of v sync
  parameter vbporch = 493;      //start of v back porch
  parameter vmax = 524;         //total # of rows
  
  always @(posedge vga_clk) begin
    if(xcount == hmax) xcount <= 0;
    else xcount = xcount + 1'b1;
  end
  
  always @(posedge vga_clk) begin
    if(xcount == hmax) begin
        if(ycount == vmax) ycount <= 0;
        else ycount <= ycount + 1'b1;
    end
  end

  always @(posedge vga_clk) begin
    displayArea <= ((xcount < hfporch) & (ycount < vfporch));
  end

  always @(posedge vga_clk) begin
    p_hsync <= ((xcount >= hsync) & (xcount < hbporch));
    p_vsync <= ((ycount >= vsync) & (ycount < vbporch));
  end
  
  assign vga_vsync = ~p_vsync;
  assign vga_hsync = ~p_hsync;

endmodule
