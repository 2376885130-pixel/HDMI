// Stage 1-3 allocation: rotate through four slots; no cache-hit policy yet.
// The UI accepts another load only after the previous frame is presented.
module quad_slot_allocator(
 input wire clk,rst,write_req,load_ready,show_image,
 input wire [1:0] display_slot,
 output reg [1:0] load_slot,output reg [3:0] slot_valid
);
 reg req_old,ready_old;
 reg [1:0] cursor,display_meta,display_sync;
 reg [1:0] shown_sync;
 wire [1:0] selected=(shown_sync[1] && cursor==display_sync) ? cursor+2'd1 : cursor;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   req_old<=0;ready_old<=0;cursor<=0;load_slot<=0;slot_valid<=0;
   display_meta<=0;display_sync<=0;shown_sync<=0;
  end else begin
   req_old<=write_req;ready_old<=load_ready;
   display_meta<=display_slot;display_sync<=display_meta;shown_sync<={shown_sync[0],show_image};
   if(write_req && !req_old)begin
    load_slot<=selected;cursor<=selected+2'd1;slot_valid[selected]<=0;
   end else if(load_ready && !ready_old)slot_valid[load_slot]<=1;
  end
 end
endmodule
