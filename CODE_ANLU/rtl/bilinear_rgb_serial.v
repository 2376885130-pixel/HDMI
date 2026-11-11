// RGB24 bilinear, 8 fractional weight bits. Reuse arithmetic across channels.
// Each horizontal interpolation truncates to eight bits before vertical mixing.
// The caller must hold all sample/weight inputs from start through done.
// bmp24_decoder already holds them in WAIT_RGB; avoid a duplicate 112-bit bank.
module bilinear_rgb_serial(input clk,rst,start,input [23:0] p00,p10,p01,p11,
 input [7:0] wx,wy,output reg done,output reg [23:0] rgb);
 reg [1:0] channel,state;reg [7:0] top,bottom,fx,fy;
 wire [7:0] ca=channel==0?p00[23:16]:channel==1?p00[15:8]:p00[7:0];
 wire [7:0] cb=channel==0?p10[23:16]:channel==1?p10[15:8]:p10[7:0];
 wire [7:0] cc=channel==0?p01[23:16]:channel==1?p01[15:8]:p01[7:0];
 wire [7:0] cd=channel==0?p11[23:16]:channel==1?p11[15:8]:p11[7:0];
 wire [8:0] ix=9'd256-{1'b0,fx},iy=9'd256-{1'b0,fy};
 wire [15:0] ht=ca*ix+cb*fx,hb=cc*ix+cd*fx;
 wire [15:0] vv=top*iy+bottom*fy;
 always @(posedge clk or posedge rst)begin
  if(rst)begin channel<=0;state<=0;done<=0;rgb<=0;top<=0;bottom<=0;fx<=0;fy<=0;end
  else begin
   done<=0;
   case(state)
    0:if(start)begin channel<=0;state<=1;fx<=wx;fy<=wy;end
    1:begin top<=ht[15:8];bottom<=hb[15:8];state<=2;end
    2:begin
     case(channel)0:rgb[23:16]<=vv[15:8];1:rgb[15:8]<=vv[15:8];2:rgb[7:0]<=vv[15:8];endcase
     if(channel==2)begin done<=1;state<=0;end else begin channel<=channel+1'b1;state<=1;end
    end
   endcase
  end
 end
endmodule
