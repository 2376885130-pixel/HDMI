// Three clocks, one RGB pixel each clock. Contrast 128 and brightness 0 are
// bit-exact identity. Signed products are kept wide before saturation.
module picture_adjust_rgb(
 input wire clk,rst,input wire [23:0] rgb_in,input wire content_valid,
 input wire signed [7:0] brightness,input wire [7:0] contrast,
 output reg [23:0] rgb_out
);
 reg signed [17:0] product[0:2];
 reg signed [11:0] sum[0:2];
 reg signed [7:0] brightness_q;
 reg [1:0] valid_pipe;
 integer i;
 function [7:0] clip;input signed [11:0] value;
 begin clip=value<0?8'd0:value>255?8'd255:value[7:0];end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   for(i=0;i<3;i=i+1)begin product[i]<=0;sum[i]<=0;end
   brightness_q<=0;valid_pipe<=0;rgb_out<=0;
  end else begin
   for(i=0;i<3;i=i+1)begin
    product[i]<=($signed({1'b0,rgb_in[i*8+:8]})-9'sd128)*$signed({1'b0,contrast});
    sum[i]<=($signed(product[i])>>>7)+12'sd128+brightness_q;
    rgb_out[i*8+:8]<=valid_pipe[1]?clip(sum[i]):8'd0;
   end
   brightness_q<=brightness;valid_pipe<={valid_pipe[0],content_valid};
  end
 end
endmodule
