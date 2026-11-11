// Metadata consumes the original SD stream in both catalog and image loads.
// Never parse header bytes through the pixel replay RAM. All fields are
// little endian; a byte-enabled shift register handles arbitrarily long gaps.
// Complete/valid are held until the next probe/load, not recomputed from a
// subsequently selected directory entry. Supported: positive RGB24 BI_RGB.
module bmp24_header(
 input wire clk,rst,start,byte_valid,input wire [7:0] data,
 input wire [31:0] position,file_size,
 output reg complete,output reg valid,
 output reg [11:0] width,height,
 output reg [31:0] pixel_offset,output reg [13:0] stride,
 output wire [3:0] reject_reason
);
 reg [31:0] assembly,declared_size,dib_size;
 reg [6:0] fields_ok;
 reg [25:0] payload;
 reg [32:0] required_end,dib_end;
 reg sizes_ok;
 wire [31:0] assembled={data,assembly[31:8]};
 // Observability only: no change to complete/valid or the acceptance criteria.
 // 0 accepted; 1..7 field checks; 8..11 length checks; 12 incomplete.
 assign reject_reason=!complete ? 4'd12 : valid ? 4'd0 :
  !fields_ok[0] ? 4'd1 : !fields_ok[1] ? 4'd2 :
  !fields_ok[2] ? 4'd3 : !fields_ok[3] ? 4'd4 :
  !fields_ok[4] ? 4'd5 : !fields_ok[5] ? 4'd6 :
  !fields_ok[6] ? 4'd7 : pixel_offset<54 ? 4'd8 :
  dib_end>{1'b0,pixel_offset} ? 4'd9 :
  required_end>{1'b0,declared_size} ? 4'd10 : 4'd11;
 // Width is captured by byte21, height by25, offset by13 and DIB by17.
 // These arithmetic stages settle well before the byte53 commit boundary,
 // including a source delivering one byte on every clock.
 always @(posedge clk)begin
  stride<=({2'b0,width}+{1'b0,width,1'b0}+14'd3)&14'h3ffc;
  payload<=stride*height;
  required_end<={1'b0,pixel_offset}+{7'd0,payload};
  dib_end<={1'b0,dib_size}+33'd14;
  sizes_ok<=pixel_offset>=54 && dib_end<={1'b0,pixel_offset} &&
            required_end<={1'b0,declared_size} && declared_size<=file_size;
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   assembly<=0;declared_size<=0;dib_size<=0;fields_ok<=0;
   width<=0;height<=0;pixel_offset<=0;complete<=0;valid<=0;
  end else if(start)begin
   assembly<=0;declared_size<=0;dib_size<=0;fields_ok<=0;
   width<=0;height<=0;pixel_offset<=0;complete<=0;valid<=0;
  end else if(byte_valid && !complete)begin
   assembly<=assembled;
   case(position)
    1:fields_ok[0]<=data==8'h4d && assembly[31:24]==8'h42;
    5:declared_size<=assembled;
    13:pixel_offset<=assembled;
    17:begin dib_size<=assembled;fields_ok[1]<=assembled>=40;end
    21:begin width<=assembled[11:0];fields_ok[2]<=assembled>=1 && assembled<=2048;end
    25:begin height<=assembled[11:0];fields_ok[3]<=assembled>=1 && assembled<=2048;end
    27:fields_ok[4]<=assembled[31:16]==16'd1;
    29:fields_ok[5]<=assembled[31:16]==16'd24;
    33:fields_ok[6]<=assembled==0;
    53:begin complete<=1;valid<=(&fields_ok) && sizes_ok;end
   endcase
  end
 end
endmodule
