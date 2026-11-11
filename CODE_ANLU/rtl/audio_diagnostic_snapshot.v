// Four-phase bundled-data transfer. Falling-edge destination capture gives a
// physical half-cycle hold margin relative to the PLL-related source edge.
module audio_diagnostic_snapshot(
 input wire src_clk,src_rst_n,input wire[127:0]src_data,
 input wire dst_clk,dst_rst_n,output reg[127:0]dst_data
);
 (* preserve=1,keep=1 *) reg[127:0]held;
 reg request,ack;
 (* preserve=1,keep=1,async_reg="true" *) reg[1:0]as,rs;
 always @(posedge src_clk or negedge src_rst_n)begin
  if(!src_rst_n)begin held<=0;request<=0;as<=0;end
  else begin
   as<={as[0],ack};
   if(!request&&!as[1])begin held<=src_data;request<=1;end
   else if(request&&as[1])request<=0;
  end
 end
 always @(negedge dst_clk or negedge dst_rst_n)begin
  if(!dst_rst_n)begin dst_data<=0;ack<=0;rs<=0;end
  else begin
   rs<={rs[0],request};
   if(rs[1]&&!ack)begin dst_data<=held;ack<=1;end
   else if(!rs[1])ack<=0;
  end
 end
endmodule
