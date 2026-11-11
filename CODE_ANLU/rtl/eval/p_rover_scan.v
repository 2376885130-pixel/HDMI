// Shared scanning console; no TF requests or frame buffer. Two pixel latency.
module p_rover_scan(input wire clk,rst_n,input wire [9:0] x,y,input wire de,
 input wire [63:0] state,output wire [23:0] rgb,input wire [1:0] model_id);
 wire rover=model_id==0,satellite=model_id==1,lander=model_id==2,telescope=model_id==3;
 wire [7:0] dx=state[25:18]-{2'd0,state[25:20]},dy=state[17:10]-{2'd0,state[17:12]};
 wire [4:0] secondary=state[9:5],power=state[44:40],load=state[39:35];
 wire [6:0] angle=state[58:52],eff=state[51:45],battery=state[34:28];
 wire [1:0] sel=state[60:59],mission=state[27:26];wire active=state[61];
 wire [7:0] pdx=lander?{1'b0,dy[7:1]}:telescope?dx+{1'b0,dx[7:1]}:dx;
 wire [7:0] pdy=lander?8'd56+{2'd0,dx[7:2]}:telescope?dy+{1'b0,dy[7:1]}:dy;
 wire panel,secondary_span;
 reg [6:0] sx,sy;
 always @*case(secondary)
  0:begin sx=56;sy=0;end 1:begin sx=56;sy=5;end 2:begin sx=55;sy=10;end
  3:begin sx=54;sy=14;end 4:begin sx=53;sy=19;end 5:begin sx=51;sy=24;end
  6:begin sx=48;sy=28;end 7:begin sx=46;sy=32;end 8:begin sx=43;sy=36;end
  9:begin sx=40;sy=40;end 10:begin sx=36;sy=43;end 11:begin sx=32;sy=46;end
  12:begin sx=28;sy=48;end 13:begin sx=24;sy=51;end 14:begin sx=19;sy=53;end
  15:begin sx=14;sy=54;end 16:begin sx=10;sy=55;end 17:begin sx=5;sy=56;end
  default:begin sx=0;sy=56;end
 endcase
 wire [9:0] tip_x=258+{2'd0,dx},tip_y=238-{2'd0,dy};
 p_console_spans spans(clk,rst_n,x,y,lander,satellite,pdx,pdy,
  satellite?{sy,1'b0}:{1'b0,sx},satellite?{sx,1'b0}:{1'b0,sy},
  telescope?tip_x:10'd198,telescope?tip_y:10'd250,panel,secondary_span);
 wire scene=x>=16&&x<410&&y>=66&&y<432;
 wire [9:0] ground_center=198+{2'd0,sy,1'b0},flame_end=316+{4'd0,secondary,1'b0}+{5'd0,secondary};
 wire [9:0] wx0=x>=133?x-133:133-x,wx1=x>=198?x-198:198-x,wx2=x>=263?x-263:263-x;
 wire [9:0] wy=y>=326?y-326:326-y;
 wire tyre=(wx0<=22&&wy<=22&&wx0+wy<=33)||(wx1<=22&&wy<=22&&wx1+wy<=33)||(wx2<=22&&wy<=22&&wx2+wy<=33);
 wire rim=(wx0<=15&&wy<=15&&wx0+wy<=22)||(wx1<=15&&wy<=15&&wx1+wy<=22)||(wx2<=15&&wy<=15&&wx2+wy<=22);
 wire hub=(wx0<=6&&wy<=6)||(wx1<=6&&wy<=6)||(wx2<=6&&wy<=6);
 wire [9:0] ax=x>=285?x-285:285-x,ay=y>=187?y-187:187-y;
 wire dish=ax<=16&&ay<=16&&ax+ay<=23;
 wire [9:0] earth_curve=(x<198?198-x:x-198)>>3;
 wire [7:0] second_value=rover?{3'd0,load}:({3'd0,secondary}<<2)+secondary;
 reg [6:0] geometry;
 always @*begin
  geometry=7'd0;
  if(de)begin
   if(y<54)geometry=7'd1;
   if((y==54||y==446)&&x>=12&&x<628)geometry=7'd2;
   if(scene)begin
    geometry=7'd3;
    if(x[4:0]==0||y[4:0]==0)geometry=7'd4;
    if((rover||lander)&&y>=364+{7'd0,x[6:4]})begin
     geometry=y<388?7'd5:7'd6;
     if(x[5:0]>18&&x[5:0]<30&&y[4:0]>12&&y[4:0]<16)geometry=7'd7;
    end
    if(satellite&&y>=372+earth_curve)begin geometry=y<380+earth_curve?7'd8:7'd9;
     if(x[5:3]==y[5:3])geometry=7'd10;end
    if(telescope&&x[5:0]==y[5:0]&&x[3:0]==4)geometry=7'd11;
    if(rover)begin
     if(x>=139&&x<=257&&y>=244&&y<=296)begin
      geometry=y<254?7'd12:y>=284?7'd13:7'd14;
      if((x==160||x==198||x==235)&&y>258&&y<281)geometry=7'd15;end
     if(x>=146&&x<=250&&y>=300&&y<=305)geometry=7'd16;
     if(((x>=130&&x<=136)||(x>=195&&x<=201)||(x>=260&&x<=266))&&y>=293&&y<326)geometry=7'd17;
     if(tyre)geometry=7'd18;
     if(tyre&&(y[2:0]==0||x[2:0]==0))geometry=7'd19;
     if(rim)geometry=7'd20;
     if(rim&&(x[3:0]==6||y==326))geometry=7'd21;
     if(hub)geometry=7'd22;
     if(x>=193&&x<=201&&y>=171&&y<=244)geometry=7'd23;
     if(x>=176&&x<=220&&y>=154&&y<=176)geometry=7'd24;
     if(y>=160&&y<=170&&((x>=181&&x<=190)||(x>=205&&x<=214)))geometry=7'd25;
     if(x>=282&&x<=286&&y>=184&&y<=244)geometry=7'd26;
     if(dish)geometry=ax+ay>19?7'd27:7'd28;
     if(dish&&(x==285||y==187))geometry=7'd29;
     if(panel)geometry=(x[3:0]==0||y[3:0]==0)?7'd30:7'd31;
    end
    if(satellite)begin
     if(x>=166&&x<=230&&y>=202&&y<=270)begin
      geometry=x<176||x>220?7'd32:7'd33;
      if(y[3:0]==0)geometry=7'd34;end
     if(x>=180&&x<=216&&y>=184&&y<=204)geometry=7'd35;
     if(panel)geometry=(x[3:0]==0||y[3:0]==0)?7'd30:7'd36;
     if(secondary_span&&x>=198)geometry=7'd37;
     if(x>=186&&x<=210&&y>=270&&y<=290)geometry=7'd38;
     if(x>=191&&x<=205&&y>=284&&y<=292)geometry=7'd39;
     if(y>=354&&y<=366&&x+32>=ground_center&&x<=ground_center+32)geometry=y==354||y==366?7'd40:7'd41;
    end
    if(lander)begin
     if(x>=146&&x<=250&&y>=211&&y<=282&&x+y>=365&&x+282>=y+125)begin
      geometry=(x[4:0]==0||y[4:0]==0)?7'd42:7'd43;if(y<225)geometry=7'd44;end
     if(x>=176&&x<=220&&y>=230&&y<=255)geometry=7'd45;
     if(x>=192&&x<=200&&y>=170&&y<=212)geometry=7'd46;
     if(x>=184&&x<=208&&y>=168&&y<=176)geometry=7'd47;
     if(panel)geometry=7'd48;
     if(y>=238+pdy-3&&y<=238+pdy+3&&((x+16>=138-pdx&&x<=138-pdx+16)||(x+16>=258+pdx&&x<=258+pdx+16)))geometry=7'd47;
     if(x>=178&&x<=218&&y>=282&&y<=310)geometry=y<302?7'd49:7'd50;
     if(secondary!=0&&y>=311&&y<flame_end&&x>=180&&x<=216)begin
      geometry=x>=190&&x<=206?7'd51:7'd52;
      if(y>flame_end-8&&(x<188||x>208))geometry=7'd3;end
    end
    if(telescope)begin
     if(x>=170&&x<=258&&y>=246&&y<=286)geometry=x[4:0]==0?7'd53:7'd54;
     if(x>=142&&x<=174&&y>=224&&y<=320)geometry=(x[3:0]==0||y[3:0]==0)?7'd55:7'd56;
     if(panel&&x>=248)begin
      if(x<=tip_x+8&&y+8>=tip_y)geometry=x[3:0]<2?7'd57:7'd58;
      else if(x[3]||y[3])geometry=7'd59;
     end
     if(x+5>=tip_x&&x<=tip_x+5&&y+9>=tip_y&&y<=tip_y+9)geometry=7'd60;
     if(secondary_span&&x>=tip_x)geometry=7'd61;
    end
    if(((x>=134&&x<=142)||(x>=254&&x<=262))&&y>=234&&y<=242&&!telescope)geometry=7'd62;
   end
   if((x==12||x==414)&&y>=62&&y<=436)geometry=7'd63;
   if((y==62||y==436)&&x>=12&&x<=414)geometry=7'd63;
   if(x>=428&&x<=628&&((y>=62&&y<=242)||(y>=256&&y<=436)))begin
    geometry=7'd64;
    if(x==428||x==628||y==62||y==242||y==256||y==436)geometry=7'd63;end
   if(x>=438&&x<618&&y>=96&&y<126&&sel==0)geometry=7'd65;
   if(x>=438&&x<618&&y>=164&&y<194&&sel==1)geometry=7'd65;
   if(x>=444&&x<612&&y>=132&&y<142)geometry=x<444+angle+{3'd0,angle[6:1]}?7'd66:7'd67;
   if(x>=444&&x<612&&y>=200&&y<210)geometry=x<444+second_value+{1'd0,second_value[7:1]}?7'd68:7'd67;
   if(x>=444&&x<612&&y>=310&&y<318)geometry=x<444+eff?7'd69:7'd67;
   if(x>=444&&x<612&&y>=354&&y<362)geometry=x<444+{2'd0,power,2'b0}?7'd70:7'd67;
   if(x>=444&&x<612&&y>=398&&y<408)geometry=x<444+battery?7'd71:7'd67;
   if(x>=612&&x<622&&y>=22&&y<32)geometry=active?7'd72:7'd73;
  end
 end
 function [23:0] geometry_color(input [6:0] index);
  case(index)
   7'd0:geometry_color=24'h071322;
   7'd1:geometry_color=24'h0c2034;
   7'd2:geometry_color=24'h277997;
   7'd3:geometry_color=24'h091b2c;
   7'd4:geometry_color=24'h102a40;
   7'd5:geometry_color=24'h45515a;
   7'd6:geometry_color=24'h303d49;
   7'd7:geometry_color=24'h202f3c;
   7'd8:geometry_color=24'h66cbe9;
   7'd9:geometry_color=24'h154c75;
   7'd10:geometry_color=24'h256a75;
   7'd11:geometry_color=24'h96bed0;
   7'd12:geometry_color=24'hf0dc9c;
   7'd13:geometry_color=24'h8d7045;
   7'd14:geometry_color=24'hba9f66;
   7'd15:geometry_color=24'h5e6772;
   7'd16:geometry_color=24'h8b9eac;
   7'd17:geometry_color=24'h9db2bd;
   7'd18:geometry_color=24'h111c28;
   7'd19:geometry_color=24'h3c4b59;
   7'd20:geometry_color=24'h8ba5b5;
   7'd21:geometry_color=24'h273d50;
   7'd22:geometry_color=24'hd5e4e9;
   7'd23:geometry_color=24'hd9e3e8;
   7'd24:geometry_color=24'hb4c8d5;
   7'd25:geometry_color=24'h14283d;
   7'd26:geometry_color=24'h99abb8;
   7'd27:geometry_color=24'he4edf2;
   7'd28:geometry_color=24'h647e91;
   7'd29:geometry_color=24'hb7ccd7;
   7'd30:geometry_color=24'h7dd8fc;
   7'd31:geometry_color=24'h175b9a;
   7'd32:geometry_color=24'hb89041;
   7'd33:geometry_color=24'hcdb56e;
   7'd34:geometry_color=24'hf1d687;
   7'd35:geometry_color=24'hc1d5df;
   7'd36:geometry_color=24'h155b99;
   7'd37:geometry_color=24'h48b2d0;
   7'd38:geometry_color=24'ha7c0cf;
   7'd39:geometry_color=24'h153d59;
   7'd40:geometry_color=24'hf4d751;
   7'd41:geometry_color=24'h297879;
   7'd42:geometry_color=24'he7cc7e;
   7'd43:geometry_color=24'hae8b45;
   7'd44:geometry_color=24'he2d5a9;
   7'd45:geometry_color=24'h586b7c;
   7'd46:geometry_color=24'hc9d8de;
   7'd47:geometry_color=24'hc6a457;
   7'd48:geometry_color=24'hc7d7df;
   7'd49:geometry_color=24'h6f8798;
   7'd50:geometry_color=24'hb9cad2;
   7'd51:geometry_color=24'hffe69a;
   7'd52:geometry_color=24'he87939;
   7'd53:geometry_color=24'he3d9a2;
   7'd54:geometry_color=24'hae9860;
   7'd55:geometry_color=24'h6db5e2;
   7'd56:geometry_color=24'h1d598d;
   7'd57:geometry_color=24'he0e8ed;
   7'd58:geometry_color=24'h8ba7bc;
   7'd59:geometry_color=24'hb879c4;
   7'd60:geometry_color=24'h172b3c;
   7'd61:geometry_color=24'he2bc58;
   7'd62:geometry_color=24'hf1c656;
   7'd63:geometry_color=24'h267b99;
   7'd64:geometry_color=24'h0d253b;
   7'd65:geometry_color=24'h23465b;
   7'd66:geometry_color=24'hf5cf43;
   7'd67:geometry_color=24'h183c5b;
   7'd68:geometry_color=24'h50c4e9;
   7'd69:geometry_color=24'hf0d150;
   7'd70:geometry_color=24'h56c6e7;
   7'd71:geometry_color=24'h62d393;
   7'd72:geometry_color=24'h69da8c;
   7'd73:geometry_color=24'h697f94;
   default:geometry_color=24'h071322;
  endcase
 endfunction
 function [34:0] glyph(input [7:0] c);
  case(c)
   "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
   "B":glyph=35'b11110_10001_10001_11110_10001_10001_11110;
   "C":glyph=35'b01111_10000_10000_10000_10000_10000_01111;
   "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
   "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
   "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
   "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
   "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
   "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
   "K":glyph=35'b10001_10010_10100_11000_10100_10010_10001;
   "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
   "M":glyph=35'b10001_11011_10101_10101_10001_10001_10001;
   "N":glyph=35'b10001_11001_10101_10011_10001_10001_10001;
   "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
   "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
   "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
   "S":glyph=35'b01111_10000_10000_01110_00001_00001_11110;
   "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
   "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
   "V":glyph=35'b10001_10001_10001_10001_10001_01010_00100;
   "W":glyph=35'b10001_10001_10001_10101_10101_10101_01010;
   "X":glyph=35'b10001_10001_01010_00100_01010_10001_10001;
   "Y":glyph=35'b10001_10001_01010_00100_00100_00100_00100;
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
   "+":glyph=35'b00000_00100_00100_11111_00100_00100_00000;
   "-":glyph=35'b00000_00000_00000_11111_00000_00000_00000;
   ":":glyph=35'b00000_00100_00100_00000_00100_00100_00000;
   "%":glyph=35'b11001_11010_00010_00100_01000_01011_10011;
   default:glyph=0;
  endcase
 endfunction
 function [23:0] decimal(input [7:0] n);
  reg [7:0] v;reg [3:0] h,t;integer j;
  begin v=n;h=0;t=0;for(j=0;j<2;j=j+1)if(v>=100)begin v=v-100;h=h+1'b1;end
   for(j=0;j<9;j=j+1)if(v>=10)begin v=v-10;t=t+1'b1;end
   decimal={h==0?8'd32:8'h30+h,h==0&&t==0?8'd32:8'h30+t,8'h30+v};end
 endfunction
 reg [23:0] a_digits,b_digits,e_digits,p_digits,bat_digits;
 reg [2:0] number_slot;reg number_busy;
 wire [7:0] number_value=number_slot==0?{1'b0,angle}:number_slot==1?second_value:number_slot==2?{1'b0,eff}:number_slot==3?{3'd0,power}:{1'b0,battery};
 reg [7:0] decimal_rem;reg [3:0] decimal_h,decimal_t;reg number_loaded;
 wire [23:0] number_digits={decimal_h==0?8'd32:8'h30+{4'd0,decimal_h},decimal_h==0&&decimal_t==0?8'd32:8'h30+{4'd0,decimal_t},8'h30+decimal_rem};
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin a_digits<="  0";b_digits<="  0";e_digits<="  0";p_digits<="  0";bat_digits<="  0";number_slot<=0;number_busy<=0;number_loaded<=0;decimal_rem<=0;decimal_h<=0;decimal_t<=0;end
  else if(x==1&&y==480)begin number_slot<=0;number_busy<=1;number_loaded<=0;end
  else if(number_busy)begin
   if(!number_loaded)begin decimal_rem<=number_value;decimal_h<=0;decimal_t<=0;number_loaded<=1;end
   else if(decimal_rem>=100)begin decimal_rem<=decimal_rem-8'd100;decimal_h<=decimal_h+1'b1;end
   else if(decimal_rem>=10)begin decimal_rem<=decimal_rem-8'd10;decimal_t<=decimal_t+1'b1;end
   else begin
    case(number_slot)0:a_digits<=number_digits;1:b_digits<=number_digits;2:e_digits<=number_digits;3:p_digits<=number_digits;4:bat_digits<=number_digits;endcase
    number_loaded<=0;if(number_slot==4)number_busy<=0;else number_slot<=number_slot+1'b1;
   end
  end
 reg [4:0] line_code;reg [9:0] lx,ly;reg text_on;reg [23:0] text_color;
 always @*begin
  line_code=31;lx=0;ly=0;text_on=0;text_color=24'hc4dbe9;
  if(y>=38&&y<52&&x>=32&&x<288)begin
   text_on=1;lx=x-32;ly=y-38;
   case(model_id)0:line_code=5'd0;1:line_code=5'd1;2:line_code=5'd2;3:line_code=5'd3;endcase
  end
  if(scene&&x>=28&&x<220&&y>=78&&y<92)begin
   text_on=1;lx=x-28;ly=y-78;text_color=24'h77b8d4;
   case(model_id)0:line_code=5'd4;1:line_code=5'd5;2:line_code=5'd6;3:line_code=5'd7;endcase
  end
  if(x>=444&&x<620)begin
   lx=x-444;
   if(y>=72&&y<86)begin text_on=1;ly=y-72;line_code=5'd8;end
   if(y>=102&&y<116)begin text_on=1;ly=y-102;text_color=sel==0?24'hffda60:24'hc4dbe9;
    case(model_id)0:line_code=5'd9;1:line_code=5'd10;2:line_code=5'd11;3:line_code=5'd12;endcase end
   if(y>=148&&y<162)begin text_on=1;ly=y-148;line_code=13;end
   if(y>=170&&y<184)begin text_on=1;ly=y-170;text_color=sel==1?24'hffda60:24'hc4dbe9;
    case(model_id)0:line_code=5'd14;1:line_code=5'd15;2:line_code=5'd16;3:line_code=5'd17;endcase end
   if(y>=216&&y<230)begin text_on=1;ly=y-216;line_code=18;end
   if(y>=266&&y<280)begin text_on=1;ly=y-266;line_code=5'd19;text_color=24'h70c9df;end
   if(y>=288&&y<302)begin text_on=1;ly=y-288;line_code=20;end
   if(y>=332&&y<346)begin text_on=1;ly=y-332;line_code=21;end
   if(y>=376&&y<390)begin text_on=1;ly=y-376;line_code=22;end
   if(y>=416&&y<430)begin text_on=1;ly=y-416;text_color=sel==2?24'hffda60:24'hc4dbe9;
    line_code=mission==0?23:mission==1?24:25;end
  end
  if(y>=452&&y<466&&x>=16&&x<576)begin text_on=1;lx=x-16;ly=y-452;
   line_code=x<320?26:27;if(x>=320)lx=x-320;end
  if(y>=466&&y<480&&x>=16&&x<272)begin text_on=1;lx=x-16;ly=y-466;line_code=active?28:29;end
 end
 wire [4:0] charpos=lx[7:3];
 (* rom_style="bram" *) reg [6:0] line_rom[0:1023];
 (* rom_style="bram" *) reg [4:0] ascii_rom[0:1023];
 initial begin $readmemh("theme_rom/console_lines.hex",line_rom);$readmemh("theme_rom/console_ascii.hex",ascii_rom);end
 reg [23:0] chosen_digits;reg override_digit;reg [6:0] special_char;
 always @*begin
  chosen_digits=line_code==13?a_digits:line_code==18?b_digits:line_code==20?e_digits:line_code==21?p_digits:bat_digits;
  override_digit=(line_code==13||line_code==18||line_code==20||line_code==21||line_code==22)&&charpos>=8&&charpos<=10;
  special_char=charpos==8?chosen_digits[22:16]:charpos==9?chosen_digits[14:8]:chosen_digits[6:0];
  if(line_code==18&&(rover||lander)&&charpos>=12&&charpos<=14)begin
   override_digit=1;special_char=charpos==12?(rover?7'd87:7'd37):7'd32;
  end
 end
 reg [6:0] character_q,special_q;reg override_q,text_q,text_qq;reg [2:0] row_q,col_q,col_qq;
 reg [4:0] ascii_row;reg [23:0] text_color_q,text_color_qq;
 always @(posedge clk)begin
  character_q<=line_rom[{line_code,charpos}];special_q<=special_char;override_q<=override_digit;
  row_q<=ly[3:1];col_q<=lx[2:0];text_q<=text_on&&lx<256&&lx[2:0]<5;text_color_q<=text_color;
  ascii_row<=ascii_rom[{override_q?special_q:character_q,row_q}];col_qq<=col_q;text_qq<=text_q;text_color_qq<=text_color_q;
 end
 wire ascii_pixel=text_qq&&ascii_row[4-col_qq];
 (* rom_style="bram" *) reg [15:0] title_font[0:511];
 initial $readmemh("theme_rom/console_titles.hex",title_font);
 reg [4:0] title_char;wire [3:0] title_pos=(x-32)>>4;
 always @*begin
  title_char=0;
  case(model_id)
   0:case(title_pos)0:title_char=1;1:title_char=2;2:title_char=3;3:title_char=4;4:title_char=5;endcase
   1:case(title_pos)0:title_char=6;1:title_char=2;2:title_char=7;3:title_char=4;4:title_char=8;5:title_char=9;endcase
   2:case(title_pos)0:title_char=1;1:title_char=2;2:title_char=10;3:title_char=11;4:title_char=5;endcase
   3:case(title_pos)0:title_char=12;1:title_char=13;2:title_char=14;3:title_char=15;4:title_char=16;endcase
  endcase
 end
 reg [15:0] title_row;reg [3:0] title_x;reg title_en,title_pixel,de_q,de_qq;reg [6:0] geometry_q,geometry_qq;
 always @(posedge clk)begin
  title_row<=title_font[{title_char,y[3:0]}];title_x<=x[3:0];
  title_en<=x>=32&&x<160&&y>=16&&y<32;
  title_pixel<=title_en&&title_row[15-title_x];
  geometry_q<=geometry;geometry_qq<=geometry_q;de_q<=de;de_qq<=de_q;
 end
 assign rgb=de_qq?(title_pixel?24'he9f4fa:ascii_pixel?text_color_qq:geometry_color(geometry_qq)):24'd0;
endmodule
