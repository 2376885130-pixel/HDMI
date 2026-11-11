`timescale 1ns/1ps
// One stream clock for speech and silence. Source data is available a few
// clocks after tick; delay the capture, never the 48kHz sample cadence.
// No reset, oscillator restart or picture-commit input exists at a cut.
module pcm_continuous_output(
 input wire clk,rst_n,tick,selected,source_valid,
 output wire source_ready,input wire signed[15:0]source_left,source_right,
 output wire sample_valid,input wire sample_ready,
 output wire signed[15:0]sample_left,sample_right,output reg overflow
);
 reg[2:0]tick_pipe;
 reg[31:0]queue[0:7];reg[2:0]wp,rp;reg[3:0]count;
 reg signed[15:0]last_left,last_right;
 reg[8:0]gain;
 wire take=sample_valid&&sample_ready;
 wire room=count<8||take;
 wire push=tick_pipe[2]&&room;
 wire real_pcm=selected&&source_valid;
 assign source_ready=push&&selected;
 assign sample_valid=count!=0;
 assign sample_left=queue[rp][15:0];assign sample_right=queue[rp][31:16];
 wire signed[25:0]scaled_left=$signed(source_left)*$signed({1'b0,gain});
 wire signed[25:0]scaled_right=$signed(source_right)*$signed({1'b0,gain});
 // Bounded tail suppresses a hard nonzero-to-zero step on manual cancellation
 // and temporary underrun. No old session FIFO data is fetched after stop.
 function signed[15:0] decay(input signed[15:0]v);
 begin decay=(v<32&&v> -32)?16'sd0:v-(v>>>5);end endfunction
 wire signed[15:0]next_left=real_pcm?scaled_left[23:8]:decay(last_left);
 wire signed[15:0]next_right=real_pcm?scaled_right[23:8]:decay(last_right);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tick_pipe<=0;wp<=0;rp<=0;count<=0;last_left<=0;last_right<=0;gain<=0;overflow<=0;end
  else begin
   tick_pipe<={tick_pipe[1:0],tick};
   if(tick_pipe[2]&&!room)overflow<=1;
   if(push)begin
    queue[wp]<={next_right,next_left};wp<=wp+1'b1;last_left<=next_left;last_right<=next_right;
    if(!real_pcm)gain<=0;else if(gain<256)gain<=gain+1'b1;
   end
   if(take)rp<=rp+1'b1;
   case({push,take})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:count<=count;endcase
  end
 end
endmodule
