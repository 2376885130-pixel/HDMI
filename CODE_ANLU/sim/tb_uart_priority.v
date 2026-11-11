`timescale 1ns/1ps
module tb_uart_priority;
 reg clk=0,rn=0,k3=1,tv=0;reg [1:0] target=3;
 always #10 clk=~clk;
 wire home,restart;wire [1:0] theme;wire [4:0] index;
 theme_control #(.CLOCK_HZ(100),.DEBOUNCE(4)) dut(
  .clk(clk),.rst_n(rn),.key2_n(1'b1),.key3_n(k3),.key4_n(1'b1),.sw1_up(1'b1),.sw3_up(1'b1),.sw4_up(1'b1),
  .reverse_mode(1'b0),.demo_hold(1'b0),.ready(1'b1),.preview_hold(1'b0),.menu_reserved(1'b0),.load_error(1'b0),
  .next_event(1'b0),.prev_event(1'b0),.select_valid(1'b0),.select_index(5'd0),.audio_done(1'b0),.audio_id(5'd0),
  .home(home),.theme(theme),.index(index),.restart_event(restart),.timed_mode(1'b0),.uart_theme_valid(tv),.uart_theme(target));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
  cycles(4);rn=1;cycles(10);k3=0;
  wait(dut.key3_count==199);@(negedge clk);tv=1;cycles(1);tv=0;
  if(!home||theme!=3||index!=0||restart)$fatal(1,"UART selection leaked simultaneous old-theme entry");
  k3=1;cycles(20);k3=0;cycles(220);k3=1;cycles(20);
  if(home||index!=24)$fatal(1,"selected theme physical entry");
  tv=1;target=1;cycles(1);tv=0;cycles(10);
  if(theme!=3||index!=24)$fatal(1,"in-theme bypass");
  rn=0;tv=1;cycles(3);if(!home||theme!=0)$fatal(1,"reset precedence");
  $display("PASS command/KEY3 terminal-count collision, no spurious media request, context protection and reset precedence");$finish;
 end
 initial begin #1000000;$fatal(1,"priority timeout");end
endmodule
