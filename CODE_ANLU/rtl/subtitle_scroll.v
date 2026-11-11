// One pixel per displayed frame (~59.524 px/s). Reset/new text starts at left.
// Cycle includes the whole text, viewport and a 32-pixel gap.
module subtitle_scroll(input wire clk,rst_n,frame_start,changed,enable,
 input wire [3:0] length,output reg [9:0] offset);
 wire [9:0] cycle=10'd640+length*10'd18;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)offset<=0;
  else if(changed || !enable || length==0)offset<=0;
  else if(frame_start)offset<=offset==cycle-1 ? 10'd0 : offset+1'b1;
 end
endmodule
