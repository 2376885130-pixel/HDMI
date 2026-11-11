`timescale 1ns/1ps
// session_rst_n asserts in BOTH domains on stop/start. Hold low >= 3 clocks
// of each domain; producer waits byte_ready. file_size stable for the session.
// tick comes from the HDMI bridge's single 48kHz cadence. Unselected WAV pauses:
// consumer sets selected=0; upstream eventually backpressures at FIFO full.
module wav_pcm_stream #(parameter ADDR_BITS=10,PREFILL=256)(
 input wire wr_clk,rd_clk,session_rst_n,abort,input wire[31:0]file_size,
 input wire byte_valid,output wire byte_ready,input wire[7:0]byte_data,input wire byte_last,
 input wire tick,selected,input wire[8:0]volume,
 output wire sample_valid,input wire sample_ready,output wire signed[15:0]sample_left,sample_right,
 output reg done,output wire[7:0]error,output wire low_water,
 output reg[31:0]underflows,late_ticks,output reg [31:0] played_frames
);
 reg[2:0]wr_reset,rd_reset;
 always @(posedge wr_clk or negedge session_rst_n)if(!session_rst_n)wr_reset<=0;else wr_reset<={wr_reset[1:0],1'b1};
 always @(posedge rd_clk or negedge session_rst_n)if(!session_rst_n)rd_reset<=0;else rd_reset<={rd_reset[1:0],1'b1};
 wire wrn=wr_reset[2],rdn=rd_reset[2];wire tv,tr,pready,finished;wire[32:0]td,fd;
 wire fv;wire[ADDR_BITS:0]level;
 assign byte_ready=wrn&&pready;
 wav_riff_parser parser(wr_clk,wrn,abort,file_size,byte_valid,pready,byte_data,byte_last,tv,tr,td,error,finished);
 wire pop;pcm_async_fifo #(.ADDR_BITS(ADDR_BITS)) fifo(wr_clk,wrn,tv,tr,td,rd_clk,rdn,fv,pop,fd,level);
 (* async_reg="true",preserve=1,keep=1 *) reg end1,end2;
 reg playing,ending,gain_initialized;reg[8:0]gain;
 reg[31:0]queue[0:7];reg real_sample[0:7];reg[2:0]wp,rp;reg[3:0]count;
 assign sample_valid=rdn&&count!=0;
 assign sample_left=queue[rp][15:0];assign sample_right=queue[rp][31:16];
 wire take=sample_valid&&sample_ready;
 wire slot=count<8||take;
 wire emit=tick&&selected&&!done&&!ending&&slot&&gain_initialized;
 wire pcm=playing&&fv&&!fd[32];
 assign pop=selected&&!ending&&!done&&fv&&((fd[32]&&playing)||(emit&&pcm));
 wire push=emit && !(playing&&fv&&fd[32]);
 wire signed[25:0]mul_l=$signed(fd[15:0])*$signed({1'b0,gain});
 wire signed[25:0]mul_r=$signed(fd[31:16])*$signed({1'b0,gain});
 assign low_water=level<PREFILL;
 always @(posedge rd_clk or negedge rdn)begin
  if(!rdn)begin end1<=0;end2<=0;playing<=0;ending<=0;done<=0;gain<=0;gain_initialized<=0;wp<=0;rp<=0;count<=0;underflows<=0;late_ticks<=0;played_frames<=0;end
  else begin
   end1<=finished;end2<=end1;
   // Retain the user's current volume across file loops, including mute.
   if(!gain_initialized)begin gain<=volume>256?256:volume;gain_initialized<=1;end
   if(!playing&&(level>=PREFILL||end2))playing<=1;
   if(pop&&fd[32])ending<=1;
   if(ending&&count==0)done<=1;
   if(tick&&selected&&!done&&!ending&&!slot)late_ticks<=late_ticks+1'b1;
   if(push)begin
    queue[wp]<=pcm?{mul_r[23:8],mul_l[23:8]}:32'd0;real_sample[wp]<=pcm;wp<=wp+1'b1;
    if(playing&&!fv)underflows<=underflows+1'b1;
    if(gain<(volume>256?256:volume))gain<=gain+1'b1;
    else if(gain>(volume>256?256:volume))gain<=gain-1'b1;
   end
   if(take)begin rp<=rp+1'b1;if(real_sample[rp])played_frames<=played_frames+1'b1;end
   case({push,take})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:count<=count;endcase
  end
 end
endmodule
