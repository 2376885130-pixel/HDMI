`timescale 1ns/1ps
// Commit audio changes only when a new image is actually presented.
module media_hdmi_audio_bridge #(parameter EXPLICIT_COMMIT=0,USER_VOLUME=0,EXTERNAL_PCM=0,SILENT_FALLBACK=0)(
 input wire pixel_clk,pixel_rst_n,
 input wire video_hsync,video_vsync,video_de,video_line_active,
 input wire [9:0] video_x,input wire [23:0] video_rgb,
 output wire [9:0] channel0_symbol,channel1_symbol,channel2_symbol,
 output wire sequence_error,tone_overflow,pcm_contract_error,
 input wire image_shown,input wire [4:0] displayed_index,input wire present_commit,
 input wire [8:0] volume,
 input wire wav_selected,wav_valid,input wire signed[15:0]wav_left,wav_right,
 output wire wav_ready,audio_tick,
 output reg pcm_tap_valid,output reg signed [15:0] pcm_tap_left
);
 wire sv,sr,pv,pr;wire signed[15:0] sl,sright,pl,pright;
 wire tone_tick,silent_tick;
 always @(posedge pixel_clk or negedge pixel_rst_n)begin
  if(!pixel_rst_n)begin pcm_tap_valid<=0;pcm_tap_left<=0;end
  else begin
   pcm_tap_valid<=pv&&pr;
   if(pv&&pr)pcm_tap_left<=pl;
  end
 end
 reg shown_q;
 always @(posedge pixel_clk or negedge pixel_rst_n)
  if(!pixel_rst_n)shown_q<=0;else shown_q<=image_shown;
 wire commit=EXPLICIT_COMMIT ? present_commit : image_shown && !shown_q;
 generate if(EXTERNAL_PCM && SILENT_FALLBACK) begin:media_only_source
   pcm_tick_48k tick_source(.clk(pixel_clk),.rst_n(pixel_rst_n),.tick(silent_tick));
   assign audio_tick=silent_tick;
   assign sv=1'b0; assign sl=16'sd0; assign sright=16'sd0;
 end else begin:tone_source
   pcm_media_tone #(.SMOOTH_VOLUME(USER_VOLUME)) source(.clk(pixel_clk),.rst_n(pixel_rst_n),.media_id(displayed_index),
    .media_commit(commit),.volume(USER_VOLUME ? volume : 9'd128),.sample_valid(sv),.sample_ready(sr),
    .sample_left(sl),.sample_right(sright),.overflow(tone_overflow),.blip_active(),.cadence_tick(tone_tick));
   assign audio_tick=tone_tick;
 end endgenerate
 wire mv,mr;wire signed[15:0]ml,mt;
 generate if(EXTERNAL_PCM && SILENT_FALLBACK)begin:continuous_media
  pcm_continuous_output output_pcm(.clk(pixel_clk),.rst_n(pixel_rst_n),.tick(audio_tick),
    .selected(wav_selected),.source_valid(wav_valid),.source_ready(wav_ready),
    .source_left(wav_left),.source_right(wav_right),.sample_valid(mv),.sample_ready(mr),
    .sample_left(ml),.sample_right(mt),.overflow(tone_overflow));
  assign sr=1'b0;
 end else if(EXTERNAL_PCM)begin:external_source
  pcm_source_select selector(pixel_clk,pixel_rst_n,wav_selected,sv,sr,SILENT_FALLBACK?16'sd0:sl,SILENT_FALLBACK?16'sd0:sright,
   wav_valid,wav_ready,wav_left,wav_right,mv,mr,ml,mt);
 end else begin:legacy_source
  assign mv=sv;assign sr=mr;assign ml=sl;assign mt=sright;assign wav_ready=0;
 end endgenerate
 m06_pcm_contract_adapter contract(.clk(pixel_clk),.rst_n(pixel_rst_n),
  .source_valid(mv),.source_ready(mr),.source_left(ml),.source_right(mt),
  .pcm_valid(pv),.pcm_ready(pr),.pcm_left(pl),.pcm_right(pright),.contract_error(pcm_contract_error));
 hdmi_audio_symbol_core core(.pixel_clk(pixel_clk),.rst_n(pixel_rst_n),
  .video_hsync(video_hsync),.video_vsync(video_vsync),.video_de(video_de),
  .video_x(video_x),.video_line_active(video_line_active),.video_rgb(video_rgb),
  .sample_valid(pv),.sample_ready(pr),.sample_left(pl),.sample_right(pright),
  .channel0_symbol(channel0_symbol),.channel1_symbol(channel1_symbol),.channel2_symbol(channel2_symbol),.sequence_error(sequence_error));
endmodule
