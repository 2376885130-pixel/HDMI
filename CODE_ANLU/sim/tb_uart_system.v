`timescale 1ns/1ps
module tb_uart_system;
 reg clk=0,rn=0,rx=1,boot=0,presented=0;
 reg k2=1,k3=1,k4=1,s3=1,s4=1;
 always #10 clk=~clk;
 wire tx,home,active,blocked,tc,dc,de;wire [1:0] ct,theme;
 wire [4:0] idx;wire [63:0] state;wire [95:0] text;wire [3:0] length;wire en;
 wire a2,a3,a4,b3,b4;wire [7:0] outbyte;wire outvalid,outbad;
 subtitle_uart_service #(.CLKS_PER_BIT(8),.LINE_TIMEOUT(3000)) uart(
  .clk(clk),.rst_n(rn),.rx(rx),.tx(tx),.text(text),.length(length),.enable(en),.audio_diag(128'b0),
  .system_ready(boot),.system_home(home),.system_theme(theme),.image_presented(presented),.presented_index(idx),
  .demo_active(active),.theme_command(tc),.command_theme(ct),.demo_command(dc),.command_demo(de));
 uart_rx_byte #(.CLKS_PER_BIT(8)) monitor(clk,rn,tx,outbyte,outvalid,outbad);
 p_rover_control #(.FILTER(4),.SETTLE(12),.SECOND(10000)) rover(
  .clk(clk),.rst_n(rn),.home(home),.model_id(theme),.sw3_up(s3),.sw4_up(s4),.key2_n(k2),.key3_n(k3),.key4_n(k4),
  .active(active),.blocked(blocked),.main_key2_n(a2),.main_key3_n(a3),.main_key4_n(a4),.main_sw3_up(b3),.main_sw4_up(b4),
  .state(state),.uart_demo_valid(dc),.uart_demo_enable(de));
 theme_control #(.CLOCK_HZ(100),.DEBOUNCE(4)) themes(
  .clk(clk),.rst_n(rn),.key2_n(a2),.key3_n(a3),.key4_n(a4),.sw1_up(1'b1),.sw3_up(b3),.sw4_up(b4),
  .reverse_mode(1'b0),.demo_hold(blocked),.ready(presented),.preview_hold(1'b0),.menu_reserved(1'b0),.load_error(1'b0),
  .next_event(1'b0),.prev_event(1'b0),.select_valid(1'b0),.select_index(5'b0),.audio_done(1'b0),.audio_id(5'b0),
  .home(home),.theme(theme),.index(idx),.timed_mode(1'b0),.uart_theme_valid(tc),.uart_theme(ct));
 reg [319:0] linebuf=0;integer oks=0,contexts=0,errors=0,events=0,commands=0,demos=0,diagnostics=0;
 always @(posedge clk)if(rn)begin
  if(tc)commands=commands+1;if(dc)demos=demos+1;
  if(outbad)$fatal(1,"TX framing");
  if(outvalid)begin
   if(outbyte==10)begin
    $display("TX %0s",linebuf);
    if(linebuf=={"OK",8'd13})oks=oks+1;
    else if(linebuf=={"ERR CONTEXT",8'd13})contexts=contexts+1;
    else if(linebuf=={"ERR SYNTAX",8'd13}||linebuf=={"ERR TIMEOUT",8'd13}||linebuf=={"ERR LONG",8'd13}||linebuf=={"ERR FRAME",8'd13}||linebuf=={"ERR BUSY",8'd13}||linebuf=={"ERR CHAR",8'd13})errors=errors+1;
    else if(linebuf=={"EV BOOT",8'd13}||linebuf=={"EV OVERFLOW",8'd13}||linebuf=={"EV DEMO 1",8'd13}||linebuf=={"EV DEMO 0",8'd13}||
      linebuf=={"EV THEME 1 H",8'd13}||linebuf=={"EV THEME 2 H",8'd13}||linebuf=={"EV THEME 3 H",8'd13}||linebuf=={"EV THEME 4 H",8'd13}||
      linebuf=={"EV THEME 1 T",8'd13}||linebuf=={"EV THEME 2 T",8'd13}||linebuf=={"EV THEME 3 T",8'd13}||linebuf=={"EV THEME 4 T",8'd13}||
      linebuf=={"EV IMAGE 01",8'd13}||linebuf=={"EV IMAGE 09",8'd13}||linebuf=={"EV IMAGE 17",8'd13}||linebuf=={"EV IMAGE 25",8'd13})events=events+1;
    else if(linebuf=={"AUD=00 00 00000000 00000000 0",8'd13})diagnostics=diagnostics+1;
    else if(linebuf=={"SUB=1:FPGA PLAYER",8'd13}||linebuf=={"SUB=1:TEST",8'd13}||linebuf=={"LBA=00000000",8'd13})begin end
    else $fatal(1,"interleaved/invalid line %s",linebuf);
    linebuf=0;
   end else linebuf={linebuf[311:0],outbyte};
  end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task byte_in(input [7:0] b);integer j;begin
  rx=0;cycles(8);for(j=0;j<8;j=j+1)begin rx=b[j];cycles(8);end rx=1;cycles(8);
 end endtask
 task command(input [159:0] s,input integer n);integer j;begin
  for(j=n-1;j>=0;j=j-1)byte_in(s[j*8+:8]);byte_in(13);byte_in(10);cycles(3000);
 end endtask
 task tap(input integer n);begin
  if(n==2)k2=0;else if(n==3)k3=0;else k4=0;
  cycles(24);k2=1;k3=1;k4=1;cycles(24);
 end endtask
 integer m,saved,oldc,j;reg [63:0] savedstate;
 initial begin
  cycles(4);rn=1;cycles(20);boot=1;presented=1;
  // Full duplex: command arrives while the boot/event packet owns TX.
  command("T2",2);if(theme!=1||commands!=1)$fatal(1,"full duplex command");
  command("M1",2);if(active||contexts!=1)$fatal(1,"home protection");
  command("T0",2);command("+",1);command("T12",3);
  oldc=commands;byte_in("T");byte_in("3");cycles(3200);cycles(3000);
  if(commands!=oldc)$fatal(1,"partial timeout executed");
  saved=errors;byte_in(1);byte_in(13);byte_in(10);cycles(3000);
  if(errors!=saved+1)$fatal(1,"invalid character not rejected");
  saved=errors;for(j=0;j<22;j=j+1)byte_in("T");byte_in(13);byte_in(10);cycles(3000);
  if(errors!=saved+1||commands!=oldc)$fatal(1,"long line not rejected");
  // A damaged stop bit must not execute a valid-looking command suffix.
  saved=errors;rx=0;cycles(80);rx=1;cycles(20);byte_in(13);byte_in(10);cycles(3000);
  if(errors<saved+1||commands!=oldc)$fatal(1,"framing rejection");
  saved=commands;
  byte_in("T");byte_in("1");byte_in(13);byte_in(10);
  // Host violates stop-and-wait while OK is still being sent.
  byte_in("T");byte_in("4");byte_in(13);byte_in(10);cycles(3500);
  if(commands!=saved+1||theme!=0)$fatal(1,"busy line executed");
  command("SUB?",4);command("TEXT=TEST",9);command("SUB?",4);
  if(text[31:0]!=32'h54534554||length!=4)$fatal(1,"subtitle regression");
  command("AERR?",5);
  command("AUDIO?",6);if(diagnostics!=1)$fatal(1,"31-byte diagnostic response regression");
  for(m=0;m<4;m=m+1)begin
   command({8'h54,8'd49+m[7:0]},2);if(theme!=m||!home)$fatal(1,"theme selection");
   k3=0;cycles(220);k3=1;cycles(40);presented=1;
   if(home||idx!=m*8)$fatal(1,"physical theme entry");
   oldc=contexts;command("T1",2);if(contexts!=oldc+1||theme!=m)$fatal(1,"context mutation");
   command("M1",2);if(!active||!blocked)$fatal(1,"remote entry");
   savedstate=state;command("M1",2);if(!active||state[58:52]!=savedstate[58:52])$fatal(1,"idempotent entry");
   tap(3);if(state[58:52]!=35||idx!=m*8)$fatal(1,"shared key parameter routing");
   tap(4);if(state[60:59]!=1)$fatal(1,"parameter selection");
   command("M0",2);if(active||blocked)$fatal(1,"remote exit restore");
   command("M0",2);if(active)$fatal(1,"idempotent exit");
   s3=0;s4=0;cycles(40);if(!active)$fatal(1,"physical entry");
   command("M0",2);cycles(50);if(active||blocked)$fatal(1,"M0 combo inhibit");
   s3=1;cycles(40);s3=0;cycles(40);if(!active)$fatal(1,"physical rearm");
   // A held key on exit must never leak to the main OSD/menu.
   k4=0;cycles(30);command("M0",2);if(active||!blocked||!a4)$fatal(1,"held-key exit guard");
   k4=1;s3=1;s4=1;cycles(60);if(blocked)$fatal(1,"guard release");
   k4=0;cycles(320);k4=1;cycles(40);if(!home)$fatal(1,"return home");
  end
  command("T4",2);k3=0;cycles(220);k3=1;cycles(30);command("M1",2);
  rn=0;cycles(4);rn=1;cycles(40);if(active||!home||theme!=0)$fatal(1,"reset clears remote state");
  $display("PASS UART framing/CRLF/full-duplex TX arbitration/context/four themes/shared parameters/M0 inhibit/held-key/reset: OK=%0d events=%0d",oks,events);
  $finish;
 end
 initial begin #100000000;$fatal(1,"UART system timeout");end
endmodule
