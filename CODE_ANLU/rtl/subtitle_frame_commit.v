// Four-phase bundled-data transfer, acknowledged only at a frame boundary.
// Source is a live configuration register: edits while busy coalesce, and the
// final value is sent when this transaction retires. No toggles can cancel.
module subtitle_frame_commit(
 input wire src_clk,src_rst_n,input wire [95:0] src_text,
 input wire [3:0] src_length,input wire src_enable,
 input wire dst_clk,dst_rst_n,frame_start,
 output reg [95:0] dst_text,output reg [3:0] dst_length,
 output reg dst_enable,output reg changed
);
 reg [100:0] held;reg req,ack;
 (* preserve=1,keep=1 *) reg [1:0] req_sync,ack_sync;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin held<=0;req<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(!req && !ack_sync[1])begin held<={src_text,src_length,src_enable};req<=1;end
   else if(req && ack_sync[1])req<=0;
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin req_sync<=0;ack<=0;dst_text<=0;dst_length<=0;dst_enable<=0;changed<=0;end
  else begin
   req_sync<={req_sync[0],req};changed<=0;
   if(frame_start && req_sync[1] && !ack)begin
    changed<=({dst_text,dst_length,dst_enable}!=held);
    {dst_text,dst_length,dst_enable}<=held;ack<=1;
   end else if(!req_sync[1])ack<=0;
  end
 end
endmodule
