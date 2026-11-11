module image_key_control #(
 parameter integer DEBOUNCE_CYCLES=1000000,
 parameter integer RESET_CYCLES=64,
 parameter integer CLOCK_HZ=50000000,
 parameter integer SWITCH_AUTOPLAY=0,FIXED_INTERVAL_SECONDS=0,THUMBNAILS=0
)(input wire clk,reset_n,image_ready,key_next_n,key_prev_n,
 output reg [4:0] image_index=0,output wire run_reset_n,
 input wire key_auto_n,input wire [1:0] interval_switch,
 output reg auto_mode=0,input wire direction_switch,
 input wire [5:0] image_total,
 output wire [1:0] stable_interval, output wire stable_direction,
 input wire load_error,input wire recovery_next,output reg manual_restart=0,
 input wire preview_hold,select_valid,input wire [4:0] select_index,
 output wire next_event,prev_event);
 wire held=THUMBNAILS && preview_hold;
 (* preserve = 1, keep = 1 *) reg [2:0] ready_sync=0;
 (* preserve=1,keep=1 *) reg ready_capture=0;
 always @(negedge clk or negedge reset_n)
  if(!reset_n)ready_capture<=0;else ready_capture<=image_ready;
 reg has_displayed=0,pending_valid=0,pending_reverse=0;
 wire next_press,prev_press,auto_press;
 assign next_event=next_press;assign prev_event=prev_press;
 localparam integer RESET_BITS=(RESET_CYCLES<2)?1:$clog2(RESET_CYCLES+1);
 localparam integer DB_BITS=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
 localparam integer SECOND_BITS=(CLOCK_HZ<2)?1:$clog2(CLOCK_HZ);
 // synthesis translate_off
 initial if(DEBOUNCE_CYCLES<1 || RESET_CYCLES<1 || CLOCK_HZ<1)
   $fatal(1,"Control timing parameters must be positive");
 // synthesis translate_on
 reg [RESET_BITS-1:0] reset_count=0;
 reg [2:0] sw_meta=0,sw_sync=0,sw_stable=0,sw_previous=0,sw_candidate=0;
 reg [DB_BITS-1:0] sw_count=0;
 reg [SECOND_BITS-1:0] second_count=0;
 reg [4:0] elapsed_seconds=0;
 wire [4:0] interval_seconds=FIXED_INTERVAL_SECONDS!=0 ? FIXED_INTERVAL_SECONDS :
     sw_stable[1:0]==0 ? 5'd2 : sw_stable[1:0]==1 ? 5'd5 : sw_stable[1:0]==2 ? 5'd10 : 5'd20;
 assign stable_interval=FIXED_INTERVAL_SECONDS==5 ? 2'd1 : sw_stable[1:0];
 assign stable_direction=sw_stable[2];
 wire [4:0] last_image=image_total-1'b1;
 assign run_reset_n=reset_n && reset_count==0;
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_next(clk,reset_n,key_next_n,next_press);
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_prev(clk,reset_n,key_prev_n,prev_press);
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_auto(clk,reset_n,key_auto_n,auto_press);
 wire manual_step=next_press!=prev_press;
 wire conflicting_keys=next_press && prev_press;
 wire can_step=ready_sync[2] && reset_count==0 && image_total>1 && !load_error;
 wire step_reverse=manual_step ? prev_press : pending_reverse;
 wire auto_event=SWITCH_AUTOPLAY ? (auto_mode!=!key_auto_n) : auto_press;
 wire auto_step=auto_mode && !auto_event && !next_press && !prev_press && !pending_valid && !load_error && ready_sync[2] && reset_count==0 &&
                sw_stable==sw_previous && second_count==CLOCK_HZ-1 && elapsed_seconds==interval_seconds-1;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   manual_restart<=0;
   ready_sync<=0;has_displayed<=0;pending_valid<=0;pending_reverse<=0;image_index<=0;reset_count<=0;auto_mode<=0;
   sw_meta<=0;sw_sync<=0;sw_stable<=0;sw_previous<=0;sw_candidate<=0;sw_count<=0;
   second_count<=0;elapsed_seconds<=0;
  end else begin
   manual_restart<=0;
   ready_sync<={ready_sync[1:0],ready_capture};
   if(ready_sync[2])has_displayed<=1;
   // One pending manual direction. New manual input replaces the old one.
   if(held || load_error || image_total<2 || conflicting_keys)pending_valid<=0;
   else if(manual_step && has_displayed && !can_step)begin
    pending_valid<=1;pending_reverse<=prev_press;
   end
   sw_meta<={direction_switch,interval_switch};sw_sync<=sw_meta;sw_previous<=sw_stable;
   if(sw_sync==sw_stable)begin sw_candidate<=sw_sync;sw_count<=0;end
   else if(sw_sync!=sw_candidate)begin
    sw_candidate<=sw_sync;
    if(DEBOUNCE_CYCLES==1)begin sw_stable<=sw_sync;sw_count<=0;end
    else sw_count<=1;
   end else if(sw_count==DEBOUNCE_CYCLES-1)begin sw_stable<=sw_candidate;sw_count<=0;end
   else sw_count<=sw_count+1'b1;
   if(SWITCH_AUTOPLAY)auto_mode<=!key_auto_n;
   else if(auto_press) auto_mode<=~auto_mode;
   if(held || image_total<2 || !auto_mode || auto_event || !ready_sync[2] || reset_count!=0 ||
      manual_step || conflicting_keys || pending_valid || auto_step || sw_stable!=sw_previous) begin
    second_count<=0;elapsed_seconds<=0;
   end else if(second_count==CLOCK_HZ-1)begin
    second_count<=0;elapsed_seconds<=elapsed_seconds+1'b1;
   end else second_count<=second_count+1'b1;
   if(THUMBNAILS && select_valid && select_index<image_total)begin
    image_index<=select_index;pending_valid<=0;reset_count<=RESET_CYCLES;
   end else if(reset_count!=0)reset_count<=reset_count-1'b1;
   else if(load_error && manual_step && !conflicting_keys)begin
    manual_restart<=1;
    // A user action starts a fresh attempt even before the first display.
    pending_valid<=0;reset_count<=RESET_CYCLES;
    if(image_total>1)image_index<=prev_press ?
      (image_index==0 ? last_image : image_index-1'b1) :
      (image_index==last_image ? 5'd0 : image_index+1'b1);
   end else if(recovery_next && image_total>1)begin
    pending_valid<=0;reset_count<=RESET_CYCLES;
    image_index<=sw_stable[2] ? (image_index==0 ? last_image : image_index-1'b1) :
      (image_index==last_image ? 5'd0 : image_index+1'b1);
   end else if(held)pending_valid<=0;
   else if(can_step && !conflicting_keys && (manual_step || pending_valid)) begin
    pending_valid<=0;
    image_index<=!step_reverse ? (image_index==last_image ? 5'd0 : image_index+1'b1) :
                             (image_index==0 ? last_image : image_index-1'b1);
    reset_count<=RESET_CYCLES;
   end else if(auto_step && can_step)begin
    image_index<=sw_stable[2] ? (image_index==0 ? last_image : image_index-1'b1) :
                              (image_index==last_image ? 5'd0 : image_index+1'b1);
    reset_count<=RESET_CYCLES;
   end
   if(image_total==0 || image_index>=image_total)image_index<=0;
  end
 end
endmodule
