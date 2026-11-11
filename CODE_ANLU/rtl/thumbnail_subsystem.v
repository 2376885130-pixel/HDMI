// Three clock domains connected through held bundles or four-phase leases.
module thumbnail_subsystem #(parameter ANIMATIONS=0,RUNTIME_MODE=0)(
 input wire sys_clk,sys_rst_n,mem_clk,mem_rst,pixel_clk,video_rst,
 input wire switch_down,key4_press,next_press,prev_press,first_shown,full_ready,
 input wire [4:0] current_index,input wire [5:0] image_total,
 input wire load_error,input wire [4:0] displayed_index,
 output wire preview_hold,select_valid,output wire [4:0] select_index,
 input wire visible_preview,visible_bank,input wire [2:0] visible_page,input wire [3:0] visible_valid,
 input wire [1:0] visible_focus,
 output wire preview_request,output wire [2:0] requested_page,output wire [4:0] target_index,
 output wire [1:0] focus_video,
 output wire source_req,output wire [4:0] source_index,
 input wire source_ack,source_ok,input wire [1:0] source_slot,
 output wire dma_req,dma_write,output wire [20:0] dma_addr,output wire [31:0] dma_wdata,
 input wire dma_accept,dma_done,dma_valid,input wire [31:0] dma_rdata,input wire [6:0] dma_word,
 output wire page_toggle,page_bank,output wire [2:0] page_number,output wire [3:0] page_valid,input wire page_ack,
 output wire zoom_active_video,output wire builder_busy,output wire [9:0] builder_progress,output wire page_zoom,
 input wire effect_bypass
);
 wire session;wire [2:0] page;wire [1:0] focus;
 wire zoom_request,zoom_done;wire [4:0] zoom_index;
 (* preserve=1,keep=1 *) reg [2:0] zoom_done_sync;
 always @(posedge sys_clk or negedge sys_rst_n)
  if(!sys_rst_n)zoom_done_sync<=0;else zoom_done_sync<={zoom_done_sync[1:0],zoom_done};
 wire [9:0] visible_sys;
 osd_state_snapshot #(.WIDTH(10)) u_visible(
  .src_clk(pixel_clk),.src_rst_n(~video_rst),.src_data({visible_focus,visible_preview,visible_page,visible_valid}),
  .dst_clk(sys_clk),.dst_rst_n(sys_rst_n),.dst_data(visible_sys));
 thumbnail_controller #(.ANIMATIONS(ANIMATIONS),.RUNTIME_MODE(RUNTIME_MODE)) u_control(.clk(sys_clk),.rst_n(sys_rst_n),.switch_down(switch_down),.effect_bypass(effect_bypass),
  .zoom_request(zoom_request),.zoom_index(zoom_index),.zoom_done(zoom_done_sync[2]),
  .load_error(load_error),.displayed_index(displayed_index),
  .first_shown(first_shown),.full_ready(full_ready && !visible_sys[7]),
  .key4_press(key4_press),.next_press(next_press),.prev_press(prev_press),
  .current_index(current_index),.image_total(image_total),
  .visible_preview(visible_sys[7]),.visible_page(visible_sys[6:4]),.visible_valid(visible_sys[3:0]),
  .visible_focus(visible_sys[9:8]),
  .session(session),.page(page),.focus(focus),.hold_fullscreen(preview_hold),
  .select_valid(select_valid),.select_index(select_index));
 wire [11:0] pixel_control;
 osd_state_snapshot #(.WIDTH(12)) u_pixel_control(
  .src_clk(sys_clk),.src_rst_n(sys_rst_n),
  .src_data({session,zoom_request,page,focus,select_valid ? select_index : current_index}),
  .dst_clk(pixel_clk),.dst_rst_n(~video_rst),.dst_data(pixel_control));
 assign {preview_request,zoom_active_video,requested_page,focus_video,target_index}=pixel_control;
 wire [15:0] memory_control;
 osd_state_snapshot #(.WIDTH(16)) u_memory_control(
  .src_clk(sys_clk),.src_rst_n(sys_rst_n),.src_data({session,zoom_request,zoom_index,page,image_total}),
  .dst_clk(mem_clk),.dst_rst_n(~mem_rst),.dst_data(memory_control));
 (* preserve=1,keep=1 *) reg [2:0] ack_sync,page_ack_sync;
 (* preserve=1,keep=1 *) reg [1:0] bank_sync;
 reg ok_meta,ok_sync;reg [1:0] slot_meta,slot_sync;
 always @(posedge mem_clk or posedge mem_rst)begin
  if(mem_rst)begin ack_sync<=0;page_ack_sync<=0;bank_sync<=0;ok_meta<=0;ok_sync<=0;slot_meta<=0;slot_sync<=0;end
  else begin
   ack_sync<={ack_sync[1:0],source_ack};page_ack_sync<={page_ack_sync[1:0],page_ack};
   bank_sync<={bank_sync[0],visible_bank};ok_meta<=source_ok;ok_sync<=ok_meta;
   slot_meta<=source_slot;slot_sync<=slot_meta;
  end
 end
 thumbnail_page_builder u_builder(.clk(mem_clk),.rst(mem_rst),.enable(memory_control[15] && !memory_control[14]),
  .zoom_enable(memory_control[14]),.zoom_index(memory_control[13:9]),.zoom_done(zoom_done),.progress_rows(builder_progress),.page_zoom(page_zoom),
  .requested_page(memory_control[8:6]),.image_total(memory_control[5:0]),.visible_bank(bank_sync[1]),
  .source_req(source_req),.source_index(source_index),.source_ack(ack_sync[2]),.source_ok(ok_sync),.source_slot(slot_sync),
  .dma_req(dma_req),.dma_write(dma_write),.dma_addr(dma_addr),.dma_wdata(dma_wdata),
  .dma_accept(dma_accept),.dma_done(dma_done),.dma_valid(dma_valid),.dma_rdata(dma_rdata),.dma_word(dma_word),
  .page_toggle(page_toggle),.page_bank(page_bank),.page_number(page_number),.page_valid(page_valid),.page_ack(page_ack_sync[2]),.busy(builder_busy));
endmodule
