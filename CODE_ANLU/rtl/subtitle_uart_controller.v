// ASCII line protocol, 12-byte text. Atomic updates at line termination.
// Reply buffer is immutable during transmission. Host waits for reply before
// sending again; busy input is discarded to EOL and produces ERR BUSY later.
module subtitle_uart_controller #(parameter integer LINE_TIMEOUT=50000000)(
 input wire clk,rst_n,input wire [7:0] rx_data,input wire rx_valid,rx_framing_error,
 output reg [95:0] text,output reg [3:0] length,output reg enable,
 output wire reply_valid,output wire [7:0] reply_data,input wire reply_ready,
 input wire[127:0]audio_diag,
 input wire system_home,
 output reg theme_command,output reg [1:0] command_theme,
 output reg demo_command,output reg command_demo
);
 localparam integer CW=(LINE_TIMEOUT<2)?1:$clog2(LINE_TIMEOUT);
 reg [159:0] line;reg [4:0] count;reg invalid,overflow,skip_lf;
 reg [CW-1:0] idle_count;
 reg [255:0] response;reg [4:0] reply_count,reply_index;
 reg busy_line,busy_pending;
 integer i;reg [95:0] parsed;
 wire active=reply_count!=0;
 wire eol=rx_data==13 || rx_data==10;
 wire sub_prefix=line[31:0]==32'h3d425553; // SUB=, byte zero in low bits.
 wire text_prefix=line[39:0]==40'h3d54584554; // TEXT=
 function[7:0]hexchar;input[3:0]v;begin hexchar=v<10?48+v:55+v;end endfunction
 assign reply_valid=active;
 assign reply_data=response[reply_index*8 +:8];
 task answer;
 input [255:0] value;input [4:0] size;
 begin response<=value;reply_count<=size;reply_index<=0;end
 endtask
 // Reply constants are byte zero at the low end, including CR LF.
 localparam [255:0] OK=32'h0a0d4b4f;
 localparam [255:0] BUSY=80'h0a0d5953554220525245;
 localparam [255:0] SYNTAX=96'h0a0d5841544e595320525245;
 localparam [255:0] LONG=80'h0a0d474e4f4c20525245;
 localparam [255:0] CHAR=80'h0a0d5241484320525245;
 localparam [255:0] FRAME=88'h0a0d454d41524620525245;
 localparam [255:0] TIMEOUT=104'h0a0d54554f454d495420525245;
 localparam [255:0] UNSUPPORTED=136'h0a0d444554524f505055534e5520525245;
 localparam [255:0] CONTEXT=104'h0a0d545845544e4f4320525245;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   text<=96'h00524559414c502041475046;length<=11;enable<=1;
   line<=0;count<=0;invalid<=0;overflow<=0;skip_lf<=0;idle_count<=0;
   response<=0;reply_count<=0;reply_index<=0;busy_line<=0;busy_pending<=0;
   theme_command<=0;command_theme<=0;demo_command<=0;command_demo<=0;
  end else begin
   theme_command<=0;demo_command<=0;
   if(active && reply_ready)begin
    if(reply_index+1==reply_count)begin reply_count<=0;reply_index<=0;end
    else reply_index<=reply_index+1'b1;
   end
   if(!active && busy_pending)begin answer(BUSY,10);busy_pending<=0;end
   if(rx_framing_error)begin
    line<=0;count<=0;overflow<=0;invalid<=0;idle_count<=0;
    // Reject the rest of a damaged line rather than executing its suffix.
    busy_line<=1;
    if(!active && !busy_pending)answer(FRAME,11);else busy_pending<=1;
   end else if(rx_valid)begin
    idle_count<=0;
    if(skip_lf && rx_data==10)skip_lf<=0;
    else begin
     skip_lf<=eol && rx_data==13;
     if(active || busy_pending || busy_line)begin
      count<=0;line<=0;invalid<=0;overflow<=0;
      busy_line<=!eol;
      if(eol)busy_pending<=1;
     end else if(eol)begin
      count<=0;line<=0;invalid<=0;overflow<=0;
      if(count!=0)begin
       if(overflow)answer(LONG,10);
       else if(invalid)answer(CHAR,10);
       else if(count==2 && line[7:0]=="T" && line[15:8]>="1" && line[15:8]<="4")begin
        if(system_home)begin
         theme_command<=1;command_theme<=line[15:8]-8'd49;answer(OK,4);
        end else answer(CONTEXT,13);
       end else if(count==2 && line[7:0]=="M" && (line[15:8]=="0" || line[15:8]=="1"))begin
        if(system_home && line[15:8]=="1")answer(CONTEXT,13);
        else begin demo_command<=1;command_demo<=line[15:8]=="1";answer(OK,4);end
       end else if(count==6 && line[47:0]==48'h3f4f49445541)begin // AUDIO?
        response<=0;response[31:0]<=32'h3d445541; // AUD=
        response[39:32]<=hexchar(audio_diag[7:4]);response[47:40]<=hexchar(audio_diag[3:0]);response[55:48]<=32;
        response[63:56]<=hexchar(audio_diag[15:12]);response[71:64]<=hexchar(audio_diag[11:8]);response[79:72]<=32;
        for(i=0;i<8;i=i+1)begin
         response[(10+i)*8+:8]<=hexchar(audio_diag[44-i*4+:4]);
         response[(19+i)*8+:8]<=hexchar(audio_diag[76-i*4+:4]);
        end
        response[151:144]<=32;response[223:216]<=32;response[231:224]<=audio_diag[112]?"1":"0";
        response[239:232]<=13;response[247:240]<=10;reply_count<=31;reply_index<=0;
       end else if(count==5 && line[39:0]==40'h3f52524541)begin // AERR?
        response<=0;response[31:0]<=32'h3d41424c;
        for(i=0;i<8;i=i+1)response[(4+i)*8+:8]<=hexchar(audio_diag[108-i*4+:4]);
        response[103:96]<=13;response[111:104]<=10;reply_count<=14;reply_index<=0;
       end else if(count==4 && line[31:0]==32'h3f425553)begin
        response<=0;response[47:0]<={8'h3a,enable?8'h31:8'h30,32'h3d425553};
        for(i=0;i<12;i=i+1)if(i<length)response[(i+6)*8 +:8]<=text[i*8 +:8];
        response[(length+6)*8 +:8]<=13;response[(length+7)*8 +:8]<=10;
        reply_count<=length+8;reply_index<=0;
       end else if(sub_prefix && count==6 && line[47:32]==16'h4e4f)begin enable<=1;answer(OK,4);end
       else if(sub_prefix && count==7 && line[55:32]==24'h46464f)begin enable<=0;answer(OK,4);end
       else if(sub_prefix && count==8 && line[63:32]==32'h45564153)answer(UNSUPPORTED,17);
       else if(sub_prefix || text_prefix)begin
        if(count>(text_prefix?17:16))answer(LONG,10);
        else begin
         parsed=0;
         for(i=0;i<12;i=i+1)if(i<count-(text_prefix?5:4))parsed[i*8 +:8]=line[(i+(text_prefix?5:4))*8 +:8];
         text<=parsed;length<=count-(text_prefix?5:4);answer(OK,4);
        end
       end else answer(SYNTAX,12);
      end
     end else begin
      if(count<20)begin line[count*8 +:8]<=rx_data;count<=count+1'b1;end
      else overflow<=1;
      if(rx_data<32 || rx_data>126)invalid<=1;
     end
    end
   end else if(count!=0 || busy_line)begin
    if(idle_count==LINE_TIMEOUT-1)begin
     idle_count<=0;count<=0;line<=0;invalid<=0;overflow<=0;busy_line<=0;
     if(!active && !busy_pending)answer(TIMEOUT,13);else busy_pending<=1;
    end else idle_count<=idle_count+1'b1;
   end else idle_count<=0;
  end
 end
endmodule
