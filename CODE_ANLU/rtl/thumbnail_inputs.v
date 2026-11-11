// Additional preview inputs; the accepted player_front_panel is unchanged.
module thumbnail_inputs #(parameter DEBOUNCE_CYCLES=1000000)(
 input wire clk,rst_n,enabled,sw3_up,key4_n,preview_hold,
 output reg switch_down=0,output wire key4_press,volume_key_n
);
 localparam CW=DEBOUNCE_CYCLES<2?1:$clog2(DEBOUNCE_CYCLES);
 (* preserve=1,keep=1 *) reg [1:0] sw_sync=3;
 reg [CW-1:0] count=0;
 reg suppress_volume=0;
 key_debounce #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES)) key4(clk,rst_n,key4_n,key4_press);
 assign volume_key_n=key4_n || (enabled && (preview_hold || suppress_volume));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sw_sync<=3;count<=0;switch_down<=0;suppress_volume<=0;end
  else begin
   sw_sync<={sw_sync[0],sw3_up};
   if(!enabled)begin switch_down<=0;count<=0;end
   else if(switch_down==!sw_sync[1])count<=0;
   else if(count==DEBOUNCE_CYCLES-1)begin switch_down<=!sw_sync[1];count<=0;end
   else count<=count+1'b1;
   if(preview_hold)suppress_volume<=1;
   else if(key4_n)suppress_volume<=0;
  end
 end
endmodule
