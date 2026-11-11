// Match the existing video_delay's 21-stage HS/VS/DE pipeline.
module video_audio_coordinates #(parameter LATENCY=21)(
 input wire clk,rst,input wire[9:0] x,y,
 output wire[9:0] aligned_x,output wire active_line
);
 reg[9:0] x_pipe[0:LATENCY-1];reg[LATENCY-1:0] line_pipe;
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin for(i=0;i<LATENCY;i=i+1)x_pipe[i]<=0;line_pipe<=0;end
  else begin
   x_pipe[0]<=x;for(i=1;i<LATENCY;i=i+1)x_pipe[i]<=x_pipe[i-1];
   line_pipe<={line_pipe[LATENCY-2:0],y<480};
  end
 end
 assign aligned_x=x_pipe[LATENCY-1];assign active_line=line_pipe[LATENCY-1];
endmodule
