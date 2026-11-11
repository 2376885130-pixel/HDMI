// Per-image reset is requested for many memory clocks (startup settling time).
// Sample that request in the memory domain; only power/PLL loss asserts reset
// asynchronously. Runtime release never drives a memory-domain async SR pin.
module memory_load_reset(
 input wire clk,power_ready,load_enable,
 output wire rst
);
 (* preserve=1,keep=1 *) reg [1:0] enable_sync=0;
 (* preserve=1,keep=1 *) reg [2:0] release_pipe=0;
 always @(posedge clk or negedge power_ready)begin
  if(!power_ready)begin enable_sync<=0;release_pipe<=0;end
  else begin
   enable_sync<={enable_sync[0],load_enable};
   if(!enable_sync[1])release_pipe<=0;
   else release_pipe<={release_pipe[1:0],1'b1};
  end
 end
 assign rst=~release_pipe[2];
endmodule
