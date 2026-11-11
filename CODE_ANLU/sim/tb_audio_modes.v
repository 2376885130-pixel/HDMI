`timescale 1ns/1ps
module tb_audio_modes;
 reg clk=0,pc=0,rst=1,basic=0,en=0;reg [4:0] id=31;
 always #10 clk=~clk;always #20 pc=~pc;
 wire req,finished,selected,sv,playing,sbasic;wire [4:0]sid;wire [31:0]lba,frames;wire[127:0]diag;
 wire signed[15:0]sl,sr;reg busy=0,v=0,d=0;reg[7:0]data=0;reg tick=0;integer divider=0;
 always @(posedge pc)begin tick<=divider==520;divider<=divider==520?0:divider+1;end
 theme_audio_player dut(.clk(clk),.pixel_clk(pc),.rst(rst),.pixel_rst(rst),.mounted(1'b1),.play_enable(en),
 .play_id(id),.basic_mode(basic),.session_basic(sbasic),.root_cluster(32'd2),.fat_lba(32'd10),.data_lba(32'd100),.max_cluster(32'd1000),
 .cluster_shift(4'd0),.sectors_per_cluster(8'd1),.req(req),.lba(lba),.busy(busy),.valid(v),.done(d),.data(data),.error(8'd0),
 .tick(tick),.volume(9'd256),.selected(selected),.sample_valid(sv),.sample_ready(1'b1),.sample_left(sl),.sample_right(sr),
 .diagnostics(diag),.finished(finished),.session_id(sid),.played_frames(frames),.playing_video(playing));
 reg [31:0]addr;integer pos=0,phase=0,basic_reads=0,guide_reads=0,raw_frames=0,mode_changes=0;
 function[7:0]payload(input[31:0]a,input integer i);
  reg [87:0]name;reg[15:0]sample;integer n;
  begin
   payload=0;name=i<32?"BASIC48 WAV":"T1P01   WAV";
   if(a==100)begin
    if(i<64)case(i%32)
     0,1,2,3,4,5,6,7,8,9,10:payload=name>>((10-i%32)*8);
     11:payload=8'h20;26:payload=i<32?3:4;28:payload=8'h2c;29:payload=1;
    endcase
   end else if(a==101||a==102)begin
    case(i)
     0:payload="R";1:payload="I";2,3:payload="F";4:payload=8'h24;5:payload=1;
     8:payload="W";9:payload="A";10:payload="V";11:payload="E";
     12:payload="f";13:payload="m";14:payload="t";15:payload=32;16:payload=16;
     20:payload=1;22:payload=2;24:payload=8'h80;25:payload=8'hbb;
     28:payload=0;29:payload=8'hee;30:payload=2;32:payload=4;34:payload=16;
     36:payload="d";37:payload="a";38:payload="t";39:payload="a";41:payload=1;
     default:if(i>=44&&i<300)begin
      n=(i-44)/4;sample=(a==101?16'h1100:16'h2200)+n;
      payload=i[0]?sample[15:8]:sample[7:0];
     end
    endcase
   end
  end
 endfunction
 always @(negedge clk)begin
  v=0;d=0;
  if(rst)begin busy=0;pos=0;phase=0;end
  else if(req&&!busy)begin busy=1;addr=lba;pos=0;phase=0;
   if(lba==101)basic_reads=basic_reads+1;if(lba==102)guide_reads=guide_reads+1;
  end else if(busy)begin
   phase=phase+1;
   if(phase==2)begin phase=0;v=1;data=payload(addr,pos);pos=pos+1;
    if(pos==512)begin d=1;busy=0;end
   end
  end
 end
 reg[15:0]expected;integer sample_no=0;
 always @(posedge clk)begin
  if(!dut.pcm.wrn)sample_no=0;
  else if(dut.pcm.tv&&dut.pcm.tr&&!dut.pcm.td[32])begin
   expected=(sbasic?16'h1100:16'h2200)+sample_no;
   if(dut.pcm.td[31:0]!=={expected,expected})$fatal(1,"wrong session PCM");
   sample_no=sample_no+1;raw_frames=raw_frames+1;
  end
  if(sbasic&&finished)$fatal(1,"base demo advanced picture");
 end
 initial begin
  #101;rst=0;en=1;
  wait(diag[7:0]==8'h10);wait(dut.state==6);
  @(negedge clk);basic=1;
  wait(sbasic&&playing);wait(basic_reads>=2);
  // Switch while a sector is accepted, including a quick reversal.
  @(negedge clk);id=0;basic=0;
  wait(guide_reads==1&&busy);@(negedge clk);basic=1;
  repeat(7)@(negedge clk);basic=0;
  wait(!sbasic&&finished);
  en=0;wait(dut.state==0);basic=1;en=1;
  wait(sbasic&&playing);wait(raw_frames>200);
  rst=1;repeat(8)@(negedge clk);rst=0;wait(sbasic&&playing);
  $display("PASS audio modes: missing narration->base recovery, base loop/no next event, mode change during accepted sector, rapid reversal, SW1 stop/restart and reset; PCM=%d",raw_frames);$finish;
 end
 initial begin #100000000;$fatal(1,"audio mode timeout state=%d fs=%h",dut.state,diag[7:0]);end
endmodule
