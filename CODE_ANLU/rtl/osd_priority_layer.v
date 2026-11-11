// Generate UI from raw raster coordinates, then delay hit/color by exactly
// LATENCY clocks. rgb_in is already aligned; this adds no video latency.
// Shared compact ASCII font serves UART subtitles and non-blocking faults.
module osd_priority_layer #(parameter LATENCY=24,DEMO_UI=0)(
 input wire clk,rst,input wire [9:0] x,y,input wire de,
 input wire loading,ascii_allowed,subtitle_enable,audio_warning,
 input wire [3:0] image_fault,subtitle_length,
 input wire [95:0] subtitle_text,input wire [9:0] subtitle_offset,progress,
 input wire [23:0] rgb_in,output wire [23:0] rgb_out,
 input wire basic_mode,timed_mode,input wire [15:0] elapsed_bcd,
 input wire info_visible,home,input wire [4:0] image_id
);
 (* rom_style="bram" *) reg [7:0] font[0:2047];
 initial $readmemh("theme_rom/ascii.hex",font);
 reg [5:0] motion;reg [9:0] amount;reg [15:0] elapsed_frame;reg basic_frame,timed_frame;
 always @(posedge clk or posedge rst)
  if(rst)begin motion<=0;amount<=0;elapsed_frame<=0;basic_frame<=1;timed_frame<=0;end
  else if(x==0&&y==0)begin motion<=motion+1'b1;amount<=progress>480?10'd480:progress;
   elapsed_frame<=elapsed_bcd;basic_frame<=basic_mode;timed_frame<=timed_mode;end
 reg hit,text_on,transparent;reg [23:0] bg,fg;reg [7:0] character;
 reg [3:0] row,col;reg [255:0] line;
 reg [9:0] tx;integer k;
 wire [9:0] width=subtitle_length*10'd18;
 wire [10:0] cycle=11'd640+{1'b0,width};
 wire [10:0] sum={1'b0,x}-11'd16+{1'b0,subtitle_offset};
 wire [10:0] stream=sum>=cycle?sum-cycle:sum;
 always @*begin
  hit=0;text_on=0;transparent=0;bg=24'h142b40;fg=24'hf3f8ff;
  character=32;row=y[3:0];col=x[3:0];line=0;tx=0;
  if(de)begin
   if(DEMO_UI&&!home&&y>=8&&y<24&&x>=432&&x<624)begin
    hit=1;text_on=1;transparent=1;tx=x-432;row=y-8;line="UPTIME 00:00                    ";
    line[199:192]=8'h30+{4'd0,elapsed_frame[15:12]};line[191:184]=8'h30+{4'd0,elapsed_frame[11:8]};
    line[175:168]=8'h30+{4'd0,elapsed_frame[7:4]};line[167:160]=8'h30+{4'd0,elapsed_frame[3:0]};
   end
   if(DEMO_UI&&info_visible&&y>=32&&y<48&&x>=368&&x<624)begin
    hit=1;text_on=1;transparent=1;tx=x-368;
    line={basic_frame?"BASIC48K ":"ADVANCED ",timed_frame?"AUTO 3S":"GUIDE  ",128'd0};
   end
   if(DEMO_UI&&info_visible&&y>=80&&y<96&&x>=16&&x<304)begin
    hit=1;text_on=1;transparent=1;tx=x-16;
    case(image_id[2:0])
     4:line="BMP  800 x 600                  ";
     5:line="BMP 1024 x 768                  ";
     6:line="BMP  800 x 480                  ";
     7:line="BMP  480 x 640                  ";
     default:line="BMP  640 x 480                  ";
    endcase
   end
   if(ascii_allowed&&subtitle_enable&&subtitle_length!=0&&
      ((info_visible&&basic_frame)||subtitle_text!=96'h00524559414c502041475046)&&x>=16&&x<624&&
      y>=(DEMO_UI?372:412)&&y<(DEMO_UI?396:436))begin
    hit=1;transparent=DEMO_UI;
    if(y>=(DEMO_UI?376:416)&&y<(DEMO_UI?392:432)&&stream<width)begin
     row=y-(DEMO_UI?376:416);
     text_on=1;
     for(k=0;k<12;k=k+1)if(stream>=k*18&&stream<k*18+16)begin
      character=subtitle_text[k*8+:8];col=stream-k*18;
     end
    end
   end
   if(loading&&y>=400)begin
    hit=1;text_on=0;transparent=0;
    if(x>=64&&x<576&&y>=416&&y<432)begin text_on=1;line="LOADING - PLEASE WAIT           ";tx=x-64;end
    if(x>=78&&x<562&&y>=448&&y<466)begin
     if(x<80||x>=560||y<450||y>=464)bg=24'he0e0e0;
     else if(x<80+amount)bg=24'h30c878;
     else bg=(x[5:0]-motion)<6'd8 ? 24'h707080 : 24'h202028;
    end
   end
   if(audio_warning&&y>=400)begin
    hit=1;bg=24'h443010;text_on=0;transparent=0;
    if(x>=64&&x<576&&y>=416&&y<432)begin
     text_on=1;line="AUDIO UNAVAILABLE - BROWSE OK    ";tx=x-64;
    end
   end
   if(image_fault!=0)begin
    transparent=0;
    // Clear ordinary title/subtitle regions in every mode, and cover the
    // parameter panel at the center. Controls/recovery continue running.
    if(y<48||y>=400)begin hit=1;bg=24'h301820;text_on=0;end
    if(x>=48&&x<592&&y>=176&&y<272)begin
     hit=1;bg=24'h501820;text_on=0;
     if(x>=64&&x<576&&y>=192&&y<208)begin
      text_on=1;tx=x-64;
      case(image_fault)
       10:line="ERROR 10: FAT32 REQUIRED        ";
       11:line="ERROR 11: NO SUPPORTED IMAGE    ";
       12:line="ERROR 12: IMAGE DATA            ";
       13:line="ERROR 13: FILE CHAIN            ";
       14:line="ERROR 14: SD / CACHE TIMEOUT    ";
       default:line="ERROR 15: MEDIA STATE           ";
      endcase
     end
     if(x>=64&&x<576&&y>=224&&y<240)begin
      text_on=1;tx=x-64;line=DEMO_UI?"HOLD KEY1 2S TO RESET           ":"CHECK TF CARD - KEY1 TO RETRY   ";
     end
    end
   end
  end
  if(line!=0)begin
   character=0;col=tx[3:0];
   for(k=0;k<32;k=k+1)if(tx[8:4]==k)character=line[255-k*8-:8];
  end
 end
 reg [7:0] pixels;reg [2:0] col_q;reg hit_q,text_q,transparent_q;
 reg [23:0] bg_q,fg_q;
 always @(posedge clk)begin
  pixels<=font[{character[7]?7'd32:character[6:0],row}];
  col_q<=col[3:1];hit_q<=hit;text_q<=text_on;bg_q<=bg;fg_q<=fg;transparent_q<=transparent;
 end
 reg [LATENCY-2:0] hits,dim;reg [23:0] colors[0:LATENCY-2];integer j;
 always @(posedge clk or posedge rst)
  if(rst)begin hits<=0;dim<=0;for(j=0;j<LATENCY-1;j=j+1)colors[j]<=0;end
  else begin
   hits<={hits[LATENCY-3:0],hit_q};
   dim<={dim[LATENCY-3:0],transparent_q&&!(text_q&&pixels[7-col_q])};
   colors[0]<=text_q&&pixels[7-col_q]?fg_q:bg_q;
   for(j=1;j<LATENCY-1;j=j+1)colors[j]<=colors[j-1];
  end
 wire [23:0] dimmed={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
 assign rgb_out=hits[LATENCY-2]?(dim[LATENCY-2]?dimmed:colors[LATENCY-2]):rgb_in;
endmodule
