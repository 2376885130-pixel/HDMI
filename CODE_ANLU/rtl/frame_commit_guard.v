// SDRAM completion crosses into the loader clock domain as a toggle.
// Clear any old completion at the accepted write request. Receiving all pixels
// only enables wait_commit; image_ready still requires the real SDRAM finish.
// The video-domain frame-boundary presentation remains in the existing top.
module frame_commit_guard (
    input wire clk,rst,write_accepted,wait_commit,write_finish_toggle,
    output reg memory_done,output wire commit_ready,output reg image_ready
);
    reg [2:0] finish_sync;
    assign commit_ready=wait_commit && memory_done;
    always @(posedge clk or posedge rst)begin
        if(rst)begin finish_sync<=0;memory_done<=0;image_ready<=0;end
        else begin
            finish_sync<={finish_sync[1:0],write_finish_toggle};
            if(finish_sync[2]^finish_sync[1])memory_done<=1;
            // Acceptance wins over a stale toggle arriving on the same edge.
            if(write_accepted)memory_done<=0;
            if(commit_ready)image_ready<=1;
        end
    end
endmodule
