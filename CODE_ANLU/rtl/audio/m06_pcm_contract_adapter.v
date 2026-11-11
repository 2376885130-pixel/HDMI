`timescale 1ns/1ps
// Transparent single-clock PCM boundary; monitor only, not a CDC or FIFO.
module m06_pcm_contract_adapter(
 input wire clk,rst_n,source_valid,output wire source_ready,
 input wire signed [15:0] source_left,source_right,
 output wire pcm_valid,input wire pcm_ready,
 output wire signed [15:0] pcm_left,pcm_right,
 output reg contract_error
);
 reg stalled;
 reg signed [15:0] held_left,held_right;
 assign source_ready=pcm_ready;
 assign pcm_valid=source_valid;
 assign pcm_left=source_left;
 assign pcm_right=source_right;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin stalled<=0;held_left<=0;held_right<=0;contract_error<=0;end
  else begin
   // Includes withdrawal of valid and changed data on the accepting edge.
   if(stalled && (!source_valid || source_left!=held_left || source_right!=held_right))
    contract_error<=1;
   stalled<=source_valid && !source_ready;
   if(source_valid && !source_ready)begin held_left<=source_left;held_right<=source_right;end
  end
 end
endmodule
