`timescale 1ns/1ps
module tb_display_osd;
 reg clk=0,rst=1;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg home=1,basic=1,timed=0,commit=0,playing=0,preview=0;
 reg [4:0] id=0;reg [23:0] src=24'h80a0c0;wire [23:0] rgb;wire visible;
 theme_osd #(.INFO_FRAMES(3)) dut(.clk(clk),.rst(rst),.x(x),.y(y),.home(home),.theme(2'd0),.image_id(id),.hold_progress(8'd0),
  .playing(playing),.loading(1'b0),.preview(preview),.load_status(4'd0),.audio_error(1'b0),.played_frames(32'd0),.image_rgb(src),.rgb(rgb),
  .basic_mode(basic),.timed_mode(timed),.present_commit(commit),.info_visible(visible));
 task frame;begin @(negedge clk);x=0;y=0;@(negedge clk);x=639;y=479;end endtask
 task pixel(input integer px,py,input [23:0] expected);
  begin @(negedge clk);x=px;y=py;repeat(30)@(negedge clk);if(rgb!==expected)$fatal(1,"OSD pixel %d %d exp=%h got=%h",px,py,expected,rgb);end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;frame;home=0;frame;if(!visible)$fatal(1,"entry info absent");
  pixel(24,20,24'h405060);pixel(600,300,src);
  frame;frame;frame;if(visible)$fatal(1,"info failed to hide");pixel(24,20,src);
  id=1;frame;if(!visible)$fatal(1,"image change info absent");frame;frame;frame;
  basic=0;frame;if(!visible)$fatal(1,"mode info absent");
  playing=1;frame;pixel(172,398,24'h405060);playing=0;frame;pixel(172,398,src);
  preview=1;frame;pixel(24,20,src);preview=0;
  rst=1;repeat(2)@(negedge clk);if(visible)$fatal(1,"reset failed");
  $display("PASS display OSD: entry/image/mode events, timed hide, exact 50-percent blend, narration-only band, preview and reset");$finish;
 end
endmodule
