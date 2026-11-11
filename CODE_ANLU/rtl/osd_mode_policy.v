// Only foreground presentation state drives the loading UI. Loader activity
// alone is deliberately absent: cache prefetch must not disturb narration.
module osd_mode_policy #(parameter SIMULTANEOUS_ASCII=0)(
 input wire clk,rst,frame_start,home,guide_requested,menu,shown,
 input wire preview_request,visible_preview,zoom_active,visible_zoom,
 input wire [2:0] requested_page,visible_page,
 input wire [4:0] requested_index,displayed_index,
 input wire builder_busy,transition_busy,audio_error,
 input wire [3:0] load_status,
 output reg loading,ascii_allowed,chinese_allowed,wave_allowed,
 output reg [3:0] image_fault,output reg audio_warning
);
 wire fault=load_status>=10;
 wire foreground=!home && (preview_request ?
     (!zoom_active && (!visible_preview || requested_page!=visible_page || builder_busy)) :
     (!shown || visible_preview || requested_index!=displayed_index || transition_busy));
 wire full=!home && shown && !preview_request && !visible_preview && !zoom_active && !visible_zoom;
 always @(posedge clk or posedge rst)begin
  if(rst)begin loading<=0;ascii_allowed<=0;chinese_allowed<=0;wave_allowed<=0;image_fault<=0;audio_warning<=0;end
  else if(frame_start)begin
   image_fault<=fault?load_status:4'd0;
   audio_warning<=!home && guide_requested && audio_error && !fault;
   loading<=foreground && !fault;
   ascii_allowed<=full && (SIMULTANEOUS_ASCII || !guide_requested) && !menu && !foreground && !fault;
   chinese_allowed<=full && guide_requested && !menu && !foreground && !fault && !audio_error;
   wave_allowed<=full && guide_requested && !foreground && !fault && !audio_error;
  end
 end
endmodule
