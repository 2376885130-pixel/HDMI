// Drain an in-flight SDRAM write burst before resetting the write controller.
// The read controller and SDRAM refresh are never reset by a load retry.
module frame_write_reset_guard(
 input wire clk,rst,abort_load,write_busy,
 output reg write_reset=1
);
 (* preserve=1,keep=1 *) reg [1:0] abort_sync=3;
 always @(posedge clk or posedge rst)begin
  if(rst)begin abort_sync<=3;write_reset<=1;end
  else begin
   abort_sync<={abort_sync[0],abort_load};
   if(abort_sync[1])begin
    if(!write_busy)write_reset<=1;
   end else write_reset<=0;
  end
 end
endmodule
