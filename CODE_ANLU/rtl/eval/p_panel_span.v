// Compute one scanline's panel span in horizontal blanking. No DSP or RAM.
// At x=656 the timing generator has advanced y to the NEW scanline; 144
// pixel clocks remain before x=0. Two 8-cycle products and 16-cycle divides
// finish within 53 clocks. Active video only compares four registered bounds.
module p_panel_span #(parameter VARIABLE_HINGE=0,LEFT_HINGE=260,RIGHT_HINGE=380,HINGE_Y=230,HALF_THICKNESS=6,HALF_WIDTH=4)(input wire clk,rst_n,input wire [9:0] x,y,
 input wire [7:0] dx,dy,output wire panel,input wire [9:0] hinge_x,hinge_y);
 reg [2:0] phase;
 reg [4:0] count;
 reg second,ready,row_valid;
 reg [9:0] row;
 reg [7:0] denominator,upper_r,multiplier;
 reg [15:0] multiplicand,product,quotient;
 reg [8:0] remainder;
 reg [7:0] lower_x,upper_x;
 wire [9:0] trial={remainder,quotient[15]};
 wire subtract=trial>={2'd0,denominator};
 wire [9:0] rem_next=subtract?trial-{2'd0,denominator}:trial;
 wire [15:0] quotient_next={quotient[14:0],subtract};
 wire [9:0] bottom=VARIABLE_HINGE?hinge_y+HALF_THICKNESS:HINGE_Y+HALF_THICKNESS;
 wire [9:0] top=VARIABLE_HINGE?hinge_y-HALF_THICKNESS:HINGE_Y-HALF_THICKNESS;
 wire [9:0] rlow=y>=top?10'd0:top-y;
 wire [9:0] rhigh=y>=bottom?10'd0:bottom-y;
 wire [9:0] left_min=LEFT_HINGE-HALF_WIDTH-{2'd0,upper_x};
 wire [9:0] left_max=LEFT_HINGE+HALF_WIDTH-{2'd0,lower_x};
 wire [9:0] right_min=(VARIABLE_HINGE?hinge_x-HALF_WIDTH:RIGHT_HINGE-HALF_WIDTH)+{2'd0,lower_x};
 wire [9:0] right_max=(VARIABLE_HINGE?hinge_x+HALF_WIDTH:RIGHT_HINGE+HALF_WIDTH)+{2'd0,upper_x};
 assign panel=ready&&row_valid&&y==row&&
   ((!VARIABLE_HINGE&&x>=left_min&&x<=left_max)||(x>=right_min&&x<=right_max));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   phase<=0;count<=0;second<=0;ready<=0;row_valid<=0;row<=0;
   denominator<=0;upper_r<=0;multiplier<=0;multiplicand<=0;
   product<=0;quotient<=0;remainder<=0;lower_x<=0;upper_x<=0;
  end else if(x==656)begin
   row<=y;ready<=0;second<=0;count<=0;product<=0;
   row_valid<=y<=bottom&&({2'd0,dy}+y>=top)&&(dx!=0||dy!=0);
   denominator<=dy;
   multiplier<=rlow>{2'd0,dy}?dy:rlow[7:0];
   upper_r<=rhigh>{2'd0,dy}?dy:rhigh[7:0];
   multiplicand<={8'd0,dx};
   if(dy==0)begin lower_x<=0;upper_x<=dx;ready<=1;phase<=0;end
   else phase<=1;
  end else case(phase)
   1:begin
    if(multiplier[0])product<=product+multiplicand;
    multiplicand<={multiplicand[14:0],1'b0};multiplier<={1'b0,multiplier[7:1]};
    if(count==7)begin count<=0;phase<=2;end else count<=count+1'b1;
   end
   2:begin quotient<=product;remainder<=0;phase<=3;count<=0;end
   3:begin
    remainder<=rem_next[8:0];quotient<=quotient_next;
    if(count==15)begin
     if(second)begin upper_x<=quotient_next[7:0];ready<=1;phase<=0;end
     else begin
      lower_x<=quotient_next[7:0];second<=1;product<=0;count<=0;
      multiplier<=upper_r;multiplicand<={8'd0,dx};phase<=1;
     end
    end else count<=count+1'b1;
   end
   default:phase<=0;
  endcase
 end
endmodule

// Two spans share one serial product/divider during horizontal blanking.
// Launches at x=656 and x=712; each completes in at most 50 cycles.
// The active raster starts at x=0 after x=799. State/hinges are held per frame.
module p_console_spans(input wire clk,rst_n,input wire [9:0] x,y,
 input wire lander,satellite,input wire [7:0] pdx,pdy,sdx,sdy,
 input wire [9:0] hinge_x,hinge_y,output wire panel,secondary_panel);
 reg slot,second;reg [1:0] phase;reg [4:0] count;
 reg [7:0] denominator,upper_r,multiplier,saved_dx;
 reg [15:0] multiplicand,product,quotient;reg [8:0] remainder;
 reg [7:0] lo0,hi0,lo1,hi1;reg valid0,valid1;
 wire start0=x==10'd656,start1=x==10'd712;
 wire [9:0] row_in=start1?(satellite?10'd500-y:y):(lander?10'd476-y:y);
 wire [9:0] bottom=start1?hinge_y+10'd3:10'd250;
 wire [9:0] top=start1?hinge_y-10'd3:10'd226;
 wire [7:0] dx_in=start1?sdx:pdx,dy_in=start1?sdy:pdy;
 wire [9:0] rlow=row_in>=top?10'd0:top-row_in;
 wire [9:0] rhigh=row_in>=bottom?10'd0:bottom-row_in;
 wire valid_in=row_in<=bottom&&({2'd0,dy_in}+row_in>=top)&&(dx_in!=0||dy_in!=0);
 wire [9:0] trial={remainder,quotient[15]};
 wire subtract=trial>={2'd0,denominator};
 wire [9:0] rem_next=subtract?trial-{2'd0,denominator}:trial;
 wire [15:0] quotient_next={quotient[14:0],subtract};
 wire [9:0] left_min=10'd128-{2'd0,hi0},left_max=10'd148-{2'd0,lo0};
 wire [9:0] right_min=10'd248+{2'd0,lo0},right_max=10'd268+{2'd0,hi0};
 wire [9:0] secondary_min=hinge_x-10'd4+{2'd0,lo1},secondary_max=hinge_x+10'd4+{2'd0,hi1};
 assign panel=valid0&&((x>=left_min&&x<=left_max)||(x>=right_min&&x<=right_max));
 assign secondary_panel=valid1&&x>=secondary_min&&x<=secondary_max;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   slot<=0;second<=0;phase<=0;count<=0;denominator<=0;upper_r<=0;multiplier<=0;saved_dx<=0;
   multiplicand<=0;product<=0;quotient<=0;remainder<=0;lo0<=0;hi0<=0;lo1<=0;hi1<=0;valid0<=0;valid1<=0;
  end else if(start0||start1)begin
   slot<=start1;second<=0;count<=0;product<=0;saved_dx<=dx_in;
   if(start1)valid1<=valid_in;else valid0<=valid_in;
   denominator<=dy_in;multiplier<=rlow>{2'd0,dy_in}?dy_in:rlow[7:0];
   upper_r<=rhigh>{2'd0,dy_in}?dy_in:rhigh[7:0];multiplicand<={8'd0,dx_in};
   if(dy_in==0)begin
    if(start1)begin lo1<=0;hi1<=dx_in;end else begin lo0<=0;hi0<=dx_in;end
    phase<=0;
   end else phase<=1;
  end else case(phase)
   1:begin
    if(multiplier[0])product<=product+multiplicand;
    multiplicand<={multiplicand[14:0],1'b0};multiplier<={1'b0,multiplier[7:1]};
    if(count==7)begin count<=0;phase<=2;end else count<=count+1'b1;
   end
   2:begin quotient<=product;remainder<=0;phase<=3;count<=0;end
   3:begin
    remainder<=rem_next[8:0];quotient<=quotient_next;
    if(count==15)begin
     if(second)begin
      if(slot)hi1<=quotient_next[7:0];else hi0<=quotient_next[7:0];phase<=0;
     end else begin
      if(slot)lo1<=quotient_next[7:0];else lo0<=quotient_next[7:0];
      second<=1;product<=0;count<=0;multiplier<=upper_r;multiplicand<={8'd0,saved_dx};phase<=1;
     end
    end else count<=count+1'b1;
   end
   default:phase<=0;
  endcase
 end
endmodule
