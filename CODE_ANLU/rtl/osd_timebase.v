// Elapsed MM:SS from the 50 MHz oscillator, independent of video frame rate.
// KEY1 resets to 00:00; 99:59 wraps to 00:00. Hiding the OSD never stops time.
module osd_timebase #(parameter integer CLOCK_HZ=50000000)(
 input wire clk,rst_n,output reg [15:0] elapsed_bcd
);
 localparam integer CW=(CLOCK_HZ<2)?1:$clog2(CLOCK_HZ);
 reg [CW-1:0] divider;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin divider<=0;elapsed_bcd<=0;end
  else if(divider==CLOCK_HZ-1)begin
   divider<=0;
   if(elapsed_bcd[3:0]!=9)elapsed_bcd[3:0]<=elapsed_bcd[3:0]+1'b1;
   else begin
    elapsed_bcd[3:0]<=0;
    if(elapsed_bcd[7:4]!=5)elapsed_bcd[7:4]<=elapsed_bcd[7:4]+1'b1;
    else begin
     elapsed_bcd[7:4]<=0;
     if(elapsed_bcd[11:8]!=9)elapsed_bcd[11:8]<=elapsed_bcd[11:8]+1'b1;
     else begin
      elapsed_bcd[11:8]<=0;
      elapsed_bcd[15:12]<=elapsed_bcd[15:12]==9 ? 4'd0 : elapsed_bcd[15:12]+1'b1;
     end
    end
   end
  end else divider<=divider+1'b1;
 end
endmodule
