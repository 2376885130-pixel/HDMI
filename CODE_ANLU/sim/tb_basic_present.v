`timescale 1ns/1ps
module tb_basic_present;
 reg clk=0,sys=0,rst=1;always #5 clk=~clk;always #7 sys=~sys;
 reg sw=1;wire basic,mailbox;
 osd_state_snapshot #(.WIDTH(1)) tx(sys,!rst,sw,clk,!rst,mailbox);
 reg [9:0] x=1,y=1;integer phase=0,frames=0;
 reg token=0;reg [4:0] id=0;reg ack=0,primed=1,underflow=0,man=1;
 wire req,shown,presented,valid,commit,busy,reveal,manual;
 wire [1:0] read_slot,display_slot,kind;wire [4:0] display_id;wire [87:0] name;wire [8:0] gain;
 quad_frame_present #(.RUNTIME_MODE(1),.REQUEST_TOGGLE(1),.FADE_FRAMES(12),.TRANSITION_MODE(4),.THUMBNAILS(1),.LIVE_EFFECT(1)) dut(
 .clk(clk),.rst(rst),.x(x),.y(y),.load_ready(token),.load_slot(id[1:0]),.load_index(id),.load_name(88'd0),
 .read_ack(ack),.read_primed(primed),.read_underflow(underflow),.read_req(req),.read_slot(read_slot),
 .show_image(shown),.presented(presented),.frame_valid(valid),.display_slot(display_slot),.display_index(display_id),.display_name(name),.commit(commit),
 .transition_gain(gain),.transition_busy(busy),.transition_kind(kind),.reveal_active(reveal),
 .preview_request(1'b0),.requested_page(3'd0),.target_index(id),.page_toggle(1'b0),.page_bank(1'b0),.page_number(3'd0),.page_valid(4'd0),
 .requested_focus(2'd0),.page_zoom(1'b0),.manual_effect(man),.effect_index(id),.manual_transition(manual),.basic_request(mailbox),.mode_safe(1'b1),.basic_active(basic));
 always @(negedge clk)begin
  if(rst)begin phase=0;x=1;y=1;ack=0;end
  else begin
   phase=(phase+1)%100;x=1;y=1;
   if(phase==0)begin x=0;y=0;frames=frames+1;end
   if(phase==80)begin x=0;y=480;end
   ack=req;
  end
 end
 reg old_basic=0;integer commits=0;
 always @(posedge clk)begin
  #1;
  if(!rst)begin
   if(old_basic!=basic&&!(x==0&&y==480))$fatal(1,"mode not blanking-atomic");
   if(commit)begin
    commits=commits+1;
    if(x!=0||y!=0||!primed||!valid)$fatal(1,"unsafe frame commit");
   end
   if(basic&&(gain!=256||busy||reveal||manual))$fatal(1,"basic effect visible");
  end
  old_basic=basic;
 end
 task next_image;begin @(negedge sys);id=id+1;token=!token;end endtask
 task frames_wait(input integer n);integer f;begin f=frames;wait(frames>=f+n);#2;end endtask
 integer started;
 initial begin
  repeat(4)@(posedge clk);#2;rst=0;token=1;
  wait(shown);sw=0;wait(!basic);next_image;wait(busy);started=frames;
  // Request basic while advanced transition is already running.
  sw=1;frames_wait(5);if(basic)$fatal(1,"mid-effect mode switch");
  wait(display_id==1);if(kind!=3)$fatal(1,"advanced ripple lost");
  wait(!busy);if(frames-started!=24)$fatal(1,"12-frame out/in altered");
  wait(basic);primed=0;next_image;frames_wait(4);
  if(display_id!=1||presented==token)$fatal(1,"unprimed reader acknowledged");
  primed=1;wait(display_id==2);frames_wait(1);
  man=0;next_image;wait(display_id==3);frames_wait(1);
  if(busy||gain!=256)$fatal(1,"basic automatic effect");
  // Pending unprimed image must finish before switching the presentation policy.
  primed=0;next_image;frames_wait(1);sw=0;frames_wait(4);
  if(!basic)$fatal(1,"pending commit changed mode");
  primed=1;wait(display_id==4);wait(!basic);
  man=1;next_image;wait(busy);wait(display_id==5);wait(!busy);#2;
  if(gain!=256||!valid||commits!=6)$fatal(1,"recovery/commit count gain=%d valid=%b commits=%d",gain,valid,commits);
  rst=1;#30;sw=1;rst=0;wait(basic);
  if(shown||busy)$fatal(1,"reset retained old frame");
  $display("PASS asynchronous mode mailboxes, blanking mode commit, 12-frame advanced effect, no manual/automatic basic effects, primed/ack protection, pending/effect mode deferral, reset");$finish;
 end
 initial begin #300000;$fatal(1,"presentation timeout");end
endmodule
