// Hold the SD interface idle until card power settles; retry transient failures.
module tf_startup_control #(
 parameter integer POWER_WAIT_CYCLES=50000000,
 parameter integer SWITCH_WAIT_CYCLES=500000,
 parameter integer RETRY_WAIT_CYCLES=25000000,
 parameter integer ERROR_WAIT_CYCLES=500000,
 parameter integer MAX_RETRIES=3
)(input wire clk,reset_n,locked,load_error,
 output reg run_enable=0,input wire fast_start,
 input wire load_success,output reg exhausted_pulse=0);
 reg [31:0] wait_count=0,error_count=0;
 localparam integer RETRY_BITS=(MAX_RETRIES<1)?1:$clog2(MAX_RETRIES+1);
 reg [RETRY_BITS-1:0] retry_count=0;
 reg exhausted_sent=0;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin exhausted_pulse<=0; run_enable<=0;wait_count<=0;error_count<=0;retry_count<=0;exhausted_sent<=0;end
  else begin
   exhausted_pulse<=0;
   if(!locked) begin run_enable<=0;wait_count<=0;error_count<=0;retry_count<=0;exhausted_sent<=0;end
  else if(!run_enable) begin
   error_count<=0;
   if(wait_count==(retry_count!=0 ? RETRY_WAIT_CYCLES-1 : (fast_start ? SWITCH_WAIT_CYCLES-1 : POWER_WAIT_CYCLES-1))) begin
    run_enable<=1;wait_count<=0;
   end else wait_count<=wait_count+1'b1;
  end else if(load_success)begin retry_count<=0;error_count<=0;exhausted_sent<=0;end
  else if(load_error && !exhausted_sent) begin
   if(error_count==ERROR_WAIT_CYCLES-1) begin
    error_count<=0;
    if(retry_count<MAX_RETRIES)begin
     run_enable<=0;wait_count<=0;retry_count<=retry_count+1'b1;
    end else begin exhausted_pulse<=1;exhausted_sent<=1;end
   end else error_count<=error_count+1'b1;
  end else error_count<=0;
  end
 end
endmodule
