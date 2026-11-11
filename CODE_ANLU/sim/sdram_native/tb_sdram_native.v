`timescale 1ns/1ps
module tb_sdram_native;
 reg mc=0,pc=0,sc=0,rst=1;
 always #10 mc=~mc;
 always #20 pc=~pc;
 initial begin #8;forever #10 sc=~sc;end
 wire init,refresh,busy,rv,we,re;
 wire [31:0] rd,wd;wire [20:0] wa,ra;wire [3:0] dm;
 reg wen=1,wreq=0,rreq=0,pv=0,ren=0;reg[31:0]pd=0;
 wire wack,finish,rack,primed,under,fault,wrst;wire [31:0]q;
 quad_frame_store f(
 .mem_clk(mc),.rst(rst),.load_enable(wen),.memory_initialized(init),.memory_busy(busy),.memory_refresh(refresh),
 .app_rd_en(re),.app_rd_addr(ra),.rd_valid(rv),.rd_data(rd),.app_wr_en(we),.app_wr_addr(wa),.app_wr_data(wd),.app_wr_mask(dm),
 .write_clk(mc),.write_req(wreq),.write_slot(2'd0),.write_ack(wack),.write_finish(finish),.pixel_valid(pv),.pixel_data(pd),
 .read_clk(pc),.read_req(rreq),.read_slot(2'd0),.read_ack(rack),.read_en(ren),.read_data(q),.read_primed(primed),.read_underflow(under),.memory_fault(fault),.writer_reset(wrst),
 .read_preview(1'b0),.read_bank(1'b0),.dma_req(1'b0),.dma_write(1'b0),.dma_addr(21'd0),.dma_wdata(32'd0));
 sdram m(.Clk(mc),.Clk_sft(sc),.Rst(rst),.Sdr_init_done(init),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),
 .App_wr_en(we),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(re),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd));
 integer i,j,expected,checks=0;
 initial begin
  #100;rst=0;wait(init);@(negedge mc);wreq=1;wait(wack);@(negedge mc);wreq=0;
  wait(!wrst);repeat(20)@(negedge mc);
  for(i=0;i<307200;i=i+1)begin
   while(f.write_used>380)@(negedge mc);
   pv=1;pd=32'h4a000001|(i<<8);@(negedge mc);pv=0;repeat(2)@(negedge mc);
  end
  wait(finish);$display("Native controller frame write complete t=%0t",$time);
  for(j=0;j<2;j=j+1)begin
   @(negedge pc);rreq=1;wait(rack);@(negedge pc);rreq=0;wait(!rack);wait(primed);repeat(20)@(negedge pc);
   for(i=0;i<307200;i=i+1)begin
    ren=1;@(posedge pc);#1;
    expected=(479-i/640)*640+i%640;
    if(q!==(32'h4a000001|(expected<<8)))$fatal(1,"native SDRAM mismatch frame=%0d word=%0d got=%h expected=%h",j,i,q,32'h4a000001|(expected<<8));
    if(under||fault)$fatal(1,"native frame fault");
    checks=checks+1;@(negedge pc);
   end
   ren=0;repeat(100)@(negedge pc);
  end
  $display("PASS native SDRAM controller/device and production FIFO %0d words",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"native SDRAM timeout state=%0d init=%b",f.state,init);end
endmodule
