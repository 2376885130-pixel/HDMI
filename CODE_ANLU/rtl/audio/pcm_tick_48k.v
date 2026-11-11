`timescale 1ns/1ps
// Stable 48 kHz cadence for the external media-only audio path. Keeping this
// cadence alive while the WAV source is muted makes HDMI carry explicit zero
// PCM packets instead of leaving the sink without audio samples.
module pcm_tick_48k #(parameter integer CLOCK_HZ=25000000, SAMPLE_HZ=48000)(
 input wire clk,input wire rst_n,output wire tick
);
 reg [24:0] accumulator;
 assign tick=accumulator>=CLOCK_HZ-SAMPLE_HZ;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n) accumulator<=0;
  else if(tick) accumulator<=accumulator+SAMPLE_HZ-CLOCK_HZ;
  else accumulator<=accumulator+SAMPLE_HZ;
 end
endmodule
