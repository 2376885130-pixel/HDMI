// Acknowledged full-bundle CDC, then atomic frame-boundary application.
module picture_param_commit(
 input wire src_clk,src_rst_n,menu_active,selected_contrast,
 input wire [7:0] brightness,contrast,
 input wire pixel_clk,pixel_rst,frame_start,
 output reg menu_frame,selected_frame,
 output reg [7:0] brightness_frame,contrast_frame
);
 wire [18:0] snapshot;
 osd_state_snapshot #(.WIDTH(19)) u_snapshot(
  .src_clk(src_clk),.src_rst_n(src_rst_n),
  .src_data({1'b1,menu_active,selected_contrast,brightness,contrast}),
  .dst_clk(pixel_clk),.dst_rst_n(!pixel_rst),.dst_data(snapshot));
 always @(posedge pixel_clk or posedge pixel_rst)begin
  if(pixel_rst)begin menu_frame<=0;selected_frame<=0;brightness_frame<=0;contrast_frame<=128;end
  else if(frame_start && snapshot[18])
   {menu_frame,selected_frame,brightness_frame,contrast_frame}<=snapshot[17:0];
 end
endmodule
