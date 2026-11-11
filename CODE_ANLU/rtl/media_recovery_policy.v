// Policy only: tf_startup_control owns reset timing and per-image retries.
// Bound a failed traversal to the catalog size, even if every file is broken.
module media_recovery_policy (
 input wire clk,reset_n,image_shown,manual_restart,
 input wire exhausted_pulse,input wire [3:0] fault_code,fault_stage,
 input wire [5:0] image_total,
 output reg next_pulse=0,output reg stopped=0
);
 reg [5:0] skipped=0;
 wire file_failure=fault_stage==5 &&
   (fault_code==12 || fault_code==13 || fault_code==14);
 always @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin skipped<=0;next_pulse<=0;stopped<=0;end
  else begin
   next_pulse<=0;
   if(image_shown || manual_restart)begin skipped<=0;stopped<=0;end
   else if(exhausted_pulse && !stopped)begin
    if(file_failure && image_total>1 && skipped<image_total-1'b1)begin
     skipped<=skipped+1'b1;next_pulse<=1;
    end else stopped<=1;
   end
  end
 end
endmodule
