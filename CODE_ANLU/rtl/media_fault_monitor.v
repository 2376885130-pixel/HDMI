// The source snapshot survives loader retries. Transfer a held bundle using a
// delayed event toggle; no pulse or independently changing multi-bit status CDC.
module media_fault_monitor (
 input wire source_clk,report_clk,reset_n,
 input wire [3:0] status,stage,input wire [4:0] image_index,
 input wire [31:0] sector_lba,
 output reg [3:0] fault_code=0,fault_stage=0,
 output reg [4:0] fault_image=0,
 output reg [31:0] fault_lba=0,
 output reg fault_event=0
);
 reg was_error=0,event_toggle=0;
 (* preserve = 1, keep = 1 *) reg [44:0] snapshot=0;
 // First fault is retained for debugger inspection until KEY1/power reset.
 (* keep = 1 *) reg first_valid=0;
 (* keep = 1 *) reg [44:0] first_snapshot=0;
 always @(posedge source_clk or negedge reset_n)begin
  if(!reset_n)begin was_error<=0;event_toggle<=0;snapshot<=0;first_valid<=0;first_snapshot<=0;end
  else begin
   was_error<=status>=10;
   if(status>=10 && !was_error)begin
    snapshot<={status,stage,image_index,sector_lba};event_toggle<=~event_toggle;
    if(!first_valid)begin first_valid<=1;first_snapshot<={status,stage,image_index,sector_lba};end
   end
  end
 end
 (* preserve = 1, keep = 1 *) reg [2:0] event_sync=0;
 (* preserve = 1, keep = 1 *) reg [44:0] data_meta=0,data_sync=0;
 always @(negedge report_clk or negedge reset_n)begin
  if(!reset_n)begin event_sync[0]<=0;data_meta<=0;end
  else begin event_sync[0]<=event_toggle;data_meta<=snapshot;end
 end
 always @(posedge report_clk or negedge reset_n)begin
  if(!reset_n)begin
   event_sync[2:1]<=0;data_sync<=0;
   fault_code<=0;fault_stage<=0;fault_image<=0;fault_lba<=0;fault_event<=0;
  end else begin
   event_sync[2:1]<=event_sync[1:0];
   data_sync<=data_meta;fault_event<=0;
   if(event_sync[2]!=event_sync[1])begin
    {fault_code,fault_stage,fault_image,fault_lba}<=data_sync;fault_event<=1;
   end
  end
 end
endmodule
