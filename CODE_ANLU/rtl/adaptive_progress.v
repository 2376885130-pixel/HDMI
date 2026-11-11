// Frame-stable preview fade and honest loading work bar, with moving activity mark.
// Coordinates/RGB are already aligned by the existing 21-cycle video pipeline.
module adaptive_progress(input clk,rst,frame_start,input [9:0] x,y,
 input [23:0] rgb_in,input preview,zoom,loading,input [9:0] progress,
 output wire [23:0] rgb_out);
 reg last_preview;reg [3:0] fade;
 reg show_bar;reg [9:0] amount;reg [5:0] motion;
 always @(posedge clk or posedge rst)begin
  if(rst)begin last_preview<=0;fade<=8;show_bar<=0;amount<=0;motion<=0;end
  else if(frame_start)begin
   last_preview<=preview;show_bar<=loading;amount<=progress>480?10'd480:progress;motion<=motion+1'b1;
   if(!preview)fade<=0;
   else if(!last_preview)fade<=1;
   else if(fade<8)fade<=fade+1'b1;
  end
 end
 wire [3:0] gain=preview && !last_preview ? 4'd0 : fade;
 wire [11:0] rr=rgb_in[23:16]*gain,gg=rgb_in[15:8]*gain,bb=rgb_in[7:0]*gain;
 wire [23:0] faded=preview && !zoom ? {rr[10:3],gg[10:3],bb[10:3]} : rgb_in;
 wire bar=show_bar && x>=78 && x<562 && y>=448 && y<466;
 wire border=x<80 || x>=560 || y<450 || y>=464;
 wire filled=x<80+amount;
 wire moving=((x[5:0]-motion)<6'd8);
 assign rgb_out=bar ? (border?24'he0e0e0:(filled?24'h30c878:(moving?24'h707080:24'h202028))) : faded;
endmodule
