// fluid_sprite.v
// Verilog-2001 - sprite unit with staging/active object tables, bitmap region,
// controlled bitmap-write mode, and vsync-driven user_interrupt request/swap.

module fluid_sprite #(
    parameter MAX_SPRITES = 2         // must be small for combinational rendering
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        video_active,   // 1 = pixel in visible area
    input  wire [9:0]  pix_x,          // physical pixel: 0..1023
    input  wire [9:0]  pix_y,          // physical pixel: 0..767
    input  wire        vsync,          // vertical sync (frame boundary)
    // Host sprite RAM interface
    input  wire  [5:0] address,        // byte address 0..63
    input  wire [31:0] data_in,
    input  wire  [1:0] data_write_n,   // 00 byte, 01 halfword, 10 word, 11 no-write
    input  wire  [1:0] data_read_n,    // 00 byte, 01 halfword, 10 word, 11 no-read
    output reg  [31:0] data_out,
    output reg         data_ready,
    output reg         user_interrupt, // pulse (1 cycle) to request staging update
    // Sprite pixel out (1=foreground)
    output wire        sprite_pixel_on
);

    // ---- memory map and sizes ----
 
    // Layout convention:
    // 0 .. OBJ_BYTES*MAX_SPRITES-1 : object table (staging writes; active used for display)
    // BITMAP_BASE .. BITMAP_BASE + BITMAP_BYTES-1 : bitmap storage (1bpp packed)
    // CONTROL_ADDR : control/status register (single byte used)
    localparam OBJ_BYTES     = 4;
    localparam OBJ_REGION_SZ = OBJ_BYTES * MAX_SPRITES; // bytes used for object table
    localparam BITMAP_BASE   = OBJ_REGION_SZ;           // start address for bitmap storage (auto-adjusted)
    localparam BITMAP_BYTES  = 63 - OBJ_REGION_SZ;      // remaining bytes up to CONTROL_ADDR
    localparam CONTROL_ADDR  = 63;                      // last byte reserved for control/status

    // --- internal memories ---
    reg [7:0] active_obj_ram  [0:OBJ_REGION_SZ-1]; // read by renderer (active frame)
    reg [7:0] stage_obj_ram   [0:OBJ_REGION_SZ-1]; // written by host for next frame
    reg [7:0] bitmap_ram      [0:BITMAP_BYTES-1]; // packed 1bpp bitmaps; host writes here only when enabled

    // --- control register bits (in CONTROL_ADDR) ---
    // bit0 = BITMAP_WRITE_EN  : when 1, host may write bitmap region
    // bit1 = STAGING_READY    : host writes 1 to indicate staging table is ready
    // bit2 = (reserved)
    reg [7:0] control_reg;

    // --- host read/write interface ---
    // Writes go to:
    //  - addresses < OBJ_REGION_SZ => stage_obj_ram (staging update)
    //  - BITMAP_BASE.. => bitmap_ram (only when BITMAP_WRITE_EN set)
    //  - CONTROL_ADDR => control_reg (byte writes only)
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            // reset memories & control
            for (i = 0; i < OBJ_REGION_SZ; i = i + 1) begin
                active_obj_ram[i] <= 8'b0;
                stage_obj_ram[i]  <= 8'b0;
            end
            for (i = 0; i < BITMAP_BYTES; i = i + 1) begin
                bitmap_ram[i] <= 8'b0;
            end
            control_reg <= 8'b0;
        end else begin
            // Host writes (synchronous)
            if (data_write_n != 2'b11) begin
                // compute write width and perform writes (byte/half/word) at address
                // only perform writes if address and region valid and allowed by control_reg
                if (data_write_n == 2'b00) begin
                    // byte write
                    if (address < OBJ_REGION_SZ) begin
                        stage_obj_ram[address] <= data_in[7:0];
                    end else if ((address >= BITMAP_BASE) && (address < BITMAP_BASE + BITMAP_BYTES)) begin
                        if (control_reg[0]) // BITMAP_WRITE_EN
                            bitmap_ram[address - BITMAP_BASE] <= data_in[7:0];
                    end else if (address == CONTROL_ADDR) begin
                        control_reg <= data_in[7:0];
                    end
                end else if (data_write_n == 2'b01) begin
                    // halfword (16-bit) write - address must be <= 62
                    if ((address + 1) < OBJ_REGION_SZ) begin
                        stage_obj_ram[address]   <= data_in[7:0];
                        stage_obj_ram[address+1] <= data_in[15:8];
                    end else if ((address >= BITMAP_BASE) && ((address + 1) < BITMAP_BASE + BITMAP_BYTES)) begin
                        if (control_reg[0]) begin
                            bitmap_ram[address - BITMAP_BASE]     <= data_in[7:0];
                            bitmap_ram[address+1 - BITMAP_BASE] <= data_in[15:8];
                        end
                    end else if (address == CONTROL_ADDR - 1) begin
                        // allow halfword write that ends at CONTROL_ADDR
                        control_reg <= data_in[15:8];
                    end
                end else if (data_write_n == 2'b10) begin
                    // word (32-bit) write - address must be <= 60
                    if ((address + 3) < OBJ_REGION_SZ) begin
                        stage_obj_ram[address]   <= data_in[7:0];
                        stage_obj_ram[address+1] <= data_in[15:8];
                        stage_obj_ram[address+2] <= data_in[23:16];
                        stage_obj_ram[address+3] <= data_in[31:24];
                    end else if ((address >= BITMAP_BASE) && ((address + 3) < BITMAP_BASE + BITMAP_BYTES)) begin
                        if (control_reg[0]) begin
                            bitmap_ram[address - BITMAP_BASE]     <= data_in[7:0];
                            bitmap_ram[address+1 - BITMAP_BASE] <= data_in[15:8];
                            bitmap_ram[address+2 - BITMAP_BASE] <= data_in[23:16];
                            bitmap_ram[address+3 - BITMAP_BASE] <= data_in[31:24];
                        end
                    end else if (address == CONTROL_ADDR - 3) begin
                        control_reg <= data_in[31:24];
                    end
                end
            end
            // Note: we keep reading/writing staging only. Active table is swapped later at vsync.
        end
    end

reg [1:0] data_read_n_reg;
reg [5:0] address_reg;

always @(posedge clk ) begin
    if (!rst_n) begin
        data_ready <= 1'b0;
        data_out   <= 32'b0;
        data_read_n_reg <= 2'b11;
        address_reg     <= 6'b0;
    end else begin
        // Latch the read request
        data_read_n_reg <= data_read_n;
        address_reg     <= address;

        data_ready <= (data_read_n_reg != 2'b11);
        data_out   <= 32'b0;
        if (data_read_n_reg != 2'b11) begin
            if (data_read_n_reg == 2'b00) begin
                // byte read
                if (address_reg < OBJ_REGION_SZ) data_out[7:0] <= active_obj_ram[address_reg];
                else if ((address_reg >= BITMAP_BASE) && (address_reg < BITMAP_BASE + BITMAP_BYTES))
                    data_out[7:0] <= bitmap_ram[address_reg - BITMAP_BASE];
                else if (address_reg == CONTROL_ADDR) data_out[7:0] <= control_reg;
            end else if (data_read_n_reg == 2'b01) begin
                // halfword
                if ((address_reg + 1) < OBJ_REGION_SZ) begin
                    data_out[15:0] <= { active_obj_ram[address_reg+1], active_obj_ram[address_reg] };
                end else if ((address_reg >= BITMAP_BASE) && ((address_reg + 1) < BITMAP_BASE + BITMAP_BYTES)) begin
                    data_out[15:0] <= { bitmap_ram[address_reg+1 - BITMAP_BASE], bitmap_ram[address_reg - BITMAP_BASE] };
                end else if (address_reg == CONTROL_ADDR - 1) begin
                    data_out[15:0] <= { 8'b0, control_reg };
                end
            end else if (data_read_n_reg == 2'b10) begin
                // word
                if ((address_reg + 3) < OBJ_REGION_SZ) begin
                    data_out[31:0] <= { active_obj_ram[address_reg+3], active_obj_ram[address_reg+2],
                                        active_obj_ram[address_reg+1], active_obj_ram[address_reg] };
                end else if ((address_reg >= BITMAP_BASE) && ((address_reg + 3) < BITMAP_BASE + BITMAP_BYTES)) begin
                    data_out[31:0] <= { bitmap_ram[address_reg+3 - BITMAP_BASE], bitmap_ram[address_reg+2 - BITMAP_BASE],
                                        bitmap_ram[address_reg+1 - BITMAP_BASE], bitmap_ram[address_reg - BITMAP_BASE] };
                end else if (address_reg == CONTROL_ADDR - 3) begin
                    data_out[31:0] <= { 24'b0, control_reg };
                end
            end
        end
    end
end

    // ---- vsync / staging swap / user_interrupt protocol ----
    // On each rising edge of vsync:
    //   if (STAGING_READY == 0) => pulse user_interrupt for 1 cycle to ask host to provide staging data.
    //   if (STAGING_READY == 1) => copy staging_obj_ram -> active_obj_ram and clear STAGING_READY.
    reg vsync_d;
    always @(posedge clk) vsync_d <= vsync;

    // user_interrupt pulse generator (1 clock) on vsync rising when staging not ready
    always @(posedge clk) begin
        if (!rst_n) user_interrupt <= 1'b0;
        else begin
            user_interrupt <= 1'b0; // default
            if (vsync && !vsync_d) begin // rising edge
                if (!control_reg[1]) begin
                    // request new staging data for next frame
                    user_interrupt <= 1'b1;
                end else begin
                    // staging ready -> commit it now (copy to active)
                    for (i = 0; i < OBJ_REGION_SZ; i = i + 1) begin
                        active_obj_ram[i] <= stage_obj_ram[i];
                    end
                    // clear STAGING_READY bit (host must set it again next frame when new staging is ready)
                    control_reg[1] <= 1'b0;
                    user_interrupt <= 1'b0;
                end
            end
        end
    end

    // --- Rendering: physical -> logical mapping (nearest-neighbor 4x scaling) ---
    wire [7:0] logic_x = pix_x[9:2]; // 1024/4 = 256
    wire [7:0] logic_y = pix_y[9:2]; // 768/4  = 192

    // --- Sprite test loop uses active_obj_ram for stable frame display ---
// --- Sprite test loop uses active_obj_ram for stable frame display ---
    integer spr_idx;
    reg pix_hit;
    always @(posedge clk ) begin
        if (!rst_n) begin
            pix_hit <= 1'b0;
        end else begin
            pix_hit <= 1'b0;
            for (spr_idx = 0; spr_idx < MAX_SPRITES; spr_idx = spr_idx + 1) begin : SPRITES
                // local variables per sprite
                reg [7:0] x, y, bitmap_offset, size_byte;
                reg [3:0] width, height;
                reg [3:0] spr_x, spr_y;
                integer bit_offset;
                integer byte_addr;
                integer bit_in_byte;
                reg [7:0] bmp_byte;
                reg bmp_bit;

                // Provide default values
                spr_x = 4'b0;
                spr_y = 4'b0;
                bit_offset = 0;
                byte_addr = 0;
                bit_in_byte = 0;
                bmp_byte = 8'b0;
                bmp_bit = 1'b0;

                // read object fields from active_obj_ram
                x = active_obj_ram[spr_idx*OBJ_BYTES + 0];
                y = active_obj_ram[spr_idx*OBJ_BYTES + 1];
                bitmap_offset = active_obj_ram[spr_idx*OBJ_BYTES + 2];
                size_byte = active_obj_ram[spr_idx*OBJ_BYTES + 3];
                width  = size_byte[7:4] + 1;
                height = size_byte[3:0] + 1;

                // bounds check and fast reject
                if ( video_active
                  && (logic_x >= x) && (logic_x < x + width)
                  && (logic_y >= y) && (logic_y < y + height) ) begin
                    // local coordinates in sprite
                    spr_x = logic_x - x;
                    spr_y = logic_y - y;
                    // bit addressing: row-major, 1 bit per pixel
                    bit_offset = spr_y * width + spr_x;
                    byte_addr  = bitmap_offset + (bit_offset >> 3); // which byte in bitmap_ram
                    bit_in_byte = bit_offset & 3'b111;               // bit index in that byte
                    if ((byte_addr >= 0) && (byte_addr < BITMAP_BYTES)) begin
                        bmp_byte = bitmap_ram[byte_addr];
                        // assume LSB is bit 0; if your asset format is MSB-first use bmp_byte[7-bit_in_byte]
                        bmp_bit = bmp_byte[bit_in_byte];
                        pix_hit <= pix_hit | bmp_bit;
                    end
                end
            end
        end
    end

    assign sprite_pixel_on = pix_hit;

endmodule
