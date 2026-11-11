// Resource-bounded unsigned setup divider; one bit per cycle, no combinational /.
module scale_divider(input clk,rst,start,input [27:0] numerator,input [11:0] denominator,
 output reg busy,done,output reg [27:0] quotient);
 reg [27:0] dividend,q;reg [11:0] divisor;
 // Remainder is always below the divisor (maximum 4095); one extra
 // bit suffices for the shift before subtraction of each numerator bit.
 reg [12:0] remainder;
 reg [4:0] count;
 wire [12:0] shifted={remainder[11:0],dividend[27]};
 wire subtract=shifted>={1'b0,divisor};
 wire [27:0] next_q={q[26:0],subtract};
 always @(posedge clk or posedge rst)begin
  if(rst)begin busy<=0;done<=0;quotient<=0;dividend<=0;divisor<=1;q<=0;remainder<=0;count<=0;end
  else begin
   done<=0;
   if(start && !busy)begin busy<=1;dividend<=numerator;divisor<=denominator==0?12'd1:denominator;q<=0;remainder<=0;count<=0;end
   else if(busy)begin
    remainder<=subtract?shifted-{1'b0,divisor}:shifted;
    dividend<={dividend[26:0],1'b0};q<=next_q;
    if(count==27)begin busy<=0;done<=1;quotient<=next_q;end else count<=count+1'b1;
   end
  end
 end
endmodule
