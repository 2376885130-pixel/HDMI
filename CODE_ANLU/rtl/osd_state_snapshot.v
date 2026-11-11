// Four-phase bundled-data mailbox. Source holds the entire payload until ack.
// Continuous snapshots converge to the latest state, including after either
// domain resets independently. Consumers latch dst_data at their frame boundary.
module osd_state_snapshot #(parameter WIDTH=32)(
 input wire src_clk,src_rst_n,input wire [WIDTH-1:0] src_data,
 input wire dst_clk,dst_rst_n,output reg [WIDTH-1:0] dst_data
);
 reg [WIDTH-1:0] held;
 reg request,ack;
 (* preserve=1,keep=1 *) reg [1:0] ack_sync,request_sync;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin held<=0;request<=0;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],ack};
   if(!request && !ack_sync[1])begin held<=src_data;request<=1;end
   else if(request && ack_sync[1])request<=0;
  end
 end
 always @(posedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin dst_data<=0;ack<=0;request_sync<=0;end
  else begin
   request_sync<={request_sync[0],request};
   if(request_sync[1] && !ack)begin dst_data<=held;ack<=1;end
   else if(!request_sync[1])ack<=0;
  end
 end
endmodule
