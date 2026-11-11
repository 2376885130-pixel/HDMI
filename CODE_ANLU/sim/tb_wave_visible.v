`timescale 1ns/1ps
module tb_wave_visible;
 reg clk=0,rn=0,vs=1,de=0,en=1,tap=0;always #5 clk=~clk;
 reg [9:0] x=0,y=0;reg signed[15:0] pcm=0;wire [23:0] rgb;wire active;
 promax_audio_waveform #(.DISPLAY_GAIN(4),.EXPLICIT_Y(1),.WAVE_X(368),.WAVE_Y(448),.WAVE_WIDTH(256),.WAVE_HEIGHT(32),.DECIMATE(2),.STALE_FRAMES(3)) dut(
 .clk(clk),.rst_n(rn),.vsync(vs),.de(de),.rgb_in(24'h123456),.pixel_x(x),.pixel_y(y),
 .enable(en),.pcm_tap_valid(tap),.pcm_tap_left(pcm),.rgb_out(rgb),.waveform_active(active));
 task frame;begin @(negedge clk);vs=0;repeat(2)@(negedge clk);vs=1;end endtask
 task sample(input signed[15:0] v);begin @(negedge clk);tap=1;pcm=v;@(negedge clk);tap=0;end endtask
 integer i,j,bars=0,fd;reg saved;
 initial begin
  repeat(4)@(negedge clk);rn=1;
  for(i=0;i<64;i=i+1)sample(i%2?-32768:16384);
  saved=dut.display_bank;repeat(10)@(negedge clk);if(saved!=dut.display_bank)$fatal(1,"tearing waveform bank");
  frame;if(!dut.display_valid||dut.display_peak!=255)$fatal(1,"saturating display gain");
  fd=$fopen("wave_visible.ppm","wb");$fwrite(fd,"P6\n640 480\n255\n");
  for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
   @(negedge clk);x=i;y=j;de=1;#1;
   if(dut.bar_pixel)bars=bars+1;
   if(active&&(y<448||y>=480||x<368||x>=640))$fatal(1,"wave escaped bounds");
   if(!active&&rgb!==24'h123456)$fatal(1,"wave pass through");
   $fwrite(fd,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
   de=0;#1;if(active||rgb!==24'h123456)$fatal(1,"wave blanking");de=1;
  end
  $fclose(fd);if(bars<5000)$fatal(1,"wave invisible");
  @(negedge clk);en=0;repeat(3)@(negedge clk);if(dut.display_valid||active)$fatal(1,"mute history clear");
  en=1;for(i=0;i<64;i=i+1)sample(0);frame;
  x=400;y=464;de=1;#1;if(rgb!==24'h406060)$fatal(1,"silence axis");
  repeat(4)frame;if(dut.display_valid)$fatal(1,"stale waveform");
  $display("PASS PCM waveform full-raster visibility, saturating -32768, silence, stale timeout, bank stability and pixel confinement bars=%0d",bars);$finish;
 end
endmodule
