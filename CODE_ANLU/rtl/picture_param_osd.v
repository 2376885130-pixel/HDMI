// Small two-row panel; bars map the full ranges, numbers show exact values.
// Coordinates already aligned with adjusted RGB. No additional pixel latency.
module picture_param_osd(
 input wire [9:0] x,y,input wire active,selected,
 input wire [7:0] brightness,contrast,input wire [23:0] rgb_in,
 output wire [23:0] rgb_out
);
 wire panel=active && x>=144 && x<496 && y>=160 && y<288;
 wire row=y>=224;
 wire chosen=row==selected;
 wire [7:0] amount=row?contrast:(brightness ^ 8'h80);
 wire [7:0] magnitude=row?contrast:brightness[7]?(~brightness+8'd1):brightness;
 wire [3:0] hundreds=magnitude>=200?4'd2:magnitude>=100?4'd1:4'd0;
 wire [7:0] rest=magnitude-hundreds*8'd100;
 wire [3:0] tens=rest/8'd10;
 wire [3:0] ones=rest-tens*8'd10;
 wire [9:0] dx=x-160,dy=y-(row?10'd232:10'd168);
 wire [5:0] char_index=dx[9:4];
 reg [7:0] ch;
 always @*begin
  ch=32;
  case(char_index)
   0:ch=row?"C":"B";
   1:ch="R";
   2:ch=row?"T":"I";
   3:ch=row?32:"G";
   4:ch=row?32:"H";
   5:ch=row?32:"T";
   7:ch=!row && brightness[7]?"-":"+";
   8:ch=48+hundreds;
   9:ch=48+tens;
   10:ch=48+ones;
  endcase
 end
 // 5x7 glyphs, doubled in both dimensions.
 function [34:0] glyph;input [7:0] c;begin
  case(c)
   "0":glyph=35'b01110_10001_10011_10101_11001_10001_01110;
   "1":glyph=35'b00100_01100_00100_00100_00100_00100_01110;
   "2":glyph=35'b01110_10001_00001_00010_00100_01000_11111;
   "3":glyph=35'b11110_00001_00001_01110_00001_00001_11110;
   "4":glyph=35'b00010_00110_01010_10010_11111_00010_00010;
   "5":glyph=35'b11111_10000_10000_11110_00001_00001_11110;
   "6":glyph=35'b01110_10000_10000_11110_10001_10001_01110;
   "7":glyph=35'b11111_00001_00010_00100_01000_01000_01000;
   "8":glyph=35'b01110_10001_10001_01110_10001_10001_01110;
   "9":glyph=35'b01110_10001_10001_01111_00001_00001_01110;
   "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
   "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
   "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
   "I":glyph=35'b01110_00100_00100_00100_00100_00100_01110;
   "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
   "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
   "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
   "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
   "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
   default:glyph=0;
  endcase
 end endfunction
 wire [34:0] bits=glyph(ch);
 wire ink=dy<14 && dx[3:0]<10 && bits[34-(dy>>1)*5-(dx[3:0]>>1)];
 wire bar=x>=160 && x<416 && dy>=28 && dy<38;
 wire fill=bar && (x-160)<{2'd0,amount};
 wire marker=chosen && x>=148 && x<154 && dy<40;
 assign rgb_out=!panel?rgb_in:marker?24'hffff00:ink?24'hffffff:
                fill?(chosen?24'h40e0a0:24'h5090b0):bar?24'h404850:24'h182028;
endmodule
