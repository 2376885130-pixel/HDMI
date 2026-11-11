// SD-clock owner of four cached frames. Metadata is bundled with a toggle:
// hold it until the pixel domain acknowledges actual frame-boundary display.
module frame_cache_manager #(
 parameter PREFETCH_DELAY=2500000, parameter MAX_RETRIES=2,THUMBNAILS=0,
 parameter PREFETCH_ENABLE=1
)(
 input wire clk,rst,input wire [4:0] requested_index,
 input wire request_enable,reverse_direction,
 input wire catalog_valid,input wire [5:0] image_total,
 input wire image_ready,input wire [87:0] image_name,
 input wire [3:0] loader_status,loader_stage,
 input wire sector_busy,writer_reset,write_req,sector_req,
 output reg job_start,job_cancel,writer_enable,
 output reg [4:0] job_index,output reg [1:0] load_slot,
 output wire transport_reset,
 output reg present_toggle,output reg [1:0] present_slot,
 output reg [4:0] present_index,output reg [87:0] present_name,
 input wire present_ack,
 output wire [3:0] ui_status,output wire [3:0] ui_stage,
 output reg [3:0] slot_valid,
 input wire aux_req,input wire [4:0] aux_index,
 output reg aux_ack,aux_ok,output reg [1:0] aux_slot
);
 localparam BOOT=0,IDLE=1,DRAIN=2,CLEAR=3,RUN=4;
 localparam WAIT_BITS=PREFETCH_DELAY<2?1:$clog2(PREFETCH_DELAY+1);
 reg [2:0] state;
 reg [4:0] slot_id[0:3];reg [87:0] slot_name[0:3];
 reg [1:0] cursor,display_slot;
 reg display_valid,present_outstanding;reg [4:0] display_id;
 (* preserve=1,keep=1 *) reg [2:0] enable_sync,ack_sync;
 (* preserve=1,keep=1 *) reg [1:0] reset_sync,dir_sync;
 reg [4:0] index_meta,index_sync,desired_old;
 reg enable_old,dir_old;
 reg background,blocked;reg [4:0] blocked_id;
 reg aux_job;
 (* preserve=1,keep=1 *) reg [2:0] aux_sync;
 reg [4:0] aux_meta,aux_id;
 wire auxiliary=THUMBNAILS && aux_sync[2];
 reg aux_hit;reg [1:0] aux_hit_slot;
 reg [3:0] error_code,error_stage;
 reg [1:0] retries;
 reg [5:0] transport_count;
 reg [WAIT_BITS-1:0] quiet_count;
 reg [2:0] look_count;reg [4:0] look_id;
 reg [3:0] protected_slots;
 reg [31:0] failed_prefetch;
 reg demand_miss,demand_pending;
 // These counters are internal diagnostics only.  They have no output path;
 // keeping them forced the no-prefetch build to retain adders and registers
 // after PREFETCH_ENABLE was set to zero, which increased physical MSlice use.
 reg [31:0] hit_count,miss_count,prefetch_count,cancel_count,sector_count;
 reg [31:0] switch_cycles,last_switch_cycles;
 wire [4:0] desired=index_sync<image_total ? index_sync : 5'd0;
 wire present_busy=present_toggle!=ack_sync[2];
 wire changed=(desired!=desired_old) || (enable_sync[2] && !enable_old);
 wire demand=enable_sync[2] && (!display_valid || desired!=display_id);
 assign transport_reset=transport_count!=0;
 assign ui_status=blocked && desired==blocked_id ? error_code :
                  (display_valid ? 4'd5 : loader_status);
 assign ui_stage=blocked && desired==blocked_id ? error_stage : loader_stage;
 function [4:0] neighbor;
 input [4:0] id;input reverse;input [5:0] total;
 begin
  if(reverse)neighbor={id[4:3],id[2:0]-3'd1};
  else neighbor={id[4:3],id[2:0]+3'd1};
 end endfunction
 reg hit,look_hit,victim_found;
 reg [1:0] hit_slot,look_slot,victim;
 reg [1:0] candidate;
 integer i;
 always @*begin
  hit=0;look_hit=0;hit_slot=0;look_slot=0;victim=0;victim_found=0;candidate=0;aux_hit=0;aux_hit_slot=0;
  for(i=0;i<4;i=i+1)begin
   if(slot_valid[i] && slot_id[i]==desired)begin hit=1;hit_slot=i;end
   if(slot_valid[i] && slot_id[i]==look_id)begin look_hit=1;look_slot=i;end
   if(slot_valid[i] && slot_id[i]==aux_id)begin aux_hit=1;aux_hit_slot=i;end
  end
  // During a foreground miss only displayed and pending slots are pinned.
  // Prefetch additionally preserves earlier members of the look-ahead window.
  for(i=3;i>=0;i=i-1)begin
   candidate=cursor+i;
   if((!display_valid || candidate!=display_slot) &&
      (!present_outstanding || candidate!=present_slot) &&
      (!auxiliary || !aux_ack || !aux_ok || candidate!=aux_slot) &&
      (demand || auxiliary || !protected_slots[candidate]))begin
    victim=candidate;victim_found=1;
   end
  end
  // Prefer unused slots before evicting a valid, unpinned frame.
  for(i=3;i>=0;i=i-1)begin
   candidate=cursor+i;
   if(!slot_valid[candidate] && (!display_valid || candidate!=display_slot) &&
      (!present_outstanding || candidate!=present_slot) &&
      (!auxiliary || !aux_ack || !aux_ok || candidate!=aux_slot) &&
      (demand || auxiliary || !protected_slots[candidate]))begin
    victim=candidate;victim_found=1;
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   enable_sync<=0;ack_sync<=0;reset_sync<=0;dir_sync<=0;index_meta<=0;index_sync<=0;aux_sync<=0;aux_meta<=0;aux_id<=0;
  end else begin
   enable_sync<={enable_sync[1:0],request_enable};ack_sync<={ack_sync[1:0],present_ack};
   reset_sync<={reset_sync[0],writer_reset};dir_sync<={dir_sync[0],reverse_direction};
   index_meta<=requested_index;index_sync<=index_meta;
   aux_sync<={aux_sync[1:0],aux_req};aux_meta<=aux_index;aux_id<=aux_meta;
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=BOOT;job_start<=0;job_cancel<=0;writer_enable<=1;job_index<=0;load_slot<=0;
   aux_ack<=0;aux_ok<=0;aux_slot<=0;aux_job<=0;
   present_toggle<=0;present_slot<=0;present_index<=0;present_name<=0;slot_valid<=0;
   cursor<=1;display_slot<=0;display_valid<=0;present_outstanding<=0;display_id<=0;
   desired_old<=0;enable_old<=0;dir_old<=0;background<=0;blocked<=0;blocked_id<=0;
   error_code<=0;error_stage<=0;retries<=0;transport_count<=0;quiet_count<=0;
   look_count<=0;look_id<=0;protected_slots<=0;failed_prefetch<=0;
   demand_miss<=1;demand_pending<=1;hit_count<=0;miss_count<=1;
   prefetch_count<=0;cancel_count<=0;sector_count<=0;switch_cycles<=0;last_switch_cycles<=0;
  end else begin
   job_start<=0;job_cancel<=0;
   if(!auxiliary)begin aux_ack<=0;aux_ok<=0;end
   desired_old<=desired;enable_old<=enable_sync[2];dir_old<=dir_sync[1];
   if(sector_req)sector_count<=sector_count+1'b1;
   if(transport_count!=0)transport_count<=transport_count-1'b1;
   if(demand_pending && switch_cycles!=32'hffffffff)switch_cycles<=switch_cycles+1'b1;
   if(changed)begin
    blocked<=0;retries<=0;quiet_count<=0;demand_pending<=1;switch_cycles<=0;
    demand_miss<=state==BOOT || ((state==RUN || state==CLEAR) && job_index==desired);
   end
   // An acknowledged frame remains pinned until another display is committed.
   if(present_outstanding && !present_busy)begin
    present_outstanding<=0;
    display_valid<=1;display_slot<=present_slot;display_id<=present_index;
    last_switch_cycles<=switch_cycles;demand_pending<=0;
    look_count<=0;look_id<=neighbor(present_index,dir_sync[1],image_total);
    protected_slots<=4'b0001<<present_slot;quiet_count<=0;
   end
   if(dir_sync[1]!=dir_old && display_valid)begin
    look_count<=0;look_id<=neighbor(display_id,dir_sync[1],image_total);
    protected_slots<=4'b0001<<display_slot;quiet_count<=0;
   end
   case(state)
    BOOT:begin
     // The initial mount automatically loads its selected file. Selection is
     // stable well before the scan finishes, including PLL-relock recovery.
     if(!catalog_valid && !write_req)job_index<=index_sync;
     if(image_ready)begin
      slot_valid[0]<=1;slot_id[0]<=job_index;slot_name[0]<=image_name;
      state<=IDLE;
     end else if(catalog_valid && loader_status>=10)begin
      writer_enable<=0;job_cancel<=1;
      if(sector_busy)transport_count<=63;
      if(retries<MAX_RETRIES)begin retries<=retries+1'b1;state<=DRAIN;end
      else begin blocked<=1;blocked_id<=job_index;error_code<=loader_status;error_stage<=loader_stage;state<=IDLE;end
     end
    end
    IDLE:begin
     if(quiet_count<PREFETCH_DELAY)quiet_count<=quiet_count+1'b1;
     if(demand && !present_outstanding && !(blocked && desired==blocked_id))begin
      if(hit)begin
       present_slot<=hit_slot;present_index<=desired;present_name<=slot_name[hit_slot];
       present_toggle<=~present_toggle;present_outstanding<=1;
       if(!demand_miss)hit_count<=hit_count+1'b1;
      end else if(victim_found)begin
       load_slot<=victim;slot_valid[victim]<=0;cursor<=victim+1'b1;
       job_index<=desired;background<=0;aux_job<=0;writer_enable<=0;job_cancel<=1;state<=DRAIN;
       if(!demand_miss)miss_count<=miss_count+1'b1;
       demand_miss<=1;quiet_count<=0;
      end
     end else if(auxiliary && !aux_ack)begin
      if(aux_hit)begin aux_ack<=1;aux_ok<=1;aux_slot<=aux_hit_slot;end
      else if(victim_found)begin
       load_slot<=victim;slot_valid[victim]<=0;cursor<=victim+1'b1;
       job_index<=aux_id;background<=0;aux_job<=1;retries<=0;
       // Auxiliary eviction invalidates old prefetch-window accounting.
       look_count<=0;look_id<=neighbor(display_id,dir_sync[1],image_total);
       protected_slots<=display_valid ? (4'b0001<<display_slot) : 4'b0000;quiet_count<=0;
       writer_enable<=0;job_cancel<=1;state<=DRAIN;
      end
     end else if(PREFETCH_ENABLE && !auxiliary && !demand && !present_outstanding && display_valid && enable_sync[2] &&
                 image_total>1 && look_count<3 && look_count<image_total-1 && quiet_count==PREFETCH_DELAY)begin
      if(look_hit || failed_prefetch[look_id])begin
       if(look_hit)protected_slots[look_slot]<=1;
       look_id<=neighbor(look_id,dir_sync[1],image_total);look_count<=look_count+1'b1;
      end else if(victim_found)begin
       load_slot<=victim;slot_valid[victim]<=0;cursor<=victim+1'b1;
       job_index<=look_id;background<=1;aux_job<=0;writer_enable<=0;job_cancel<=1;state<=DRAIN;
      end
     end
    end
    DRAIN:begin
     // Source sector and destination burst must both finish before reuse.
     if(reset_sync[1] && !sector_busy && transport_count==0)begin
      if((background && demand && desired!=job_index) ||
         (aux_job && (!auxiliary || (demand && desired!=job_index))))begin
       state<=IDLE;aux_job<=0;
      end
      else begin job_start<=1;writer_enable<=1;state<=CLEAR;end
     end
    end
    CLEAR:if(!image_ready)state<=RUN;
    RUN:begin
     if((background || aux_job) && demand && hit && !present_outstanding)begin
      present_slot<=hit_slot;present_index<=desired;present_name<=slot_name[hit_slot];
      present_toggle<=~present_toggle;present_outstanding<=1;
      if(!demand_miss)hit_count<=hit_count+1'b1;
     end
     if(image_ready)begin
      slot_valid[load_slot]<=1;slot_id[load_slot]<=job_index;slot_name[load_slot]<=image_name;
      if(background)prefetch_count<=prefetch_count+1'b1;
      state<=IDLE;retries<=0;aux_job<=0;
     end else if(loader_status>=10)begin
      slot_valid[load_slot]<=0;writer_enable<=0;job_cancel<=1;
      if(sector_busy)transport_count<=63;
      if(background && desired!=job_index)begin
       failed_prefetch[job_index]<=1;state<=IDLE;
      end else if(retries<MAX_RETRIES)begin retries<=retries+1'b1;state<=DRAIN;end
      else begin
       if(aux_job)begin aux_ack<=1;aux_ok<=0;aux_job<=0;end
       else begin blocked<=1;blocked_id<=job_index;error_code<=loader_status;error_stage<=loader_stage;end
       failed_prefetch[job_index]<=1;state<=IDLE;
      end
     end else if((background && demand && desired!=job_index && !hit) ||
                 (aux_job && (!auxiliary || (demand && desired!=job_index && !hit))))begin
      writer_enable<=0;job_cancel<=1;state<=DRAIN;cancel_count<=cancel_count+1'b1;
     end
    end
    default:state<=BOOT;
   endcase
  end
 end
endmodule
