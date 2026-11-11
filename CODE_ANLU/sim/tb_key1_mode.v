`timescale 1ns/1ps
module tb_key1_mode;
 reg clk=0,key=1;always #10 clk=~clk;
 wire rn,basic,event_short,pll_rn;
 key1_mode_control #(.POR_CYCLES(8),.FILTER(4),.LONG_CYCLES(30)) dut(clk,key,rn,basic,event_short,pll_rn);
 integer events=0,i;reg guard=0;
 always @(posedge clk)begin
  if(event_short)events=events+1;
  if(guard&&(!rn||!pll_rn))$fatal(1,"short press reset media/PLL");
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task shortpress;begin key=0;cycles(12);key=1;cycles(12);end endtask
 initial begin
  cycles(3);if(rn||!pll_rn)$fatal(1,"POR must hold logic but allow PLL startup");cycles(12);
  if(!rn||!basic)$fatal(1,"POR defaults");guard=1;
  key=0;cycles(1);key=1;cycles(8);if(events)$fatal(1,"bounce event");
  shortpress;if(events!=1||basic)$fatal(1,"short toggle");
  for(i=0;i<20;i=i+1)shortpress;
  if(events!=21||basic)$fatal(1,"rapid repeat");
  guard=0;key=0;cycles(45);if(rn||pll_rn||!basic)$fatal(1,"long press must reset logic AND PLL");
  cycles(80);if(rn)$fatal(1,"reset not held");key=1;cycles(12);
  if(!rn||events!=21||!basic)$fatal(1,"long release became short");
  guard=1;shortpress;if(events!=22||basic)$fatal(1,"rearm");
  $display("PASS KEY1 POR, debounce, 22 short presses without reset, held long reset, no release leakage");$finish;
 end
endmodule
