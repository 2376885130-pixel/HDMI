// Pixel-domain presentation policy. The cache has already completed the new
// image before pending becomes true. Never acknowledge a cache transaction here;
// only quad_frame_present acknowledges an actually prepared, displayed frame.
module video_fade_transition #(
 parameter integer FADE_FRAMES=8, parameter integer HOLD_LIMIT=60
)(
 input wire clk,rst,frame_start,show_image,pending,different_image,commit,
 output wire allow_switch,output wire busy,output wire [8:0] gain,
 input wire frame_ready,input wire [1:0] requested_kind,
 output wire [1:0] transition_kind,output wire reveal_active
);
 generate if(FADE_FRAMES==0)begin:g_bypass
  assign allow_switch=1'b1;assign busy=1'b0;assign gain=9'd256;
  assign transition_kind=0;assign reveal_active=0;
 end else begin:g_effect
  localparam IDLE=0,OUT=1,HOLD=2,IN=3,RECOVER=4;
  localparam CW=$clog2(FADE_FRAMES+1);
  localparam HW=HOLD_LIMIT<2?1:$clog2(HOLD_LIMIT+1);
  reg [2:0] state;
  reg [CW-1:0] level;
  reg [HW-1:0] held_frames;
  reg committed;
  reg [1:0] kind;
  assign transition_kind=kind;
  assign reveal_active=state==IN && kind!=0;
  // A first image and a repeated index require no transition. During a fade-in
  // an unexpectedly early next transaction stays queued until this one finishes.
  assign allow_switch=!show_image ||
       (state==IDLE && !different_image) || state==HOLD || state==RECOVER;
  assign busy=state==OUT || state==HOLD || state==IN;
  assign gain=(state==IDLE || state==RECOVER) ? 9'd256 :
              state==HOLD ? 9'd0 : (level*256)/FADE_FRAMES;
  // synthesis translate_off
  initial if(FADE_FRAMES<1 || FADE_FRAMES>256 || HOLD_LIMIT<1)
   $fatal(1,"Invalid fade parameters");
  // synthesis translate_on
  always @(posedge clk or posedge rst)begin
   if(rst)begin state<=IDLE;level<=FADE_FRAMES;held_frames<=0;committed<=0;kind<=0;end
   else begin
    if(commit && state==HOLD)committed<=1;
    // Both states have unity gain. Finish fault bypass as soon as the actual
    // transaction commits, so the next queued image is not bypassed as well.
    if(commit && state==RECOVER)state<=IDLE;
    if(frame_start)begin
     case(state)
      IDLE:begin
       committed<=0;held_frames<=0;
       if(show_image && pending && different_image)begin
        state<=OUT;level<=FADE_FRAMES-1;kind<=requested_kind;
       end
      end
      OUT:if(level<=1)begin state<=HOLD;level<=0;held_frames<=0;end
          else level<=level-1'b1;
      HOLD:begin
       if((committed || commit) && frame_ready)begin state<=IN;level<=1;committed<=0;held_frames<=0;end
       else if(held_frames==HOLD_LIMIT-1)begin
        // Release only the visual gate on failure, never fabricate a commit.
        // Existing memory/loader recovery retains ownership of the fault.
        state<=RECOVER;level<=FADE_FRAMES;
       end else held_frames<=held_frames+1'b1;
      end
      IN:begin
       // Count visible frames only. A starved reader must not silently consume
       // the reveal while the compositor is hiding the invalid frame.
       if(frame_ready)begin
        held_frames<=0;
        if(level>=FADE_FRAMES-1)begin state<=IDLE;level<=FADE_FRAMES;end
        else level<=level+1'b1;
       end else if(held_frames==HOLD_LIMIT-1)begin state<=RECOVER;level<=FADE_FRAMES;end
       else held_frames<=held_frames+1'b1;
      end
      RECOVER:if(!pending)state<=IDLE;
      default:begin state<=IDLE;level<=FADE_FRAMES;end
     endcase
    end
   end
  end
 end endgenerate
endmodule
