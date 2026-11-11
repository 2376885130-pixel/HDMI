module subtitle_uart_service #(parameter integer CLKS_PER_BIT=434,LINE_TIMEOUT=50000000)(
 input wire clk,rst_n,rx,output wire tx,
 output wire [95:0] text,output wire [3:0] length,output wire enable,
 input wire[127:0]audio_diag,
 input wire system_ready,system_home,input wire [1:0] system_theme,
 input wire image_presented,input wire [4:0] presented_index,input wire demo_active,
 output wire theme_command,output wire [1:0] command_theme,
 output wire demo_command,output wire command_demo
);
 wire [7:0] rx_data,reply_data;wire rx_valid,framing_error,reply_valid,tx_busy;
 uart_rx_byte #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver(clk,rst_n,rx,rx_data,rx_valid,framing_error);
 wire event_valid,event_ready;wire [7:0] event_data;
 reg [1:0] owner;
 wire choose_reply=owner==1 || (owner==0&&reply_valid);
 wire choose_event=owner==2 || (owner==0&&!reply_valid&&event_valid);
 wire send_reply=choose_reply&&reply_valid&&!tx_busy;
 wire send_event=choose_event&&event_valid&&!tx_busy;
 wire [7:0] tx_data=choose_reply?reply_data:event_data;
 // Lock one source through its LF, never interleave event and response bytes.
 always @(posedge clk or negedge rst_n)
  if(!rst_n)owner<=0;
  else if(send_reply||send_event)begin
   if(tx_data==10)owner<=0;
   else owner<=send_reply?1:2;
  end
 assign event_ready=send_event;
 subtitle_uart_controller #(.LINE_TIMEOUT(LINE_TIMEOUT)) control(
  .clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_valid(rx_valid),.rx_framing_error(framing_error),
  .text(text),.length(length),.enable(enable),.reply_valid(reply_valid),.reply_data(reply_data),.reply_ready(send_reply),
  .audio_diag(audio_diag),.system_home(system_home),.theme_command(theme_command),.command_theme(command_theme),
  .demo_command(demo_command),.command_demo(command_demo));
 uart_system_events events(.clk(clk),.rst_n(rst_n),.system_ready(system_ready),.home(system_home),.theme(system_theme),
  .image_presented(image_presented),.presented_index(presented_index),.demo_active(demo_active),
  .valid(event_valid),.data(event_data),.ready(event_ready));
 uart_tx_byte #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter(
  .clk(clk),.rst_n(rst_n),.start(send_reply||send_event),.data(tx_data),.tx(tx),.busy(tx_busy),.done());
endmodule
