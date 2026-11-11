// Synchronize active-low KEY input; one pulse per press, no repeat while held.
module key_debounce #(parameter integer DEBOUNCE_CYCLES=1000000)(
 input wire clk,reset_n,key_n,output reg pressed=0
);
 reg [1:0] key_sync=2'b11;
 reg stable=1;
 localparam integer COUNT_BITS=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES);
 reg [COUNT_BITS-1:0] count=0;
 // synthesis translate_off
 initial if(DEBOUNCE_CYCLES<1) $fatal(1,"DEBOUNCE_CYCLES must be positive");
 // synthesis translate_on
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin key_sync<=3;stable<=1;count<=0;pressed<=0;end
  else begin
   key_sync<={key_sync[0],key_n};pressed<=0;
   if(key_sync[1]==stable)count<=0;
   else if(count==DEBOUNCE_CYCLES-1) begin
    stable<=key_sync[1];count<=0;
    if(!key_sync[1]) pressed<=1;
   end else count<=count+1'b1;
  end
 end
endmodule
