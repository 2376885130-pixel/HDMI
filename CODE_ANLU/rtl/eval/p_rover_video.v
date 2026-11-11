module p_rover_video(input wire pixel_clk,rst_n,input wire [9:0] x,y,
 input wire de,hs,vs,input wire [63:0] state,output wire [9:0] channel0,channel1,channel2,
 input wire [1:0] model_id);
 wire [23:0] rgb;
 p_rover_scan scan(pixel_clk,rst_n,x,y,de,state,rgb,model_id);
 reg [23:0] rgb_q;reg de_q,hs_q,vs_q;reg de_s,hs_s,vs_s,de_t,hs_t,vs_t;
 always @(posedge pixel_clk or negedge rst_n)begin
  if(!rst_n)begin rgb_q<=0;de_q<=0;hs_q<=1;vs_q<=1;de_s<=0;hs_s<=1;vs_s<=1;de_t<=0;hs_t<=1;vs_t<=1;end
  else begin rgb_q<=rgb;de_s<=de;hs_s<=hs;vs_s<=vs;de_t<=de_s;hs_t<=hs_s;vs_t<=vs_s;de_q<=de_t;hs_q<=hs_t;vs_q<=vs_t;end
 end
 hdmi_tmds_channel_encoder #(.CHANNEL(0)) enc0(pixel_clk,rst_n,de_q?3'd1:3'd0,rgb_q[7:0],4'd0,{vs_q,hs_q},channel0);
 hdmi_tmds_channel_encoder #(.CHANNEL(1)) enc1(pixel_clk,rst_n,de_q?3'd1:3'd0,rgb_q[15:8],4'd0,2'd0,channel1);
 hdmi_tmds_channel_encoder #(.CHANNEL(2)) enc2(pixel_clk,rst_n,de_q?3'd1:3'd0,rgb_q[23:16],4'd0,2'd0,channel2);
endmodule
