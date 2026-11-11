// Publish a completed catalog as a held bundle, never sample live scan counters.
// Reset by KEY1/PLL loss only, not by a per-file loader reset. The source holds
// count across retries; the toggle announces a new, complete catalog (even empty).
module catalog_snapshot_bridge(
 input wire source_clk,control_clk,reset_n,
 input wire catalog_valid,input wire [5:0] catalog_total,
 output reg [5:0] image_total=0,output reg catalog_event=0
);
 reg valid_q=0,event_toggle=0;
 (* preserve=1,keep=1 *) reg [5:0] snapshot=0;
 always @(posedge source_clk or negedge reset_n)begin
  if(!reset_n)begin valid_q<=0;event_toggle<=0;snapshot<=0;end
  else begin
   valid_q<=catalog_valid;
   if(catalog_valid && !valid_q)begin
    snapshot<=catalog_total;event_toggle<=~event_toggle;
   end
  end
 end
 (* preserve=1,keep=1 *) reg [5:0] data_meta=0,data_sync=0;
 (* preserve=1,keep=1 *) reg [2:0] event_sync=0;
 always @(negedge control_clk or negedge reset_n)begin
  if(!reset_n)begin data_meta<=0;event_sync[0]<=0;end
  else begin data_meta<=snapshot;event_sync[0]<=event_toggle;end
 end
 always @(posedge control_clk or negedge reset_n)begin
  if(!reset_n)begin data_sync<=0;event_sync[2:1]<=0;image_total<=0;catalog_event<=0;end
  else begin
   data_sync<=data_meta;event_sync[2:1]<=event_sync[1:0];catalog_event<=0;
   if(event_sync[2]!=event_sync[1])begin image_total<=data_sync;catalog_event<=1;end
  end
 end
endmodule
