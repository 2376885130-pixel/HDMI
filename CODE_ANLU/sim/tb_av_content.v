`timescale 1ns/1ps
module tb_av_content;
 reg clk=0,rn=1,k2=1,k3=1,k4=1,sw3=1,sw4=1;reg[1:0]sw=3;
 reg serial_rx=1;wire serial_tx;
 always #10 clk=~clk;
 tf_image_top dut(.sys_clk(clk),.sys_rst_n(rn),.key_next_n(k2),.key_prev_n(k3),.key_auto_n(k4),
  .interval_switch(sw),.direction_switch(sw3),.parameter_switch(sw4),.sd_miso(1'b1),.uart_rx(serial_rx),.uart_tx(serial_tx));
 wire [7:0] serial_out;wire serial_valid,serial_bad;integer serial_lines=0;
 uart_rx_byte #(.CLKS_PER_BIT(434)) serial_monitor(clk,dut.control_reset_n,serial_tx,serial_out,serial_valid,serial_bad);
 always @(posedge clk)if(dut.control_reset_n)begin
  if(serial_bad)$fatal(1,"UART TX framing during AV");
  if(serial_valid&&serial_out==10)serial_lines=serial_lines+1;
 end
 integer frames=0,taps=0,nonzero=0,checked=0,check_total=0,pcm_checked=0,pcm_total=0;
 integer mode_tests=0,base_taps=0,wave_pixels=0;
 reg check=0;reg [23:0] reference[0:614399];
 reg [31:0] basic_pcm[0:16383],guide_pcm[0:32767];
 initial begin
  $readmemh("media/av_reference.hex",reference);
  $readmemh("media/basic_pcm.hex",basic_pcm);$readmemh("media/guide_pcm.hex",guide_pcm);
 end
 // Check decoded sample content, not just a nonzero audio/status flag.
 always @(posedge dut.sd_clk)begin
  if(!dut.u_bgm.pcm.wrn)pcm_checked=0;
  else if(dut.u_bgm.pcm.tv&&dut.u_bgm.pcm.tr)begin
   if(pcm_checked<16384)begin
    if(dut.u_bgm.pcm.td[31:0] !== (dut.u_bgm.session_basic ? basic_pcm[pcm_checked] : guide_pcm[dut.u_bgm.session_id[0]*16384+pcm_checked]))
      $fatal(1,"PCM mismatch basic=%b id=%d frame=%d",dut.u_bgm.session_basic,dut.u_bgm.session_id,pcm_checked);
    pcm_total=pcm_total+1;
   end
   pcm_checked=pcm_checked+1;
  end
 end
 always @(posedge dut.pixel_clk)if(!dut.video_rst)begin
  if(dut.x==0&&dut.y==0)frames=frames+1;
  if(dut.pcm_tap_valid)begin taps=taps+1;if(dut.pcm_tap_left!=0)nonzero=nonzero+1;end
  if(check&&dut.delayed_de&&dut.transition_x<640&&dut.transition_y<480)begin
   if(dut.image_rgb!==reference[dut.displayed_index_video*307200+dut.transition_y*640+dut.transition_x])
    $fatal(1,"PIXEL MISMATCH image=%d x=%0d y=%0d",dut.displayed_index_video,dut.transition_x,dut.transition_y);
   checked=checked+1;check_total=check_total+1;if(checked==307200)check=0;
  end
  if(dut.u_waveform.bar_pixel)wave_pixels=wave_pixels+1;
  if(dut.memory_fault||dut.read_underflow)$fatal(1,"frame memory fault");
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task uart_byte(input [7:0] b);integer j;begin
  serial_rx=0;cycles(434);for(j=0;j<8;j=j+1)begin serial_rx=b[j];cycles(434);end serial_rx=1;cycles(434);
 end endtask
 task uart_command(input [7:0] a,b);begin
  uart_byte(a);uart_byte(b);uart_byte(13);uart_byte(10);cycles(60000);
 end endtask
 task capture;
  begin
   checked=0;wait(dut.transition_x==0&&dut.transition_y==0);check=1;
   wait(checked==307200);$display("PASS actual-volume BMP 307200 pixel identity image=%0d",dut.displayed_index_video);
  end
 endtask
 task mode(input reg basic);
  begin
   rn=0;cycles(40);rn=1;cycles(40);
   wait(dut.basic_video==basic);
   wait(dut.narration_basic==basic&&dut.narration_playing&&pcm_checked>2048);
   if(dut.displayed_index_video!=dut.image_index)$fatal(1,"mode changed image");
   mode_tests=mode_tests+1;
   $display("PASS mode %b filename=%s decoded=%d",basic,dut.u_bgm.filename,pcm_checked);
  end
 endtask
 initial begin
  wait(dut.show_image);cycles(100);
  uart_command("T","2");if(dut.theme_id!=1||!dut.theme_home)$fatal(1,"UART home theme select");
  uart_command("T","1");if(dut.theme_id!=0)$fatal(1,"UART restore theme");
  k3=0;cycles(2050);k3=1;
  wait(!dut.theme_home&&dut.transaction_presented);
  capture;
  sw[0]=0;wait(dut.narration_playing&&nonzero>200&&pcm_checked>2048);
  if(!dut.narration_basic||dut.u_bgm.filename!="BASIC48 WAV")$fatal(1,"wrong base audio");
  mode(0);capture;mode(1);
  sw[0]=1;wait(!dut.narration_playing);cycles(100);sw[0]=0;
  wait(dut.narration_playing&&pcm_checked>2048);mode(0);
  // Real serial RX in parallel with actual BMP/WAV, not hierarchical force.
  base_taps=taps;uart_command("M","1");if(!dut.demo_active)$fatal(1,"UART demo entry");
  uart_command("T","4");if(dut.theme_id!=0)$fatal(1,"UART context corruption");
  k3=0;cycles(40);k3=1;cycles(40);
  if(dut.demo_state_sys[58:52]!=35)$fatal(1,"UART demo key route");
  uart_command("M","0");
  if(dut.demo_active||!dut.narration_playing||taps-base_taps<100||dut.image_index!=0)$fatal(1,"UART interrupted AV");
  // SW3+SW4 experiment must not steal SW1 or restart the main narration.
  sw3=0;sw4=0;wait(dut.demo_active);base_taps=taps;
  k4=0;cycles(40);k4=1;cycles(40);k3=0;cycles(40);k3=1;
  repeat(2)begin wait(dut.x==1&&dut.y==0);wait(dut.x==2&&dut.y==0);end
  if(!dut.narration_playing||taps-base_taps<1000||dut.image_index!=0)$fatal(1,"experiment interrupted audio");
  sw3=1;sw4=1;cycles(100);
  k2=0;cycles(1100000);k2=1;cycles(1100000);
  wait(dut.image_index==1&&dut.transaction_presented&&!dut.transition_busy&&dut.narration_playing&&pcm_checked>2048);
  capture;mode(1);capture;
  if(wave_pixels==0||pcm_total<10000)$fatal(1,"PCM/waveform not exercised");
  rn=0;cycles(240);if(dut.system_reset_n)$fatal(1,"long reset missing");rn=1;
  wait(dut.show_image&&dut.theme_home);cycles(100);
  if(dut.preview_fault_sd[32])$fatal(1,"reset remount failed");
  $display("PASS mode/SW1/demo/manual/reset: modes=%0d pixels=%0d exact_PCM=%0d waveform=%0d",mode_tests,check_total,pcm_total,wave_pixels);
  if(serial_lines<10)$fatal(1,"UART events/replies not exercised");
  $display("PASS UART/AV concurrent events and controls lines=%0d",serial_lines);
  $display("PASS actual-volume WAV lookup and nonzero HDMI PCM: taps=%0d nonzero=%0d",taps,nonzero);
  $finish;
 end
 always @(posedge dut.sd_clk)if(!dut.sd_rst)begin
  if(dut.loader_status>=10)$fatal(1,"image status=%d",dut.loader_status);
  if(dut.audio_diag_sd[7:0]>=16)$fatal(1,"audio lookup=%h filename=%s lba=%d",dut.audio_diag_sd[7:0],dut.u_bgm.filename,dut.u_bgm.lba);
 end
 always #100000000 $display("PROGRESS frames=%0d image=%d fs=%h taps=%d",frames,dut.loader_status,dut.audio_diag_sd[7:0],taps);
 initial begin #(64'd6000000000);$fatal(1,"AV content timeout");end
endmodule
