module fluid_sprite #(
    parameter MAX_SPRITES = 8   // fixed, static for synthesis
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        video_active,   // 1 = pixel in visible area
    input  wire [9:0]  pix_x,         // physical pixel: 0..1023
    input  wire [9:0]  pix_y,         // physical pixel: 0..767
    input  wire        vsync,
    // Host sprite RAM interface
    input  wire  [5:0] address,
    input  wire [31:0] data_in,
    input  wire  [1:0] data_write_n,
    input  wire  [1:0] data_read_n,
    output reg  [31:0] data_out,
    output reg         data_ready,
    output wire        user_interrupt,
    // Sprite pixel out (1=foreground)
    output wire        sprite_pixel_on
);

    // --- 8-bit-wide, 63-byte physical RAM (address 63 reserved) ---
    reg [7:0] sprite_ram [0:63];

    // Host RAM read/write
    always @(posedge clk) begin
        if (!rst_n) begin
            // Optionally clear RAM here.
        end else if (data_write_n != 2'b11 && address < 63) begin
            if      (data_write_n == 2'b00) sprite_ram[address]     <= data_in[7:0];
            else if (data_write_n == 2'b01 && (address < 62))
                {sprite_ram[address+1], sprite_ram[address]}         <= data_in[15:0];
            else if (data_write_n == 2'b10 && (address < 60))
                {sprite_ram[address+3], sprite_ram[address+2], sprite_ram[address+1], sprite_ram[address]} <= data_in[31:0];
        end
    end

    always @* begin
        data_ready = (data_read_n != 2'b11);
        data_out = 32'b0;
        if (data_read_n == 2'b00) data_out[7:0]   = sprite_ram[address];
        else if (data_read_n == 2'b01)
            data_out[15:0] = {sprite_ram[address+1], sprite_ram[address]};
        else if (data_read_n == 2'b10)
            data_out[31:0] = {sprite_ram[address+3], sprite_ram[address+2], sprite_ram[address+1], sprite_ram[address]};
    end
    assign user_interrupt = 1'b0;

    // --- Physical to logical mapping (nearest-neighbor 4x scaling) ---
    // 1024/4 = 256, 768/4 = 192
    wire [7:0] logic_x = pix_x[9:2];
    wire [7:0] logic_y = pix_y[9:2];

    // --- Each object = 4 bytes: X, Y, bitmap_offset, {width-1, height-1} ---
    localparam OBJ_BYTES = 4;

    integer spr_idx;
    reg pix_hit;

    always @ (*) begin
        pix_hit = 1'b0;
        for (spr_idx = 0; spr_idx < MAX_SPRITES; spr_idx = spr_idx + 1) begin : SPRITES
            reg [7:0] x, y, bitmap_offset, size_byte;
            reg [3:0] width, height;
            reg [3:0] spr_x, spr_y;
            integer bit_offset, byte_addr, bit_in_byte;
            reg [7:0] bmp_byte;
            reg bmp_bit;

            // Sprite object fields in RAM
            x = sprite_ram[spr_idx*OBJ_BYTES + 0];
            y = sprite_ram[spr_idx*OBJ_BYTES + 1];
            bitmap_offset = sprite_ram[spr_idx*OBJ_BYTES + 2];
            size_byte = sprite_ram[spr_idx*OBJ_BYTES + 3];
            width  = size_byte[7:4] + 1;
            height = size_byte[3:0] + 1;

            // SPRITE BLIT: all in logical coordinates!
            if (    video_active
                && (logic_x >= x) && (logic_x < x + width)
                && (logic_y >= y) && (logic_y < y + height)) begin
                spr_x = logic_x - x;
                spr_y = logic_y - y;
                bit_offset = spr_y * width + spr_x;
                byte_addr = bitmap_offset + (bit_offset >> 3); // each byte = 8 bits
                bit_in_byte = bit_offset % 8;
                if (byte_addr < 63) begin
                    bmp_byte = sprite_ram[byte_addr];
                    bmp_bit = bmp_byte[bit_in_byte];
                    pix_hit = pix_hit | bmp_bit;
                end
            end
        end
    end

    assign sprite_pixel_on = pix_hit;

endmodule
