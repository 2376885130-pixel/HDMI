// SW2 is active-low on the board: down=0 requests reverse autoplay.
// The switch is sampled into sys_clk and accepted only after a stable dwell.
module sw2_direction_filter #(
 parameter integer DEBOUNCE_CYCLES=1000000
)(input wire clk,rst_n,input wire sw2_up,output wire reverse_mode);
 localparam integer CW=DEBOUNCE_CYCLES<2?1:$clog2(DEBOUNCE_CYCLES);
 (* async_reg="true",preserve=1,keep=1 *) reg meta,sync;
 reg candidate,stable;reg [CW-1:0] count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin meta<=1;sync<=1;candidate<=1;stable<=1;count<=0;end
  else begin
   meta<=sw2_up;sync<=meta;
   if(sync==stable)begin candidate<=sync;count<=0;end
   else if(sync!=candidate)begin
    candidate<=sync;
    if(DEBOUNCE_CYCLES==1)begin stable<=sync;count<=0;end
    else count<=1;
   end else if(count==DEBOUNCE_CYCLES-1)begin stable<=candidate;count<=0;end
   else count<=count+1'b1;
  end
 end
 assign reverse_mode=!stable;
endmodule
