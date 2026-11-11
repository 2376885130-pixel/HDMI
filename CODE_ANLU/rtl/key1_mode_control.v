// Raw 50 MHz board clock: this controller must not depend on PLL lock or KEY1 reset.
// FPGA configuration initializes the POR counter; long press holds reset until release.
module key1_mode_control #(
 parameter integer POR_CYCLES=500000, FILTER=1000000, LONG_CYCLES=100000000
)(input wire clk,key1_n,output wire reset_n,output reg basic_request=1,
 output reg short_event=0,output wire pll_reset_n);
 localparam PW=$clog2(POR_CYCLES+1),DW=$clog2(FILTER+1),LW=$clog2(LONG_CYCLES+1);
 reg [PW-1:0] por_count=0;
 reg por_done=0;
 (* async_reg="true",preserve=1,keep=1 *) reg [1:0] key_sync=3;
 reg stable=1,armed=0,long_fired=0;
 reg [DW-1:0] debounce=0;
 reg [LW-1:0] held=0;
 assign reset_n=por_done&&!long_fired;
 // Match FOUR_CLEAN's released-KEY1 power-up: the PLL starts immediately.
 // POR still holds all application logic, but must not gate PLL startup.
 // Only a qualified long press resets the PLL; short mode presses never do.
 assign pll_reset_n=!long_fired;
 always @(posedge clk)begin
  key_sync<={key_sync[0],key1_n};short_event<=0;
  if(!por_done)begin
   if(por_count==POR_CYCLES-1)por_done<=1;else por_count<=por_count+1'b1;
   stable<=1;debounce<=0;armed<=0;held<=0;long_fired<=0;basic_request<=1;
  end else begin
   if(key_sync[1]==stable)debounce<=0;
   else if(debounce==FILTER-1)begin
    debounce<=0;stable<=key_sync[1];
    if(!key_sync[1])begin armed<=1;held<=0;end
    else begin
     if(armed&&!long_fired)begin basic_request<=~basic_request;short_event<=1;end
     armed<=0;held<=0;long_fired<=0;
    end
   end else debounce<=debounce+1'b1;
   if(!stable&&armed&&!long_fired)begin
    if(held==LONG_CYCLES-1)begin long_fired<=1;basic_request<=1;end
    else held<=held+1'b1;
   end
  end
 end
endmodule
