// Align both coordinates with the unchanged 21-clock video_delay RGB stream.
// Effect progress updates in source blanking, before these visible pixels arrive.
module video_transition_coordinates #(parameter LATENCY=21)(input wire clk,rst,input wire [9:0] x,y,
 output wire [9:0] aligned_x,aligned_y);
 reg [9:0] xp[0:LATENCY-1],yp[0:LATENCY-1];integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin for(i=0;i<LATENCY;i=i+1)begin xp[i]<=0;yp[i]<=0;end end
  else begin
   xp[0]<=x;yp[0]<=y;
   for(i=1;i<LATENCY;i=i+1)begin xp[i]<=xp[i-1];yp[i]<=yp[i-1];end
  end
 end
 assign aligned_x=xp[LATENCY-1];assign aligned_y=yp[LATENCY-1];
endmodule
