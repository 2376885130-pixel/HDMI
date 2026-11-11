// Read-only FAT32 root-directory BMP loader. Supports fragmented cluster chains.
// Supported images: 1..2048 per axis, positive height, RGB24 BI_RGB.
// Complete sectors are buffered before replay into the backpressured scaler.
// Sector interface is independent of the board-specific SD SPI transport.
module fat32_bmp_loader #(
    parameter integer REUSE_CATALOG = 0,
    parameter integer WATCHDOG_BITS = 28,
    parameter integer SELECT_BY_NAME = 0,
    parameter integer AUTO_SCAN = 0
)(
    input wire clk, input wire rst,
    input wire sd_ready, input wire memory_ready,
    output reg sector_req, output reg [31:0] sector_lba,
    input wire [7:0] sector_byte, input wire sector_valid, input wire sector_end,
    output reg write_req, input wire write_ack,
    output wire pixel_valid, output wire [31:0] pixel_data,
    input wire write_finish_toggle,
    output wire image_ready, output reg [3:0] status,
    input wire [4:0] image_index,
    output wire [5:0] image_total, output wire catalog_valid,
    output wire [87:0] image_name, // FAT short name
    output reg [3:0] diagnostic_stage, // Holds the stage that failed until loader reset.
    input wire sector_busy, input wire [7:0] sector_error,
    input wire load_start,load_cancel,
    output wire[31:0] audio_root_cluster,audio_fat_lba,audio_data_lba,audio_max_cluster,
    output wire[3:0] audio_cluster_shift,output wire[7:0] audio_sectors_per_cluster,
    output wire [9:0] load_progress_rows
);
    localparam WAIT_READY=0, REQUEST=1, RECEIVE=2, DECIDE=3,
               BEGIN_WRITE=4, WAIT_COMMIT=5, DONE=6, ERROR=7, SCAN_FINISH=8,
               VOLUME_LAYOUT=9, VOLUME_COUNT=10, VOLUME_CHECK=11, REUSE_WAIT=12, CANCELED=13,
               REPLAY_PREFETCH=14,REPLAY_BYTE=15,REPLAY_DRAIN=16,SELECT_PREFETCH=17;
    localparam MBR=0, BPB=1, DIRECTORY=2, FILE_DATA=3, FAT_ENTRY=4, SCAN_HEADER=5;
    reg [4:0] state;
    reg [2:0] kind;
    reg fat_for_file;
    reg [8:0] byte_index;
    reg [9:0] sector_bytes;
    reg [4:0] previous_state;
    reg [7:0] file_sector[0:511];
    reg [7:0] replay_byte;
    reg [8:0] replay_index;
    reg [31:0] replay_base;
    reg decoded_sector;
    // kind changes in DECIDE, before REQUEST/RECEIVE or replay begins.
    // Register its decode to keep the byte-position mux off the FSM path.
    reg decoder_file_mode;
    always @(posedge clk or posedge rst)
        if(rst)decoder_file_mode<=0;else decoder_file_mode<=kind==FILE_DATA;
    wire decoder_ready,decoder_processing;
    wire replay_valid=state==REPLAY_BYTE && decoder_ready;
    // Capture the entire write command on the service edge, then commit it
    // on the opposite edge. The BRAM write port sees held address/data/WE;
    // its read port retains the original rising-edge replay latency.
    // This is a timed half-cycle path, not a false/multicycle exception.
    (* preserve=1,keep=1 *) reg sector_wr_valid;
    (* preserve=1,keep=1 *) reg [8:0] sector_wr_address;
    (* preserve=1,keep=1 *) reg [7:0] sector_wr_data;
    always @(posedge clk or posedge rst)begin
        if(rst)begin sector_wr_valid<=0;sector_wr_address<=0;sector_wr_data<=0;end
        else begin
            sector_wr_valid<=state==RECEIVE && kind==FILE_DATA && sector_valid;
            sector_wr_address<=byte_index;sector_wr_data<=sector_byte;
        end
    end
    always @(negedge clk)
        if(sector_wr_valid)file_sector[sector_wr_address]<=sector_wr_data;
    always @(posedge clk)replay_byte<=file_sector[replay_index];
    wire [31:0] partition_lba,root_cluster,fat_lba,data_lba,max_cluster;
    wire [31:0] current_cluster,next_cluster,file_position,first_cluster,file_size;
    wire [31:0] directory_lba,selected_cluster;
    wire [7:0] sectors_per_cluster,cluster_sector;
    wire [3:0] cluster_shift;
    wire [32:0] volume_end,fat_end;
    wire found_file,directory_end;
    wire signature_ok,direct_bpb,partition_ok,bpb_bad,layout_bad,geometry_bad;
    wire chain_end,chain_bad;
    wire [18:0] pixel_count;
    wire [23:0] pixel_rgb;
    wire header_ok,header_error,memory_done,commit_ready;
    wire [3:0] header_reject_reason;
    reg [3:0] first_header_reject;
    reg probed_any;
    reg [WATCHDOG_BITS-1:0] watchdog;
    wire sector_length_error=state==RECEIVE && ((sector_end &&
        sector_bytes + (sector_valid ? 10'd1 : 10'd0)!=512) ||
        (sector_valid && sector_bytes>=512));
    wire sector_service_error=state==RECEIVE && sector_end && sector_error!=0;
    wire job_reset=REUSE_CATALOG && (load_start || load_cancel);
    wire progress = (state==RECEIVE && sector_valid) || replay_valid || pixel_valid || state!=previous_state ||
        (state==BEGIN_WRITE && write_ack) || (state==WAIT_COMMIT && memory_done);
    function [31:0] cluster_address;
        input [31:0] cluster;
        begin cluster_address=data_lba+((cluster-2)<<cluster_shift); end
    endfunction
    assign audio_root_cluster=root_cluster;assign audio_fat_lba=fat_lba;
    assign audio_data_lba=data_lba;assign audio_max_cluster=max_cluster;
    assign audio_cluster_shift=cluster_shift;assign audio_sectors_per_cluster=sectors_per_cluster;
    // Phase strobes are combinational: extracted register banks update on the
    // same edge as before. One outer scheduler owns the shared sector service.
    wire volume_prepare=state==DECIDE && kind==BPB && !bpb_bad;
    wire mount_commit=state==VOLUME_CHECK && !geometry_bad;
    wire probe_begin=state==DECIDE && kind==DIRECTORY && found_file && AUTO_SCAN;
    wire probe_done=state==DECIDE && kind==SCAN_HEADER;
    always @(posedge clk or posedge rst)
        if(rst)begin first_header_reject<=0;probed_any<=0;end
        else if(probe_done)begin
            probed_any<=1;
            if(!header_ok && first_header_reject==0)first_header_reject<=header_reject_reason;
        end
    wire catalog_select=state==SCAN_FINISH && image_total==32;
    wire direct_select=state==DECIDE && kind==DIRECTORY && found_file && !AUTO_SCAN;
    wire directory_next=state==DECIDE && kind==DIRECTORY && !found_file && !directory_end;
    wire file_next=state==DECIDE && decoded_sector && kind==FILE_DATA && pixel_count!=307200 && file_position<file_size;
    wire advance_chain=state==DECIDE && kind==FAT_ENTRY &&
        !(AUTO_SCAN && !fat_for_file && chain_end) && !chain_bad;
    fat32_volume_geometry u_volume (
        .clk(clk),.rst(rst),.capture(state==RECEIVE && sector_valid && (kind==MBR || kind==BPB)),
        .is_mbr(kind==MBR),.byte_index(byte_index),.sector_byte(sector_byte),
        .select_partition(state==DECIDE && kind==MBR && signature_ok && !direct_bpb && partition_ok),
        .prepare(volume_prepare),.layout_step(state==VOLUME_LAYOUT && !layout_bad),
        .count_step(state==VOLUME_COUNT),.commit(mount_commit),
        .partition_lba(partition_lba),.root_cluster(root_cluster),.fat_lba(fat_lba),
        .data_lba(data_lba),.max_cluster(max_cluster),.sectors_per_cluster(sectors_per_cluster),
        .cluster_shift(cluster_shift),.volume_end(volume_end),.fat_end(fat_end),
        .signature_ok(signature_ok),.direct_bpb(direct_bpb),.partition_ok(partition_ok),
        .bpb_bad(bpb_bad),.layout_bad(layout_bad),.geometry_bad(geometry_bad));
    fat32_directory_catalog #(.AUTO_SCAN(AUTO_SCAN),.SELECT_BY_NAME(SELECT_BY_NAME)) u_catalog (
        .clk(clk),.rst(rst),.byte_valid(state==RECEIVE && sector_valid && kind==DIRECTORY),
        .byte_index(byte_index),.sector_byte(sector_byte),.sector_lba(sector_lba),
        .max_cluster(max_cluster),.image_index(image_index),.probe_begin(probe_begin),
        .probe_done(probe_done),.header_ok(header_ok),.resume_clear(directory_next || advance_chain),
        .scan_finish(state==SCAN_FINISH),.select_file(catalog_select),
        .load_ack(state==BEGIN_WRITE && found_file && write_ack),
        .found_file(found_file),.directory_end(directory_end),.first_cluster(first_cluster),
        .file_size(file_size),.directory_lba(directory_lba),.image_total(image_total),
        .catalog_valid(catalog_valid),.image_name(image_name),.selected_cluster(selected_cluster));
    fat32_stream_cursor u_stream (
        .clk(clk),.rst(rst),.mount(mount_commit),.load_file(catalog_select || direct_select),
        .clear_hops(catalog_select),.probe_begin(probe_begin),
        .step_sector((directory_next || file_next) && cluster_sector+1<sectors_per_cluster),
        .step_chain(advance_chain),
        .data_valid(state==RECEIVE && sector_valid && (kind==FILE_DATA || kind==SCAN_HEADER)),
        .fat_valid(state==RECEIVE && sector_valid && kind==FAT_ENTRY),
        .byte_index(byte_index),.sector_byte(sector_byte),.root_cluster(root_cluster),
        .file_cluster(catalog_select ? selected_cluster : first_cluster),.max_cluster(max_cluster),
        .current_cluster(current_cluster),.next_cluster(next_cluster),.file_position(file_position),
        .cluster_sector(cluster_sector),.chain_end(chain_end),.chain_bad(chain_bad));
    // BMP bytes and SDRAM completion have separate owners. Keep the existing
    // FIFO word layout and same-cycle error suppression at the byte boundary.
 wire content_valid;
 assign pixel_data={pixel_rgb,7'd0,content_valid};
 bmp24_decoder u_bmp (.content_valid(content_valid),
        .header_reject_reason(header_reject_reason),
        .clk(clk),.rst(rst | job_reset),.probe_start(probe_begin),.load_start(catalog_select),
        .byte_valid(replay_valid),
        .header_byte_valid(state==RECEIVE && sector_valid && (kind==FILE_DATA || kind==SCAN_HEADER)),
        .header_byte(sector_byte),.header_position(file_position),
        .decode_pixels(decoder_file_mode),
        .suppress_pixel(sector_length_error || sector_service_error || header_error),
        .sector_byte(replay_byte),
        // Each requested file sector starts at a 512-byte boundary.
        .file_position({replay_base[31:9],replay_index}),.file_size(file_size),
        .header_ok(header_ok),.header_error(header_error),.pixel_valid(pixel_valid),
        .pixel_rgb(pixel_rgb),.pixel_count(pixel_count),.byte_ready(decoder_ready),
        .processing(decoder_processing),.progress_rows(load_progress_rows));
    frame_commit_guard u_commit (
        .clk(clk),.rst(rst | job_reset),.write_accepted(state==BEGIN_WRITE && found_file && write_ack),
        .wait_commit(state==WAIT_COMMIT),.write_finish_toggle(write_finish_toggle),
        .memory_done(memory_done),.commit_ready(commit_ready),.image_ready(image_ready));
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=WAIT_READY; kind<=MBR; status<=0;
            sector_req<=0; sector_lba<=0; write_req<=0;
            byte_index<=0; sector_bytes<=0;previous_state<=WAIT_READY;diagnostic_stage<=1;
            fat_for_file<=0;
            watchdog<=0;
            decoded_sector<=0;replay_index<=0;replay_base<=0;
        end else begin
            sector_req<=0;
            previous_state<=state;
            if(state!=ERROR) begin
                if(state==WAIT_READY) diagnostic_stage<=!sd_ready ? 4'd1 : 4'd2;
                else if(state==BEGIN_WRITE && found_file) diagnostic_stage<=4;
                else if(state==WAIT_COMMIT) diagnostic_stage<=6;
                else if(kind==FILE_DATA || (kind==FAT_ENTRY && fat_for_file)) diagnostic_stage<=5;
                else diagnostic_stage<=3;
            end
            if (progress || (!AUTO_SCAN && state==WAIT_READY) || state==DONE || state==ERROR || (REUSE_CATALOG && state==CANCELED))
              watchdog<=0;
            else watchdog<=watchdog+1'b1;
            case (state)
                WAIT_READY: if (sd_ready && memory_ready) begin
                    status<=1; sector_lba<=0; kind<=MBR; state<=REQUEST;
                end
                REQUEST: if(!sector_busy) begin
                    // Last boundary check before the transport sees a request.
                    if ((kind==FAT_ENTRY && (sector_lba<fat_lba || {1'b0,sector_lba}>=fat_end)) ||
                        ((kind==DIRECTORY || kind==FILE_DATA || kind==SCAN_HEADER) &&
                         (sector_lba<data_lba || {1'b0,sector_lba}>=volume_end))) begin
                        state<=ERROR; status<=13; write_req<=0;
                    end else begin
                        sector_req<=1; byte_index<=0; sector_bytes<=0; state<=RECEIVE;
                        if(kind==FILE_DATA)begin decoded_sector<=0;replay_base<=file_position;end
                    end
                end
                RECEIVE: begin
                    if (sector_valid) begin
                        byte_index<=byte_index+1'b1;
                        if(sector_bytes<513)sector_bytes<=sector_bytes+1'b1;
                    end
                    if (sector_end) state<=DECIDE;
                end
                DECIDE: begin
                    case (kind)
                        MBR: if (!signature_ok) begin state<=ERROR;status<=10;end
                             else if(direct_bpb)begin kind<=BPB;state<=DECIDE;end
                             else if(partition_ok)begin
                                 sector_lba<=partition_lba;kind<=BPB;state<=REQUEST;
                             end else begin state<=ERROR;status<=10;end
                        BPB: if(bpb_bad)begin state<=ERROR;status<=10;end
                             else state<=VOLUME_LAYOUT;
                        DIRECTORY: if (found_file) begin
                                 if(AUTO_SCAN) begin
                                     // Geometry/current directory cluster stay intact during the probe.
                                     kind<=SCAN_HEADER;sector_lba<=cluster_address(first_cluster);
                                     state<=REQUEST;
                                 end else begin
                                      status<=3; write_req<=1; state<=BEGIN_WRITE;
                                 end
                             end else if (directory_end) begin
                                 if(AUTO_SCAN) state<=SELECT_PREFETCH;
                                 else begin state<=ERROR;status<=11;end
                             end else if (cluster_sector+1<sectors_per_cluster) begin
                                 sector_lba<=sector_lba+1'b1; state<=REQUEST;
                             end else begin
                                 sector_lba<=fat_lba+(current_cluster>>7);
                                 fat_for_file<=0; kind<=FAT_ENTRY; state<=REQUEST;
                             end
                        SCAN_HEADER: begin
                             if(header_ok && image_total==31) state<=SELECT_PREFETCH;
                             else begin kind<=DIRECTORY;sector_lba<=directory_lba;state<=REQUEST;end
                         end
                        FILE_DATA: if(!decoded_sector)begin replay_index<=0;state<=REPLAY_PREFETCH;end
                             else if (pixel_count==307200) begin
                                 status<=4; state<=WAIT_COMMIT;
                             end else if (file_position>=file_size) begin state<=ERROR; status<=12; end
                             else if (cluster_sector+1<sectors_per_cluster) begin
                                 sector_lba<=sector_lba+1'b1; state<=REQUEST;
                             end else begin
                                 sector_lba<=fat_lba+(current_cluster>>7);
                                 fat_for_file<=1; kind<=FAT_ENTRY; state<=REQUEST;
                             end
                        FAT_ENTRY: if (AUTO_SCAN && !fat_for_file && chain_end)
                                 state<=SELECT_PREFETCH;
                             else if (chain_bad) begin
                                 state<=ERROR; status<=13;
                             end else begin
                                 sector_lba<=cluster_address(next_cluster);
                                 kind<=fat_for_file ? FILE_DATA : DIRECTORY; state<=REQUEST;
                             end
                    endcase
                end
                VOLUME_LAYOUT: if(layout_bad)begin state<=ERROR;status<=10;end
                               else state<=VOLUME_COUNT;
                VOLUME_COUNT: state<=VOLUME_CHECK;
                VOLUME_CHECK: if(geometry_bad)begin state<=ERROR;status<=10;end
                              else begin status<=2;state<=BEGIN_WRITE;end
                SCAN_FINISH: begin
                    if(image_total!=32) begin
                        status<=11;state<=ERROR;
                        // Keep status 11 and the existing recovery semantics.
                        // With an empty catalog only, expose the first failed
                        // header predicate; D means no directory candidate.
                        diagnostic_stage<=probed_any ? first_header_reject : 4'd13;
                    end
                    else begin
                        // Clamp stale/out-of-range selection after a card contents change.
                        status<=3;write_req<=1;state<=BEGIN_WRITE;
                    end
                end
                BEGIN_WRITE: if (!found_file) begin
                        sector_lba<=cluster_address(current_cluster);
                        kind<=DIRECTORY; state<=REQUEST;
                    end else if (write_ack) begin
                        // SDRAM stays alive across loads; discard an old completion toggle.
                        write_req<=0; sector_lba<=cluster_address(current_cluster);
                        kind<=FILE_DATA; state<=REQUEST;
                    end
                WAIT_COMMIT: if (commit_ready) begin status<=5; state<=DONE; end
                REPLAY_PREFETCH:state<=REPLAY_BYTE;
                REPLAY_BYTE:if(decoder_ready)begin
                    if(replay_index==511)state<=REPLAY_DRAIN;
                    else begin replay_index<=replay_index+1'b1;state<=REPLAY_PREFETCH;end
                end
                REPLAY_DRAIN:if(!decoder_processing)begin decoded_sector<=1;state<=DECIDE;end
                SELECT_PREFETCH:state<=SCAN_FINISH;
                REUSE_WAIT: if(sd_ready && memory_ready && !sector_busy) state<=SELECT_PREFETCH;
                CANCELED: state<=CANCELED;
                DONE: state<=DONE;
                ERROR: begin state<=ERROR; write_req<=0; end
                default: begin state<=ERROR; status<=15; end
            endcase
            // End may coincide with the final byte. Reject short/overlong sectors
            // before parsing a partial header or publishing a partial frame.
            if(sector_length_error || header_error) begin
                state<=ERROR;status<=12;write_req<=0;
            end
            if (&watchdog && !progress && state!=DONE && state!=ERROR && state!=CANCELED && (AUTO_SCAN || state!=WAIT_READY)) begin
                state<=ERROR; status<=14; write_req<=0;
            end
            // Service errors take precedence over a partial-sector length error.
            // Preserve existing UI/recovery codes: length=12, transport timeout=14.
            if(sector_service_error)begin
                state<=ERROR;write_req<=0;
                status<=(sector_error==8'h02 || sector_error==8'h03) ? 4'd12 : 4'd14;
            end
            // Cancel at the loader boundary; the adapter drains its current
            // sector and the memory service drains its accepted burst.
            if(REUSE_CATALOG && load_cancel)begin
                state<=CANCELED;status<=0;write_req<=0;sector_req<=0;watchdog<=0;
            end else if(REUSE_CATALOG && load_start && catalog_valid)begin
                state<=REUSE_WAIT;status<=2;write_req<=0;sector_req<=0;
                byte_index<=0;sector_bytes<=0;watchdog<=0;fat_for_file<=0;
            end
        end
    end
endmodule
