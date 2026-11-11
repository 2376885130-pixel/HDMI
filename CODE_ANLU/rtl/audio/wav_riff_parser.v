`timescale 1ns/1ps
// One session per reset. file_size is stable before bytes arrive. byte_last
// accompanies the actual final byte; premature EOF must also assert abort.
// Output is {end_marker, right16, left16}; end_marker follows all PCM frames.
module wav_riff_parser(
 input wire clk,rst_n,abort,input wire [31:0] file_size,
 input wire byte_valid,output wire byte_ready,input wire [7:0] byte_data,input wire byte_last,
 output reg token_valid,input wire token_ready,output reg [32:0] token,
 output reg [7:0] error,output reg finished
);
 localparam RIFF=0,CHUNK=1,FMT=2,SKIP=3,PAD=4,DATA=5,TRAIL=6,END=7,DONE=8;
 reg [3:0] state;reg[31:0] pos,riff_end,id,size,left,word;
 reg[4:0] idx;reg fmt_seen,data_seen;reg[15:0] format,channels,align,bits;
 reg[31:0] rate,byte_rate;reg[1:0] phase;reg[23:0] assembly;
 wire[31:0] assembled={byte_data,word[31:8]};
 assign byte_ready=state<END && (!token_valid || token_ready) && !abort;
 task fail;input[7:0] code;begin error<=code;state<=END;end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=RIFF;pos<=0;riff_end<=0;id<=0;size<=0;left<=0;word<=0;idx<=0;
   fmt_seen<=0;data_seen<=0;format<=0;channels<=0;align<=0;bits<=0;rate<=0;byte_rate<=0;
   phase<=0;assembly<=0;token_valid<=0;token<=0;error<=0;finished<=0;
  end else begin
   if(token_valid && token_ready)token_valid<=0;
   if(state==END && (!token_valid || token_ready))begin token<=33'h100000000;token_valid<=1;state<=DONE;end
   if(state==DONE && token_valid && token_ready)finished<=1;
   if(byte_valid && byte_ready)begin
    pos<=pos+1'b1;word<=assembled;
    case(state)
     RIFF:begin
      idx<=idx+1'b1;
      if(idx==3 && assembled!=32'h46464952)fail(1);
      if(idx==7)begin
       riff_end<=assembled+8;
       if(assembled<4 || assembled>32'hfffffff7 || assembled+8>file_size)fail(2);
      end
      if(idx==11)begin
       if(assembled!=32'h45564157)fail(1);
       else begin state<=CHUNK;idx<=0;end
      end
     end
     CHUNK:begin
      idx<=idx+1'b1;
      if(idx==3)id<=assembled;
      if(idx==7)begin
       size<=assembled;left<=assembled;idx<=0;
       if(pos+1>riff_end || assembled>riff_end-(pos+1) ||
          (assembled[0] && assembled==riff_end-(pos+1)))fail(2);
       else if(id==32'h20746d66)begin
        if(fmt_seen || data_seen || assembled<16)fail(3);else state<=FMT;
       end else if(id==32'h61746164)begin
        if(!fmt_seen || data_seen || assembled==0 ||
          (channels==1 && assembled[0]) || (channels==2 && |assembled[1:0]))fail(4);
        else begin data_seen<=1;state<=DATA;phase<=0;end
       end else if(assembled==0)begin
        if(pos+1==riff_end)fail(4);else state<=CHUNK;
       end else state<=SKIP;
      end
     end
     FMT:begin
      left<=left-1'b1;if(idx<16)idx<=idx+1'b1;
      case(idx)
       1:format<={byte_data,word[31:24]};
       3:channels<={byte_data,word[31:24]};
       7:rate<=assembled;
       11:byte_rate<=assembled;
       13:align<={byte_data,word[31:24]};
       15:begin
        bits<={byte_data,word[31:24]};fmt_seen<=1;
        if(format!=1 || (channels!=1 && channels!=2) || rate!=48000 ||
           {byte_data,word[31:24]}!=16 || align!=(channels<<1) ||
           byte_rate!=(channels==1?96000:192000))fail(3);
       end
      endcase
      if(left==1)begin state<=size[0]?PAD:CHUNK;idx<=0;
       if(idx==15 && (format!=1 || (channels!=1 && channels!=2) || rate!=48000 ||
          {byte_data,word[31:24]}!=16 || align!=(channels<<1) || byte_rate!=(channels==1?96000:192000)))fail(3);
      end
     end
     SKIP:begin left<=left-1'b1;if(left==1)begin state<=size[0]?PAD:CHUNK;idx<=0;end end
     PAD:begin state<=CHUNK;idx<=0;end
     DATA:begin
      left<=left-1'b1;assembly<={byte_data,assembly[23:8]};phase<=phase+1'b1;
      if(channels==1 && phase[0])begin
       token<={1'b0,byte_data,assembly[23:16],byte_data,assembly[23:16]};token_valid<=1;
      end else if(channels==2 && phase==3)begin
       token<={1'b0,byte_data,assembly};token_valid<=1;
      end
      if(left==1)state<=TRAIL;
     end
     TRAIL:begin end // Ignore legal metadata after the first data chunk.
    endcase
    if(pos>=file_size || (byte_last && pos!=file_size-1))fail(5);
    else if(pos==file_size-1)begin
     if(!byte_last || !(state==TRAIL || (state==DATA && left==1)))fail(5);
     else state<=END;
    end else if(state!=RIFF && state!=DATA && state!=TRAIL && pos+1>=riff_end)fail(4);
   end
   if(abort && state<END)fail(5);
  end
 end
endmodule
