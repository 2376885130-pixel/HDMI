`timescale 1ns/1ps
module tb_three_seconds;
 reg clk=0,rn=0,k2=1,k3=1,k4=1,s1=1,timed=0,ready=0,demo=0,preview=0,menu=0,err=0,n=0,p=0,sel=0,done=0;
 reg [4:0] choice=0,aid=0;wire home;wire [1:0] theme;wire [4:0] idx;
 wire q2,q3,q4,pup,mup,aut,play,restart,manual;wire [7:0] progress;
 always #10 clk=~clk;
 theme_control #(.CLOCK_HZ(100),.DEBOUNCE(2)) dut(clk,rn,k2,k3,k4,s1,1'b1,1'b1,1'b0,demo,ready,preview,menu,err,n,p,sel,choice,done,aid,home,theme,idx,q2,q3,q4,pup,mup,aut,play,progress,restart,manual,timed,1'b0,2'd0);
 task cycles(input integer c);repeat(c)@(negedge clk);endtask
 task quiet(input integer c);reg [4:0] saved;begin saved=idx;cycles(c);if(idx!=saved)$fatal(1,"unexpected slideshow");end endtask
 integer m,i;reg [4:0] saved;
 initial begin
  cycles(4);rn=1;cycles(10);
  for(m=0;m<4;m=m+1)begin
   if(!home||theme!=m)$fatal(1,"theme");
   timed=1;quiet(600);k3=0;cycles(210);k3=1;cycles(10);
   if(home||idx!=m*8)$fatal(1,"entry");
   quiet(600);ready=1;cycles(299);if(idx!=m*8)$fatal(1,"early slide");
   cycles(1);if(idx!=m*8+1)$fatal(1,"missing 3-second slide");
   for(i=0;i<7;i=i+1)begin saved=idx;cycles(301);if(idx[2:0]!=(saved[2:0]+3'd1))$fatal(1,"wrap");end
   demo=1;quiet(600);demo=0;menu=1;quiet(600);menu=0;preview=1;quiet(600);preview=0;err=1;quiet(600);err=0;
   n=1;cycles(1);n=0;saved=idx;quiet(299);cycles(2);if(idx[2:0]!=(saved[2:0]+3'd1))$fatal(1,"manual timer restart");
   timed=0;s1=0;cycles(10);saved=idx;aid=idx;done=1;cycles(2);if(idx[2:0]!=(saved[2:0]+3'd1))$fatal(1,"normal EOF");
   saved=idx;quiet(10);done=0;cycles(3);
   timed=1;aid=idx;done=1;quiet(100);done=0;
   timed=0;s1=1;ready=0;k4=0;cycles(320);k4=1;cycles(10);if(!home)$fatal(1,"home exit");
   k2=0;cycles(10);k2=1;cycles(10);
  end
  $display("PASS 3 seconds from ready, 4 themes x 8 image wrap, no home/loading/demo/menu/preview/error advance, manual restart, EOF exclusion/restoration");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
