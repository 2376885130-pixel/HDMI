`timescale 1ns/1ps
// Passive pixel-clock observer. Completed capture banks publish only in vblank.
// The visualizer is deliberately confined to a small bottom-right panel. It
// never writes into the 48..399 main-picture area or the subtitle area.
module promax_audio_waveform #(
 parameter integer WAVE_X=64, WAVE_Y=300, WAVE_WIDTH=512,
 parameter integer WAVE_HEIGHT=32, DECIMATE=12, STALE_FRAMES=8, EXPLICIT_Y=0,DISPLAY_GAIN=1
)(
 input wire clk,rst_n,vsync,de,
 input wire [23:0] rgb_in,input wire [9:0] pixel_x,
 input wire enable,pcm_tap_valid,input wire signed [15:0] pcm_tap_left,
 output wire [23:0] rgb_out,output wire waveform_active,input wire [9:0] pixel_y
);
 localparam integer SAMPLE_COUNT=32, SPACING=WAVE_WIDTH/SAMPLE_COUNT;
 localparam integer PANEL_TOP=WAVE_Y+4;
 localparam integer PANEL_BOTTOM=WAVE_Y+28;
 localparam integer CENTER=WAVE_Y+16;
 reg [9:0] reconstructed_y;
 wire [9:0] line_y=EXPLICIT_Y?pixel_y:reconstructed_y;
 reg de_q,vs_q,write_bank,display_bank,display_valid;
 reg [7:0] bank0[0:31],bank1[0:31];
 reg [5:0] capture_count;
 reg [7:0] decimate_count,peak0,peak1,display_peak;
 reg [7:0] window_peak;
 reg seen_sample;
 reg [7:0] idle_frames;
 wire frame_start=vs_q && !vsync;
 wire [15:0] magnitude=pcm_tap_left[15] ? (~pcm_tap_left+16'd1) : pcm_tap_left;
 // Visual gain only: never modifies PCM sent to HDMI. Saturate before truncation.
 wire [7:0] sample_abs=DISPLAY_GAIN==4 ? (|magnitude[15:14]?8'hff:magnitude[13:6]) : magnitude[15:8];
 wire stale=frame_start && !seen_sample && !pcm_tap_valid && idle_frames>=STALE_FRAMES-1;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   reconstructed_y<=0;de_q<=0;vs_q<=1;write_bank<=0;display_bank<=1;display_valid<=0;
   capture_count<=0;decimate_count<=0;peak0<=0;peak1<=0;display_peak<=0;window_peak<=0;
   seen_sample<=0;idle_frames<=0;
  end else begin
   de_q<=de;vs_q<=vsync;
   if(!vsync)reconstructed_y<=0;else if(de_q&&!de)reconstructed_y<=reconstructed_y+1'b1;
   if(pcm_tap_valid)seen_sample<=1;
   if(frame_start)begin
    seen_sample<=pcm_tap_valid;
    if(seen_sample||pcm_tap_valid)idle_frames<=0;
    else if(idle_frames<STALE_FRAMES)idle_frames<=idle_frames+1'b1;
   end
   if(stale || !enable)begin
    display_valid<=0;display_peak<=0;capture_count<=0;decimate_count<=0;
    peak0<=0;peak1<=0;window_peak<=0;
   end else if(frame_start && capture_count==SAMPLE_COUNT)begin
    display_bank<=write_bank;display_valid<=1;
    display_peak<=write_bank ? peak1 : peak0;
    write_bank<=~write_bank;capture_count<=0;decimate_count<=0;window_peak<=0;
    if(write_bank)peak0<=0;else peak1<=0;
   end else if(pcm_tap_valid && capture_count<SAMPLE_COUNT)begin
    // Peak observes every accepted sample in this capture window, not just decimated points.
    if(write_bank)begin if(sample_abs>peak1)peak1<=sample_abs;end
    else begin if(sample_abs>peak0)peak0<=sample_abs;end
    if(decimate_count==DECIMATE-1)begin
     if(write_bank)bank1[capture_count[4:0]]<=sample_abs>window_peak?sample_abs:window_peak;
     else bank0[capture_count[4:0]]<=sample_abs>window_peak?sample_abs:window_peak;
     capture_count<=capture_count+1'b1;decimate_count<=0;window_peak<=0;
    end else begin
     decimate_count<=decimate_count+1'b1;
     if(sample_abs>window_peak)window_peak<=sample_abs;
    end
   end
  end
 end
 wire in_wave=enable && de && pixel_x>=WAVE_X && pixel_x<WAVE_X+WAVE_WIDTH &&
              line_y>=WAVE_Y && line_y<WAVE_Y+WAVE_HEIGHT;
 wire [9:0] local_x=pixel_x-WAVE_X;
 wire [4:0] sample_index=local_x/SPACING;
 wire [7:0] selected_sample=display_bank ? bank1[sample_index] : bank0[sample_index];
 // Each column represents magnitude, not an FFT frequency bin.
 wire [7:0] bar_height=selected_sample>=48?8'd12:{2'd0,selected_sample[7:2]};
 wire signed [11:0] sample_top=$signed(CENTER)-$signed({4'd0,bar_height});
 wire signed [11:0] sample_bottom=$signed(CENTER)+$signed({4'd0,bar_height});
 wire signed [11:0] scan_y=$signed({2'b00,line_y});
 wire bar_pixel=in_wave && display_valid && bar_height!=0 && (local_x%SPACING)<SPACING-1 && line_y>=PANEL_TOP && line_y<PANEL_BOTTOM &&
                 scan_y>=sample_top && scan_y<=sample_bottom;
 wire axis_pixel=in_wave && line_y==CENTER;
 wire [7:0] peak_height=display_peak>>3;
 wire peak_pixel=enable && de && display_valid && pixel_x>=WAVE_X+WAVE_WIDTH+8 &&
                 pixel_x<WAVE_X+WAVE_WIDTH+16 && line_y>=WAVE_Y+WAVE_HEIGHT-peak_height &&
                 line_y<WAVE_Y+WAVE_HEIGHT;
 wire panel_pixel=enable && de && pixel_x>=WAVE_X && pixel_x<WAVE_X+WAVE_WIDTH &&
                   line_y>=WAVE_Y && line_y<WAVE_Y+WAVE_HEIGHT;
 assign waveform_active=bar_pixel||axis_pixel||peak_pixel||panel_pixel;
 assign rgb_out=bar_pixel ? (bar_height>=12?24'hffbc55:line_y<CENTER?24'h50e2c0:24'h279cac) : peak_pixel ? 24'hffb020 :
                axis_pixel ? 24'h406060 : panel_pixel ? 24'h142b40 : rgb_in;
 // synthesis translate_off
 initial begin
  if(DECIMATE<1||DECIMATE>256||WAVE_WIDTH<32||WAVE_WIDTH%32!=0||WAVE_HEIGHT!=32||
     STALE_FRAMES<1||STALE_FRAMES>255||WAVE_X<0||WAVE_Y<0||WAVE_X+WAVE_WIDTH+16>640||WAVE_Y+WAVE_HEIGHT>480)
   $fatal(1,"unsupported waveform geometry/parameters");
 end
 // synthesis translate_on
endmodule
