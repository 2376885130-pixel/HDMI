// Small experiment HUD after image adjustment, before global fault/loading OSD.
module p_rover_overlay(input wire [9:0] x,y,input wire enable,
 input wire [63:0] state,input wire [23:0] rgb_in,output reg [23:0] rgb_out);
 // New devices show the selected parameter (0..90; thrust uses 0..18 steps).
 // Keep the original lunar-rover overlay bit-for-bit for model zero.
 wire second_parameter=state[63:62]!=0&&state[60:59]==1;
 wire [6:0] secondary_angle={state[9:5],2'b0}+{2'b0,state[9:5]};
 wire [6:0] angle=second_parameter?secondary_angle:state[58:52];
 wire [4:0] power=second_parameter?state[9:5]:state[44:40];
 function [6:0] segments(input [3:0] n);
  case(n)
   0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;
   3:segments=7'b1111001;4:segments=7'b0110011;5:segments=7'b1011011;
   6:segments=7'b1011111;7:segments=7'b1110000;8:segments=7'b1111111;
   9:segments=7'b1111011;default:segments=0;
  endcase
 endfunction
 wire [3:0] tens=angle>=80?8:angle>=70?7:angle>=60?6:angle>=50?5:angle>=40?4:angle>=30?3:angle>=20?2:angle>=10?1:0;
 wire [3:0] units=angle>=90?0:angle[0]?5:0;
 wire [3:0] atens=angle==90?9:tens;
 wire [6:0] bits=segments(x<528?atens:units);
 wire [3:0] xx=x[3:0];wire [4:0] yy=y-64;
 wire digit=(bits[6]&&yy<2&&xx>=3&&xx<12)||(bits[5]&&yy>=2&&yy<10&&xx>=11&&xx<13)||
  (bits[4]&&yy>=10&&yy<18&&xx>=11&&xx<13)||(bits[3]&&yy>=18&&yy<20&&xx>=3&&xx<12)||
  (bits[2]&&yy>=10&&yy<18&&xx>=1&&xx<3)||(bits[1]&&yy>=2&&yy<10&&xx>=1&&xx<3)||
  (bits[0]&&yy>=9&&yy<11&&xx>=3&&xx<12);
 always @*begin
  rgb_out=rgb_in;
  if(enable&&x>=512&&x<608&&y>=60&&y<96)begin
   rgb_out=24'h152b41;
   if(x<544&&y>=64&&y<84&&digit)rgb_out=24'hffce40;
   if(y>=88&&y<92&&x<512+{2'd0,power,2'b0})rgb_out=24'h62cfff;
  end
 end
endmodule
