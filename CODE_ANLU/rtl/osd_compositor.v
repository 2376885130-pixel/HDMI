// Match video_delay and video_audio_coordinates: 21 clocks in total.
// Glyph renderer already consumed one clock; spinner consumed zero clocks.
// This mixer introduces no extra output register or change to HS/VS/DE.
module osd_compositor #(parameter LATENCY=21)(
 input wire clk,rst,input wire glyph_hit,input wire [23:0] glyph_rgb,loading_rgb,
 input wire loading_error,show_image,frame_valid,input wire [23:0] image_rgb,
 input wire subtitle_band,output wire [23:0] rgb
);
 reg [LATENCY-2:0] hit_pipe,band_pipe;
 reg [23:0] glyph_pipe[0:LATENCY-2];
 reg [23:0] loading_pipe[0:LATENCY-1];
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   hit_pipe<=0;band_pipe<=0;
   for(i=0;i<LATENCY-1;i=i+1)glyph_pipe[i]<=0;
   for(i=0;i<LATENCY;i=i+1)loading_pipe[i]<=0;
  end else begin
   band_pipe<={band_pipe[LATENCY-3:0],subtitle_band};
   hit_pipe<={hit_pipe[LATENCY-3:0],glyph_hit};glyph_pipe[0]<=glyph_rgb;
   loading_pipe[0]<=loading_error ? 24'd0 : loading_rgb;
   for(i=1;i<LATENCY-1;i=i+1)glyph_pipe[i]<=glyph_pipe[i-1];
   for(i=1;i<LATENCY;i=i+1)loading_pipe[i]<=loading_pipe[i-1];
  end
 end
 wire [23:0] background=show_image ? (frame_valid ? image_rgb : 24'd0) : loading_pipe[LATENCY-1];
 // Exactly 50% black: independent channels, no carry between RGB components.
 wire [23:0] dimmed={1'b0,background[23:17],1'b0,background[15:9],1'b0,background[7:1]};
 assign rgb=hit_pipe[LATENCY-2] ? glyph_pipe[LATENCY-2] : band_pipe[LATENCY-2] ? dimmed : background;
endmodule
