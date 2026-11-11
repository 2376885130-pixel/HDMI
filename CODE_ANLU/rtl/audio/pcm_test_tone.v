`timescale 1ns/1ps
// 48 kHz average sample cadence from the pixel clock. Eight stereo frames
// absorb packetizer backpressure. Enable controls sound, not sample cadence.
module pcm_test_tone #(
 parameter integer CLOCK_HZ=25000000,
 parameter integer SAMPLE_HZ=48000,
 parameter integer TONE_HZ=1000
)(
 input wire clk,rst_n,enable,
 output wire sample_valid,input wire sample_ready,
 output wire signed [15:0] sample_left,sample_right,
 output wire [3:0] rom_index,output wire sample_accepted,
 output reg overflow
);
 localparam integer RATE_BITS=$clog2(CLOCK_HZ+1);
 localparam [63:0] PHASE_STEP=(64'd4294967296*TONE_HZ+SAMPLE_HZ/2)/SAMPLE_HZ;
 reg [RATE_BITS-1:0] rate=0;
 reg [31:0] phase=0;
 reg signed [15:0] fifo[0:7];
 reg [2:0] wr=0,rd=0;
 reg [3:0] count=0;
 wire tick=rate>=CLOCK_HZ-SAMPLE_HZ;
 wire pop=sample_valid && sample_ready;
 wire push=tick && (count<8 || pop);
 assign sample_valid=count!=0;
 assign sample_left=fifo[rd];
 assign sample_right=fifo[rd];
 assign sample_accepted=pop;
 assign rom_index=phase[31:28];
 function signed [15:0] sine_sample(input [3:0] index);
  case(index)
   0:sine_sample=0;1:sine_sample=4592;2:sine_sample=8485;3:sine_sample=11087;
   4:sine_sample=12000;5:sine_sample=11087;6:sine_sample=8485;7:sine_sample=4592;
   8:sine_sample=0;9:sine_sample=-4592;10:sine_sample=-8485;11:sine_sample=-11087;
   12:sine_sample=-12000;13:sine_sample=-11087;14:sine_sample=-8485;15:sine_sample=-4592;
  endcase
 endfunction
 // synthesis translate_off
 initial if(CLOCK_HZ<SAMPLE_HZ || SAMPLE_HZ<1 || TONE_HZ<1 || 2*TONE_HZ>=SAMPLE_HZ)
  $fatal(1,"Invalid PCM rate or tone parameters");
 // synthesis translate_on
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin rate<=0;phase<=0;wr<=0;rd<=0;count<=0;overflow<=0;end
  else begin
   if(tick)begin rate<=rate-(CLOCK_HZ-SAMPLE_HZ);phase<=phase+PHASE_STEP[31:0];end
   else rate<=rate+SAMPLE_HZ;
   if(push)begin fifo[wr]<=enable?sine_sample(phase[31:28]):16'sd0;wr<=wr+1'b1;end
   if(tick && !push)overflow<=1;
   if(pop)rd<=rd+1'b1;
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;default:;endcase
  end
 end
endmodule
