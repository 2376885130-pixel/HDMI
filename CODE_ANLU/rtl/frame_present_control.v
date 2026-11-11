// The loader holds its completed bank and metadata until the next request.
// Keep showing the committed bank through load/reset/error. Publish a new frame
// only after its read request is acknowledged during vertical blanking.
module frame_present_control(
 input wire clk,rst,input wire [9:0] x,y,
 input wire load_ready,load_bank,input wire [4:0] load_index,
 input wire [87:0] load_name,input wire read_ack,
 output reg read_req=0,output reg read_bank=0,
 output reg show_image=0,output reg presented=0,
 output reg display_bank=0,output reg [4:0] display_index=0,
 output reg [87:0] display_name=0,output reg commit=0
);
 (* preserve=1,keep=1 *) reg [2:0] ready_sync=0,ack_sync=0;
 reg ready_old=0,pending=0,pending_bank=0,prepared=0,switching=0;
 reg [4:0] pending_index=0;
 reg [87:0] pending_name=0;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ready_sync<=0;ack_sync<=0;ready_old<=0;pending<=0;pending_bank<=0;
   pending_index<=0;pending_name<=0;prepared<=0;switching<=0;
   read_req<=0;read_bank<=0;show_image<=0;presented<=0;
   display_bank<=0;display_index<=0;display_name<=0;commit<=0;
  end else begin
   ready_sync<={ready_sync[1:0],load_ready};ack_sync<={ack_sync[1:0],read_ack};
   ready_old<=ready_sync[2];commit<=0;
   if(!ready_sync[2])begin presented<=0;pending<=0;end
   if(ready_sync[2] && !ready_old)begin
    pending<=1;pending_bank<=load_bank;pending_index<=load_index;pending_name<=load_name;
   end
   if(x==0 && y==480 && !read_req && (show_image || pending))begin
    read_bank<=pending ? pending_bank : display_bank;
    switching<=pending;prepared<=0;read_req<=1;
   end else if(read_req && ack_sync[2])begin read_req<=0;prepared<=1;end
   if(x==0 && y==0 && prepared)begin
    prepared<=0;
    if(switching && pending && ready_sync[2])begin
     display_bank<=read_bank;display_index<=pending_index;display_name<=pending_name;
     show_image<=1;presented<=1;commit<=1;pending<=0;switching<=0;
    end
   end
  end
 end
endmodule
