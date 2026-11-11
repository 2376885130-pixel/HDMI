// SW1: physical up=1 disables autoplay. KEY1 reset always leaves playback
// stopped, even with SW1 down; observe a debounced up before down can enable.
// KEY4 changes HDMI amplitude only; buzzer wiring remains board controlled.
module player_front_panel #(parameter DEBOUNCE_CYCLES=1000000)(
 input wire clk,rst_n,sw1_up,key_volume_n,
 output wire autoplay_enable,output reg [2:0] volume_level=2
);
 localparam CW=DEBOUNCE_CYCLES<2?1:$clog2(DEBOUNCE_CYCLES);
 (* preserve=1,keep=1 *) reg [1:0] sw_sync=0;
 reg stable_up=0,candidate=0,armed=0;
 reg [CW-1:0] count=0;
 wire volume_press;
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) u_volume(
  clk,rst_n,key_volume_n,volume_press);
 assign autoplay_enable=armed && !stable_up;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sw_sync<=0;stable_up<=0;candidate<=0;count<=0;armed<=0;volume_level<=2;end
  else begin
   sw_sync<={sw_sync[0],sw1_up};
   if(sw_sync[1]==stable_up)begin count<=0;candidate<=sw_sync[1];end
   else if(sw_sync[1]!=candidate)begin
    candidate<=sw_sync[1];
    if(DEBOUNCE_CYCLES==1)begin stable_up<=sw_sync[1];count<=0;end
    else count<=1;
   end else if(count==DEBOUNCE_CYCLES-1)begin stable_up<=candidate;count<=0;end
   else count<=count+1'b1;
   if(stable_up)armed<=1;
   if(volume_press)volume_level<=volume_level==4 ? 3'd0 : volume_level+1'b1;
  end
 end
endmodule
