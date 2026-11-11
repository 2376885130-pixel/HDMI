// Preview starts only after a successful fullscreen display. A failed exit
// rolls back to the still-pinned displayed image; boot recovery is never held.
module thumbnail_controller #(parameter ANIMATIONS=0,RUNTIME_MODE=0)(
 input wire clk,rst_n,switch_down,first_shown,full_ready,
 input wire key4_press,next_press,prev_press,
 input wire [4:0] current_index,input wire [5:0] image_total,
 input wire visible_preview,input wire [2:0] visible_page,
 input wire [3:0] visible_valid,
 input wire [1:0] visible_focus,
 output reg session,output reg [2:0] page,
 output reg [1:0] focus,output wire hold_fullscreen,
 output reg select_valid,output reg [4:0] select_index,
 input wire load_error,input wire [4:0] displayed_index,
 output reg zoom_request,output reg [4:0] zoom_index,input wire zoom_done,input wire effect_bypass
);
 wire [2:0] first_page={current_index[4:3],1'b0};
 wire [2:0] last_page={current_index[4:3],1'b1};
 wire usable=visible_preview && visible_page==page;
 reg exiting;
 assign hold_fullscreen=first_shown && (session || exiting || visible_preview);
 integer k;reg found;reg [1:0] pick,candidate;
 always @*begin
  pick=focus;found=0;candidate=0;
  for(k=1;k<=4;k=k+1)begin
   candidate=focus+k;
   if(!found && visible_valid[candidate])begin pick=candidate;found=1;end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin session<=0;exiting<=0;page<=0;focus<=0;select_valid<=0;select_index<=0;zoom_request<=0;zoom_index<=0;end
  else begin
   select_valid<=0;
   if(!first_shown)begin session<=0;exiting<=0;zoom_request<=0;end
   else if(zoom_request)begin
    if(switch_down && !load_error)zoom_request<=0;
    else if(zoom_done || load_error)begin
     zoom_request<=0;session<=0;exiting<=1;select_valid<=1;
     select_index<=load_error?displayed_index:zoom_index;
    end
   end
   else if(exiting)begin
    if(load_error && current_index!=displayed_index)begin
     select_valid<=1;select_index<=displayed_index;
    end
    if(!visible_preview && full_ready)exiting<=0;
   end else if(!session)begin
    if(switch_down && full_ready && !visible_preview && !load_error && image_total!=0)begin
     session<=1;page<=current_index[4:2];focus<=current_index[1:0];
    end
   end else if(!switch_down || load_error)begin
    if(ANIMATIONS && !(RUNTIME_MODE&&effect_bypass) && !load_error && visible_preview && visible_valid[visible_focus])begin
     zoom_request<=1;zoom_index<={visible_page,visible_focus};page<=visible_page;focus<=visible_focus;
    end else begin
     session<=0;exiting<=1;select_valid<=1;
     select_index<=load_error ? displayed_index :
       (visible_preview && visible_valid[visible_focus] ? {visible_page,visible_focus} : displayed_index);
    end
   end else if(next_press!=prev_press)begin
    page<=next_press ? (page==last_page ? first_page : page+1'b1) : (page==first_page ? last_page : page-1'b1);
    focus<=0;
   end else if(usable && (key4_press || !visible_valid[focus]))begin
    if(found)focus<=pick;
   end
  end
 end
endmodule
