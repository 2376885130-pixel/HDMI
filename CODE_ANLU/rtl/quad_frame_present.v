// Bundled metadata remains stable from load_ready until the UI starts a new load.
// Prepare in blanking; publish only at the first pixel of a complete frame.
module quad_frame_present #(parameter REQUEST_TOGGLE=0,FADE_FRAMES=0,HOLD_LIMIT=60,TRANSITION_MODE=0,THUMBNAILS=0,LIVE_EFFECT=0,RUNTIME_MODE=0)(
 input wire clk,rst,input wire [9:0] x,y,
 input wire load_ready,input wire [1:0] load_slot,input wire [4:0] load_index,
 input wire [87:0] load_name,input wire read_ack,read_primed,read_underflow,
 output reg read_req,output reg [1:0] read_slot,
 output reg show_image,output reg presented,output reg frame_valid,
 output reg [1:0] display_slot,output reg [4:0] display_index,
 output reg [87:0] display_name,output reg commit,
 output wire [8:0] transition_gain,output wire transition_busy,
 output wire [1:0] transition_kind,output wire reveal_active,
 input wire preview_request,input wire [2:0] requested_page,input wire [4:0] target_index,
 input wire page_toggle,page_bank,input wire [2:0] page_number,input wire [3:0] page_valid,
 output reg page_ack,read_preview,read_bank,visible_preview,visible_bank,
 output reg [2:0] visible_page,output reg [3:0] visible_valid,
 input wire [1:0] requested_focus,output reg [1:0] visible_focus,
 input wire page_zoom,output reg visible_zoom,
 input wire manual_effect,input wire [4:0] effect_index,output wire manual_transition,
 input wire basic_request,mode_safe,output reg basic_active
);
 (* preserve=1,keep=1 *) reg [2:0] ready_sync,ack_sync;
 reg ready_old,pending,prepared,switching,pending_token;
 reg [1:0] pending_slot;
 reg [4:0] pending_index;
 reg [87:0] pending_name;
 wire allow_switch;
 wire preview_mode=THUMBNAILS && (preview_request || visible_preview);
 wire select_pending=pending && (preview_mode || allow_switch);
 (* preserve=1,keep=1 *) reg [2:0] page_sync;
 reg page_pending,page_token,staged_bank;
 reg [2:0] staged_page,prepared_page;
 reg [3:0] staged_valid,prepared_valid;
 reg preparing_page;
 reg staged_zoom,prepared_zoom;
 wire want_preview=THUMBNAILS && preview_request;
 wire matching_page=page_pending && staged_page==requested_page;
 wire can_exit=(pending && pending_index==target_index) || (!pending && display_index==target_index);
 wire frame_ready=prepared && !read_req && !ack_sync[2] && read_primed;
 // Change visual policy only in blanking, after the current transaction/effect.
 // This never cancels memory work or blocks menu exit keys.
 always @(posedge clk or posedge rst)
  if(rst)basic_active<=RUNTIME_MODE!=0;
  else if(RUNTIME_MODE && x==0&&y==480&&mode_safe&&!pending&&!switching&&
          !transition_busy&&!preview_mode&&ready_sync[2]==ready_old)
   basic_active<=basic_request;
 function [1:0] valid_focus;
 input [3:0] mask;input [1:0] wanted;
 begin
  if(mask[wanted])valid_focus=wanted;
  else if(mask[0])valid_focus=0;
  else if(mask[1])valid_focus=1;
  else if(mask[2])valid_focus=2;
  else valid_focus=3;
 end endfunction
 // 0=fade, 1=horizontal, 2=vertical, 3=center rectangle, 4=by image index.
 wire [1:0] requested_kind=(LIVE_EFFECT&&manual_effect&&effect_index==pending_index)?2'd3:
   TRANSITION_MODE==4 ? pending_index[1:0] : TRANSITION_MODE;
 reg effect_active;
 assign manual_transition=LIVE_EFFECT&&effect_active&&!basic_active;
 always @(posedge clk or posedge rst)
  if(rst)effect_active<=0;
  else if(x==0&&y==0&&!transition_busy&&pending&&!preview_mode)
   effect_active<=manual_effect&&effect_index==pending_index;
 video_fade_transition #(.FADE_FRAMES(FADE_FRAMES),.HOLD_LIMIT(HOLD_LIMIT)) u_transition(
  .clk(clk),.rst(rst),.frame_start(x==0 && y==0),.show_image(show_image),
  .pending(pending && !preview_mode),.different_image(pending_index!=display_index && !basic_active),.commit(commit),
  .allow_switch(allow_switch),.busy(transition_busy),.gain(transition_gain),
  .frame_ready(frame_ready),.requested_kind(requested_kind),
  .transition_kind(transition_kind),.reveal_active(reveal_active));
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   ready_sync<=0;ack_sync<=0;ready_old<=0;pending_token<=0;pending<=0;prepared<=0;switching<=0;
   pending_slot<=0;pending_index<=0;pending_name<=0;read_req<=0;read_slot<=0;
   page_sync<=0;page_pending<=0;page_token<=0;staged_bank<=0;staged_page<=0;staged_valid<=0;
   prepared_page<=0;prepared_valid<=0;preparing_page<=0;visible_focus<=0;visible_zoom<=0;staged_zoom<=0;prepared_zoom<=0;
   page_ack<=0;read_preview<=0;read_bank<=0;visible_preview<=0;visible_bank<=0;visible_page<=0;visible_valid<=0;
   show_image<=0;presented<=0;frame_valid<=0;display_slot<=0;display_index<=0;display_name<=0;commit<=0;
  end else begin
   ready_sync<={ready_sync[1:0],load_ready};ack_sync<={ack_sync[1:0],read_ack};
   ready_old<=ready_sync[2];commit<=0;
   page_sync<={page_sync[1:0],page_toggle};
   if(THUMBNAILS && page_sync[2]!=page_ack && !page_pending)begin
    staged_zoom<=page_zoom;
    page_pending<=1;page_token<=page_sync[2];staged_bank<=page_bank;staged_page<=page_number;staged_valid<=page_valid;
   end
   // Discard obsolete pages only when no prepared read still references them.
   if(page_pending && (!want_preview || staged_page!=requested_page) && !preparing_page)begin
    page_ack<=page_token;page_pending<=0;
   end
   if(!REQUEST_TOGGLE && !ready_sync[2])presented<=0;
   if(REQUEST_TOGGLE ? (ready_sync[2]!=ready_old) : (ready_sync[2] && !ready_old))begin
    pending_token<=ready_sync[2];
    pending<=1;pending_slot<=load_slot;pending_index<=load_index;pending_name<=load_name;
   end
   if(x==0 && y==480 && !read_req && (show_image || pending))begin
    read_slot<=select_pending ? pending_slot : display_slot;
    switching<=select_pending;prepared<=0;read_req<=1;frame_valid<=0;
    read_preview<=0;preparing_page<=0;
    if(want_preview && matching_page)begin
     read_preview<=1;read_bank<=staged_bank;switching<=0;preparing_page<=1;
     prepared_page<=staged_page;prepared_valid<=staged_valid;
     prepared_zoom<=staged_zoom;
    end else if(THUMBNAILS && visible_preview && (want_preview || !can_exit))begin
     read_preview<=1;read_bank<=visible_bank;switching<=0;
    end
   end else if(read_req && ack_sync[2])begin read_req<=0;prepared<=1;end
   if(read_underflow)frame_valid<=0;
   if(x==0 && y==0)begin
    if(!visible_preview || visible_page==requested_page)
     visible_focus<=valid_focus(visible_valid,requested_focus);
    frame_valid<=prepared && !read_req && !ack_sync[2] && read_primed;
    if(prepared && !read_req && !ack_sync[2] && read_primed)begin
     prepared<=0;
     visible_preview<=read_preview;
     if(!read_preview)visible_zoom<=0;
     if(read_preview)begin
      visible_bank<=read_bank;
      if(preparing_page)begin
       visible_page<=prepared_page;visible_valid<=prepared_valid;
       visible_zoom<=prepared_zoom;
       visible_focus<=valid_focus(prepared_valid,prepared_page==requested_page ? requested_focus : 2'd0);
       page_ack<=page_token;page_pending<=0;preparing_page<=0;
      end
     end
     if(switching && pending)begin
      display_slot<=read_slot;display_index<=pending_index;display_name<=pending_name;
      show_image<=1;presented<=REQUEST_TOGGLE ? pending_token : 1'b1;commit<=1;pending<=0;switching<=0;
     end
    end
   end
  end
 end
endmodule
