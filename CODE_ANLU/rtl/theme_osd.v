// Synchronous packed ROMs. Overlay is delayed exactly 24 pixel clocks to
// match the accepted image path; no asynchronous large combinational font.
module theme_osd #(parameter INFO_FRAMES=180)(
 input wire clk,rst,input wire [9:0] x,y,input wire home,
 input wire [1:0] theme,input wire [4:0] image_id,input wire [7:0] hold_progress,
 input wire playing,loading,preview,input wire [3:0] load_status,input wire audio_error,
 input wire [31:0] played_frames,input wire [23:0] image_rgb,
 output wire [23:0] rgb,
 input wire basic_mode,timed_mode,input wire present_commit,output wire info_visible
);
 (* rom_style="bram" *) reg [15:0] glyph_low[0:8191];
 (* rom_style="bram" *) reg [15:0] glyph_high[0:1023];
 (* rom_style="bram" *) reg [9:0] text_rom[0:4095];
 (* rom_style="bram" *) reg [9:0] ui_rom[0:1023];
 (* rom_style="bram" *) reg [5:0] covers[0:8191];
 (* rom_style="bram" *) reg [23:0] palette[0:255];reg [31:0] cues[0:127];
 initial begin
  $readmemh("theme_rom/glyph_low.hex",glyph_low);
  $readmemh("theme_rom/glyph_high.hex",glyph_high);
  $readmemh("theme_rom/text.hex",text_rom);
  $readmemh("theme_rom/ui.hex",ui_rom);
  $readmemh("theme_rom/cover.hex",covers);
  $readmemh("theme_rom/palette.hex",palette);
  $readmemh("theme_rom/cue.hex",cues);
 end
 reg [1:0] cue,cue_wait;reg [4:0] last_id;reg [31:0] cue_end;
 always @(posedge clk)cue_end<=cues[{image_id,cue}];
 always @(posedge clk or posedge rst)
  if(rst)begin cue<=0;last_id<=0;cue_wait<=2;end
  else begin
   last_id<=image_id;
   if(!playing||last_id!=image_id)begin cue<=0;cue_wait<=2;end
   else if(cue_wait!=0)cue_wait<=cue_wait-1'b1;
   else if(played_frames>=cue_end&&cue<3)begin cue<=cue+1'b1;cue_wait<=2;end
  end
 reg hf,pf,playf,loadf,errf;reg [1:0] tf,cf;reg [4:0] idf;reg [7:0] progressf;
 reg [7:0] info_count;reg basicf,timedf,commit_pending;
 assign info_visible=!hf&&!pf&&info_count!=0;
 always @(posedge clk or posedge rst)
  if(rst)begin info_count<=0;basicf<=1;timedf<=0;commit_pending<=0;end
  else begin
   if(present_commit)commit_pending<=1;
   if(x==0&&y==0)begin
    basicf<=basic_mode;timedf<=timed_mode;
    if(!home&&(hf||image_id!=idf||basic_mode!=basicf||timed_mode!=timedf||commit_pending))info_count<=INFO_FRAMES;
    else if(info_count!=0&&!loading)info_count<=info_count-1'b1;
    commit_pending<=0;
   end
  end
 always @(posedge clk or posedge rst)
  if(rst)begin hf<=1;pf<=0;playf<=0;loadf<=1;errf<=0;tf<=0;idf<=0;cf<=0;progressf<=0;end
  else if(x==0&&y==0)begin
   hf<=home;pf<=preview;tf<=theme;idf<=image_id;cf<=cue;playf<=playing;
   loadf<=loading;errf<=audio_error||load_status>=10;progressf<=hold_progress;
  end
 reg text_enable,text_is_ui;reg [9:0] ui_addr;reg [11:0] text_addr;
 reg [3:0] gx,gy;reg [23:0] back;reg cover_enable;
 reg [12:0] cover_addr;reg overlay_enable,transparent;
 wire right_tile=x>=320,bottom_tile=y>=240;
 wire [1:0] tile={bottom_tile,right_tile};
 wire [9:0] tile_x=right_tile?352:32,tile_y=bottom_tile?256:64;
 wire inside_cover=x>=tile_x&&x<tile_x+256&&y>=tile_y&&y<tile_y+160;
 wire inside_border=x>=tile_x-3&&x<tile_x+259&&y>=tile_y-3&&y<tile_y+163;
 wire [9:0] local_x=x-tile_x,local_y=y-tile_y;
 wire [9:0] cover_row=local_y/5;
 // Numbers use a tiny segment font to avoid arbitrary Unicode indexing logic.
 reg [3:0] digit;reg number_enable;reg [3:0] nx,ny;
 function number_bit;input [3:0] n,cx,cy;reg [6:0] s;begin
  case(n)0:s=7'b1111110;1:s=7'b0110000;2:s=7'b1101101;3:s=7'b1111001;
   4:s=7'b0110011;5:s=7'b1011011;6:s=7'b1011111;7:s=7'b1110000;
   8:s=7'b1111111;9:s=7'b1111011;default:s=0;endcase
  number_bit=(s[6]&&cy==0&&cx>0&&cx<6)||(s[5]&&cx==6&&cy<6&&cy>0)||
   (s[4]&&cx==6&&cy>6&&cy<12)||(s[3]&&cy==12&&cx>0&&cx<6)||
   (s[2]&&cx==0&&cy>6&&cy<12)||(s[1]&&cx==0&&cy>0&&cy<6)||
   (s[0]&&cy==6&&cx>0&&cx<6);
 end endfunction
 always @*begin
  text_enable=0;text_is_ui=1;ui_addr=0;text_addr=0;gx=0;gy=0;
  back=24'h142b40;cover_enable=0;cover_addr=0;overlay_enable=hf;transparent=0;
  digit=15;number_enable=0;nx=0;ny=0;
  if(hf)begin
   if(inside_border&&tile==tf)back=24'h50e2c0;
   if(inside_cover)begin
    cover_enable=1;cover_addr={bottom_tile,cover_row[4:0],right_tile,local_x[7:2]};
   end
   if(y>=20&&y<36&&x>=32&&x<288)begin
    text_enable=1;ui_addr=5*32+((x-32)>>4);gx=(x-32)&15;gy=y-20;
   end
   if(y>=tile_y+164&&y<tile_y+180&&x>=tile_x&&x<tile_x+256)begin
    text_enable=1;ui_addr={tile,5'd0}+((x-tile_x)>>4);gx=(x-tile_x)&15;gy=y-(tile_y+164);
   end
   if(y>=452&&y<468&&x>=32&&x<288)begin text_enable=1;ui_addr=6*32+((x-32)>>4);gx=(x-32)&15;gy=y-452;end
   if(y>=452&&y<468&&x>=336&&x<624)begin text_enable=1;ui_addr=7*32+((x-336)>>4);gx=(x-336)&15;gy=y-452;end
   if(y>=472&&y<476&&x<({2'd0,progressf}<<1))back=24'h50e2c0;
  end else if(!pf)begin
   if(info_visible&&x>=16&&x<304&&y>=16&&y<78)begin
    overlay_enable=1;transparent=1;
    if(x<20)begin back=24'h45c7ed;transparent=0;end
    if(y>=24&&y<40&&x>=32&&x<288)begin text_enable=1;ui_addr={tf,5'd0}+((x-32)>>4);gx=(x-32)&15;gy=y-24;end
    if(y>=52&&y<68&&x>=32&&x<64)begin text_enable=1;ui_addr=9*32+((x-32)>>4);gx=(x-32)&15;gy=y-52;end
    if(y>=52&&y<68&&x>=176&&x<208)begin text_enable=1;ui_addr=10*32+((x-176)>>4);gx=(x-176)&15;gy=y-52;end
    if(y>=52&&y<65)begin
     ny=y-52;
     if(x>=80&&x<88)begin number_enable=1;digit={2'd0,tf}+1'b1;nx=x-80;end
     if(x>=112&&x<120)begin number_enable=1;digit=4;nx=x-112;end
     if(x>=224&&x<232)begin number_enable=1;digit={1'b0,idf[2:0]}+1'b1;nx=x-224;end
     if(x>=256&&x<264)begin number_enable=1;digit=8;nx=x-256;end
     if(x==100||x==244)begin transparent=0;back=24'h6bcfbd;end
    end
   end
   // Two lines, sixteen CJK glyphs each. Only the live narration has a band.
   if(y>=396&&y<440&&x>=168&&x<456&&playf&&!errf)begin
    overlay_enable=1;transparent=1;
    if(((y>=400&&y<416)||(y>=420&&y<436))&&x>=184&&x<440)begin
     text_enable=1;text_is_ui=0;
     text_addr={idf,cf,5'd0}+((x-184)>>4)+(y>=420?16:0);
     gx=(x-184)&15;gy=y>=420?y-420:y-400;
    end
   end
   if(progressf!=0&&y>=440&&y<444&&x<({2'd0,progressf}<<1))begin overlay_enable=1;back=24'h50e2c0;end
  end
 end
 reg [9:0] text_q,ui_q,char_q;reg [3:0] gx1,gx2,gx3,gy1,gy2;
 reg en1,en2,en3,which1,glyph_bank;reg [15:0] row_low,row_high;
 wire [15:0] row_q=glyph_bank?row_high:row_low;
 reg [5:0] cover_q;reg [1:0] tile_q;reg [23:0] cover_rgb1,cover_rgb2;
 reg cover1,cover2,cover3;reg [23:0] bg1,bg2,bg3;
 reg n1,n2,n3,oe1,oe2,oe3,tr1,tr2,tr3;
 always @(posedge clk)begin
  text_q<=text_rom[text_addr];ui_q<=ui_rom[ui_addr];which1<=text_is_ui;
  gx1<=gx;gy1<=gy;en1<=text_enable;
  char_q<=which1?ui_q:text_q;gx2<=gx1;gy2<=gy1;en2<=en1;
  row_low<=glyph_low[{char_q[8:0],gy2}];row_high<=glyph_high[{char_q[5:0],gy2}];glyph_bank<=char_q[9];gx3<=gx2;en3<=en2;
  cover_q<=covers[cover_addr];tile_q<=tile;cover_rgb1<=palette[{tile_q,cover_q}];cover_rgb2<=cover_rgb1;
  cover1<=cover_enable;cover2<=cover1;cover3<=cover2;
  bg1<=back;bg2<=bg1;bg3<=bg2;
  oe1<=overlay_enable;oe2<=oe1;oe3<=oe2;
  tr1<=transparent;tr2<=tr1;tr3<=tr2;
  n1<=number_enable&&number_bit(digit,nx,ny);n2<=n1;n3<=n2;
 end
 reg [23:0] color_pipe[0:20];reg [20:0] enable_pipe,dim_pipe;
 integer k;
 always @(posedge clk or posedge rst)begin
  if(rst)begin enable_pipe<=0;dim_pipe<=0;for(k=0;k<21;k=k+1)color_pipe[k]<=0;end
  else begin
   enable_pipe<={enable_pipe[19:0],oe3};
   dim_pipe<={dim_pipe[19:0],tr3&&!((en3&&row_q[15-gx3])||n3)};
   color_pipe[0]<=((en3&&row_q[15-gx3])||n3)?24'hf3f8ff:cover3?cover_rgb2:bg3;
   for(k=1;k<21;k=k+1)color_pipe[k]<=color_pipe[k-1];
  end
 end
 wire [23:0] dimmed={1'b0,image_rgb[23:17],1'b0,image_rgb[15:9],1'b0,image_rgb[7:1]};
 assign rgb=enable_pipe[20]?(dim_pipe[20]?dimmed:color_pipe[20]):image_rgb;
endmodule
