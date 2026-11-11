`timescale 1ns/1ps
module tb_uart_events;
 reg clk=0,rn=0,boot=0,home=1,active=0,shown=0,ready=0;reg [1:0] theme=0;reg [4:0] index=0;
 always #10 clk=~clk;
 wire valid;wire [7:0] data;
 uart_system_events dut(clk,rn,boot,home,theme,shown,index,active,valid,data,ready);
 reg [127:0] linebuf=0;integer overflow_lines=0,lines=0;reg [7:0] held;
 always @(posedge clk)if(rn&&valid&&ready)begin
  if(data==10)begin
   if(linebuf=={"EV OVERFLOW",8'd13})overflow_lines=overflow_lines+1;
   lines=lines+1;linebuf=0;
  end else linebuf={linebuf[119:0],data};
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 integer i;
 initial begin
  cycles(4);rn=1;boot=1;shown=1;cycles(20);
  held=data;for(i=0;i<25;i=i+1)begin theme=i;index=i;active=~active;cycles(2);if(data!==held)$fatal(1,"stall data changed");end
  if(!dut.transmitting||dut.pending[3:1]!=3'b111||!dut.overflow)$fatal(1,"pending snapshot overflow not recorded");
  ready=1;cycles(1000);if(valid||overflow_lines!=1||lines!=5)$fatal(1,"overflow recovery lines=%0d",lines);
  rn=0;cycles(4);if(valid)$fatal(1,"reset queue");
  $display("PASS bounded event queue: stable stalled byte, multi-source burst, explicit overflow, drain/recovery/reset");$finish;
 end
endmodule
