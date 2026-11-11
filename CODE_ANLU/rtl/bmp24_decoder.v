// Streaming BMP -> centered aspect-fill 640x480 RGB24. No extra frame RAM.
// Two BRAM rows retain the four bilinear samples; no raw frame in SDRAM.
// Header metadata uses a separate ORIGINAL-SD input. Pixel replay observes
// byte_ready. Keep header validity independent of replay RAM and replay address.
module bmp24_decoder(
 input wire clk,rst,probe_start,load_start,
 input wire byte_valid,decode_pixels,suppress_pixel,input wire [7:0] sector_byte,
 input wire [31:0] file_position,file_size,
 output wire header_ok,header_error,output reg pixel_valid,
 output reg [23:0] pixel_rgb,output reg [18:0] pixel_count,
 output wire byte_ready,output wire processing,
 output wire [9:0] progress_rows,
 input wire header_byte_valid,input wire [7:0] header_byte,input wire [31:0] header_position,
 output wire [3:0] header_reject_reason,output reg content_valid
);
 wire [31:0] pixel_offset;
 wire [11:0] bmp_width,bmp_height;
 wire [13:0] row_stride;
 wire header_complete;
 bmp24_header u_header(.clk(clk),.rst(rst),.start(probe_start || load_start),
  .byte_valid(header_byte_valid),.data(header_byte),.position(header_position),.file_size(file_size),
  .complete(header_complete),.valid(header_ok),.width(bmp_width),.height(bmp_height),
  .pixel_offset(pixel_offset),.stride(row_stride),.reject_reason(header_reject_reason));
 localparam HEADER=0,FIT_START=1,FIT_WAIT=2,X_START=3,X_WAIT=4,Y_START=5,Y_WAIT=6,
  CHECK=7,READ=8,PIXEL=9,R0=10,R1=11,R2=12,R3=13,R4=14,INTERP=15,WAIT_RGB=16,
  EMIT=17,BLACK_WAIT=18,FINISHED=19,BAD=20,ROW_PREP=21;
 reg [4:0] state;
 reg [11:0] width,height,source_row,loaded_row;
 reg [11:0] crop_w,crop_h,origin_x,origin_y;
 reg have_rows,wide,row_active,active_pixel;
 reg [13:0] stride,row_byte;
 reg [10:0] source_x;
 reg [1:0] component;
 reg [7:0] blue,green;
 reg [9:0] fit_w,fit_h,left,bottom,x,y;
 reg [10:0] right_edge,bottom_edge,last_x,last_y;
 wire [13:0] source_row_bytes={2'd0,width}+{1'd0,width,1'b0};
 reg [27:0] step_x,step_y,coord_x,coord_y;
 reg [3:0] black_delay;
 reg div_start;reg [27:0] numerator;reg [11:0] denominator;
 wire div_done,div_busy;wire [27:0] quotient;
 scale_divider u_div(clk,rst,div_start,numerator,denominator,div_busy,div_done,quotient);
 reg [23:0] rows[0:4095];reg [11:0] read_address;reg [23:0] read_value;
 reg [23:0] p00,p10,p01,p11;
 wire [11:0] sx=x==last_x ? origin_x+crop_w-1'b1 : coord_x[27:16];
 wire [11:0] next_sy=y==last_y ? origin_y+crop_h-1'b1 : coord_y[27:16];
 reg [11:0] sy,sy1;
 wire [11:0] sx1={1'b0,sx}+13'd1<width?sx+1'b1:sx;
 wire in_row=y>=bottom && y<bottom_edge;
 wire in_picture=row_active && x>=left && x<right_edge;
 wire [7:0] wx=x==last_x ? 8'd0 : coord_x[15:8];
 wire [7:0] wy=y==last_y ? 8'd0 : coord_y[15:8];
 wire rgb_done;wire [23:0] rgb_result;
 bilinear_rgb_serial u_bilinear(clk,rst,state==INTERP,p00,p10,p01,p11,wx,wy,rgb_done,rgb_result);
 assign byte_ready=state==HEADER || state==READ || state==FINISHED || !decode_pixels;
 assign processing=decode_pixels && !byte_ready;
 assign progress_rows=y;
 assign header_error=decode_pixels && header_complete && !header_ok;
 always @(posedge clk)begin
  read_value<=rows[read_address];
  if(state==READ && byte_valid && byte_ready && decode_pixels && file_position>=pixel_offset &&
     row_byte<source_row_bytes && component==2 && !suppress_pixel)
   rows[{source_row[0],source_x}]<={sector_byte,green,blue};
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=HEADER;pixel_valid<=0;pixel_rgb<=0;pixel_count<=0;content_valid<=0;
   width<=0;height<=0;source_row<=0;loaded_row<=0;have_rows<=0;wide<=0;stride<=0;row_byte<=0;source_x<=0;
   crop_w<=0;crop_h<=0;origin_x<=0;origin_y<=0;
   component<=0;blue<=0;green<=0;fit_w<=0;fit_h<=0;left<=0;bottom<=0;x<=0;y<=0;row_active<=0;active_pixel<=0;
   step_x<=0;step_y<=0;coord_x<=0;coord_y<=0;black_delay<=0;div_start<=0;numerator<=0;denominator<=1;
   read_address<=0;p00<=0;p10<=0;p01<=0;p11<=0;
   right_edge<=0;bottom_edge<=0;last_x<=0;last_y<=0;sy<=0;sy1<=0;
  end else begin
   pixel_valid<=0;div_start<=0;
   case(state)
    HEADER:if(decode_pixels && header_complete)begin
     if(!header_ok)state<=BAD;
     else begin
      width<=bmp_width[11:0];height<=bmp_height[11:0];stride<=row_stride;
      wide<=bmp_width[11:0]*21'd480>=bmp_height[11:0]*21'd640;
      state<=FIT_START;
     end
    end
    FIT_START:begin numerator<=wide?height*28'd640:width*28'd480;denominator<=wide?12'd480:12'd640;div_start<=1;state<=FIT_WAIT;end
    FIT_WAIT:if(div_done)begin
     crop_w<=wide?(quotient==0?12'd1:quotient[11:0]):width;
     crop_h<=wide?height:(quotient==0?12'd1:quotient[11:0]);
     fit_w<=640;fit_h<=480;state<=X_START;
    end
    X_START:begin
     left<=0;bottom<=0;origin_x<=(width-crop_w)>>1;origin_y<=(height-crop_h)>>1;
     numerator<=(crop_w-28'd1)<<16;denominator<=639;div_start<=1;state<=X_WAIT;
    end
    X_WAIT:if(div_done)begin step_x<=fit_w==1?28'd0:quotient;state<=Y_START;end
    Y_START:begin
     numerator<=(crop_h-28'd1)<<16;denominator<=479;div_start<=1;state<=Y_WAIT;
     coord_y<={origin_y,16'd0};
     right_edge<={1'b0,left}+{1'b0,fit_w};bottom_edge<={1'b0,bottom}+{1'b0,fit_h};
     last_x<=({1'b0,left}+{1'b0,fit_w})-11'd1;last_y<=({1'b0,bottom}+{1'b0,fit_h})-11'd1;
    end
    Y_WAIT:if(div_done)begin step_y<=fit_h==1?28'd0:quotient;state<=ROW_PREP;end
    // Resolve row geometry once per output row, before the loader/read FSM.
    ROW_PREP:begin
     row_active<=in_row;sy<=next_sy;
     sy1<={1'b0,next_sy}+13'd1<height?next_sy+1'b1:next_sy;
     state<=CHECK;
    end
    CHECK:begin
     x<=0;coord_x<={origin_x,16'd0};
     if(!row_active || (have_rows && loaded_row>=sy1))state<=PIXEL;
     else state<=READ;
    end
    READ:if(byte_valid && decode_pixels && file_position>=pixel_offset && file_position<file_size)begin
     if(row_byte<source_row_bytes)begin
      case(component)
       0:begin blue<=sector_byte;component<=1;end
       1:begin green<=sector_byte;component<=2;end
       2:begin component<=0;source_x<=source_x+1'b1;end
      endcase
     end
     if(row_byte+1==stride)begin
      loaded_row<=source_row;have_rows<=1;source_row<=source_row+1'b1;
      row_byte<=0;source_x<=0;component<=0;state<=CHECK;
     end else row_byte<=row_byte+1'b1;
    end
    PIXEL:begin
     active_pixel<=in_picture;
     if(in_picture)begin read_address<={sy[0],sx[10:0]};state<=R0;end
     else begin pixel_rgb<=0;black_delay<=12;state<=BLACK_WAIT;end
    end
    R0:begin read_address<={sy[0],sx1[10:0]};state<=R1;end
    R1:begin p00<=read_value;read_address<={sy1[0],sx[10:0]};state<=R2;end
    R2:begin p10<=read_value;read_address<={sy1[0],sx1[10:0]};state<=R3;end
    R3:begin p01<=read_value;state<=R4;end
    R4:begin p11<=read_value;state<=INTERP;end
    INTERP:state<=WAIT_RGB;
    WAIT_RGB:if(rgb_done)begin pixel_rgb<=rgb_result;state<=EMIT;end
    BLACK_WAIT:if(black_delay==0)state<=EMIT;else black_delay<=black_delay-1'b1;
    EMIT:begin
     pixel_valid<=!suppress_pixel;pixel_count<=pixel_count+1'b1;content_valid<=active_pixel;
     if(active_pixel)coord_x<=coord_x+step_x;
     if(x==639)begin
      if(row_active)coord_y<=coord_y+step_y;
      if(y==479)begin y<=480;state<=FINISHED;end else begin y<=y+1'b1;state<=ROW_PREP;end
     end else begin x<=x+1'b1;state<=PIXEL;end
    end
   endcase
   if(probe_start || load_start)begin
    state<=HEADER;pixel_count<=0;pixel_valid<=0;content_valid<=0;
    source_row<=0;loaded_row<=0;have_rows<=0;row_byte<=0;source_x<=0;component<=0;x<=0;y<=0;coord_x<=0;coord_y<=0;
   end
   if(suppress_pixel)begin pixel_valid<=0;if(decode_pixels)state<=BAD;end
  end
 end
endmodule
