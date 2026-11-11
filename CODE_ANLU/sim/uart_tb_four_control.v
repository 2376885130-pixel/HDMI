`timescale 1ns/1ps
module tb_four_control;
 reg clk=0,rn=0,home=1,s3=1,s4=1,k2=1,k3=1,k4=1;reg [1:0] model=0;
 always #10 clk=~clk;
 wire active,blocked,m2,m3,m4,a3,a4;wire [63:0] state;
 p_rover_control #(.FILTER(4),.SETTLE(20),.SECOND(1000)) dut(clk,rn,home,s3,s4,k2,k3,k4,active,blocked,m2,m3,m4,a3,a4,state,model,1'b0,1'b0);
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task tap(input integer n);begin
  if(n==2)k2=0;else if(n==3)k3=0;else k4=0;
  cycles(20);k2=1;k3=1;k4=1;cycles(20);
 end endtask
 integer m,i;
 reg [1:0] observed_model=0;
 always @(negedge clk)if(rn)begin
  if(state[63:62]!=observed_model)begin
   if(state[58:52]!=30||state[9:5]!=0||state[60:59]!=0)$fatal(1,"new model tag has stale parameters");
  end
  observed_model=state[63:62];
 end else observed_model=0;
 initial begin
  cycles(4);rn=1;cycles(20);
  for(m=0;m<4;m=m+1)begin
   home=1;model=m;s3=0;s4=0;cycles(40);
   if(active||state[63:62]!=m||state[60:59]!=0)$fatal(1,"home/model");
   home=0;cycles(40);if(!active||!blocked||!a3||!a4)$fatal(1,"entry");
   tap(3);if(state[58:52]!=35)$fatal(1,"primary");
   tap(2);if(state[58:52]!=30)$fatal(1,"primary decrement");
   tap(4);if(state[60:59]!=1)$fatal(1,"select secondary");
   tap(3);
   if(m==0)begin if(state[39:35]!=18)$fatal(1,"rover load");end
   else begin
    if(state[9:5]!=1)$fatal(1,"secondary increment");
    for(i=0;i<22;i=i+1)tap(3);
    if(state[9:5]!=18)$fatal(1,"secondary upper clamp");
    for(i=0;i<22;i=i+1)tap(2);
    if(state[9:5]!=0)$fatal(1,"secondary lower clamp");
   end
   tap(4);if(state[60:59]!=(m==0?2:0))$fatal(1,"selection count");
   k4=0;cycles(200);s3=1;cycles(40);
   if(active||!blocked||!m4)$fatal(1,"held exit");
   k4=1;s4=1;cycles(60);if(blocked||!a3||!a4)$fatal(1,"restore");
  end
  rn=0;cycles(4);rn=1;home=1;cycles(40);
  if(active||state[58:52]!=30||state[9:5]!=0)$fatal(1,"reset");
  $display("PASS four devices: theme mapping, home guard, parameters, clamp, key isolation, held exit, reset");$finish;
 end
 initial begin #10000000;$fatal(1,"timeout");end
endmodule
