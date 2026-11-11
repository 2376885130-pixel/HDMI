`timescale 1ns/1ps
// One elastic register keeps output stable even if selection changes while
// HDMI is stalled. Unselected tone is DRAINED; unselected WAV is PAUSED.
module pcm_source_select(
 input wire clk,rst_n,use_wav,
 input wire tv,output wire tr,input wire signed[15:0]tl,tt,
 input wire wv,output wire wr,input wire signed[15:0]wl,wt,
 output reg ov,input wire ready,output reg signed[15:0]ol,ot
);
 wire room=!ov||ready;
 assign tr=use_wav?1'b1:room;
 assign wr=use_wav&&room;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ov<=0;ol<=0;ot<=0;end
  else if(room)begin ov<=use_wav?wv:tv;ol<=use_wav?wl:tl;ot<=use_wav?wt:tt;end
 end
endmodule
