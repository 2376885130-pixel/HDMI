// 0..256 gain keeps both endpoints exact. Explicitly sized products avoid
// channel truncation or inter-channel carry. No added pixel-clock latency.
module video_transition_rgb #(parameter REVEAL_ENABLE=0,LIVE_EFFECT=0)(
 input wire [23:0] rgb_in,input wire [8:0] gain,output wire [23:0] rgb_out,
 input wire [9:0] x,y,input wire [1:0] kind,input wire reveal_active,input wire manual_transition);
 wire [16:0] r=rgb_in[23:16]*gain;
 wire [16:0] g=rgb_in[15:8]*gain;
 wire [16:0] b=rgb_in[7:0]*gain;
 wire [17:0] width_product=gain*10'd640,height_product=gain*10'd480;
 wire [9:0] width=width_product[17:8],height=height_product[17:8];
 wire horizontal=x<width;
 wire vertical=y<height;
 wire center=x>=(10'd320-(width>>1)) && x<(10'd320+(width>>1)) &&
             y>=(10'd240-(height>>1)) && y<(10'd240+(height>>1));
 wire revealed=kind==1 ? horizontal : kind==2 ? vertical : center;
 // Radial dissolve: a circular front with a dithered wave band. Old image
 // dissolves outward during OUT; new image reveals outward during IN.
 // Uses the existing single-reader cache commit, without dual-frame bandwidth.
 wire [9:0] dx=x>320?x-10'd320:10'd320-x;
 wire [9:0] dy=y>224?y-10'd224:10'd224-y;
 wire [19:0] dx2=dx*dx,dy2=dy*dy;
 wire [20:0] distance2={1'b0,dx2}+{1'b0,dy2};
 wire [8:0] phase=reveal_active?gain:9'd256-gain;
 wire [17:0] radius_product=phase*10'd416;
 wire [9:0] radius=radius_product[17:8];
 wire [19:0] radius2=radius*radius;
 wire [7:0] grain={x[0],y[0],x[1],y[1],x[2],y[2],x[3],y[3]};
 wire reached=distance2+{grain,5'd0}<radius2;
 wire ripple_visible=gain==256 ? 1'b1 : gain==0 ? 1'b0 : reveal_active?reached:!reached;
 assign rgb_out=(REVEAL_ENABLE && kind==3 && (!LIVE_EFFECT||manual_transition)) ? (ripple_visible?rgb_in:24'h142b40) :
                (REVEAL_ENABLE && reveal_active && kind!=0) ?
                (revealed ? rgb_in : 24'd0) : {r[15:8],g[15:8],b[15:8]};
endmodule
