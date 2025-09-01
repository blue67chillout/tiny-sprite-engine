/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_tiny_sprite_engine (
    input  wire        clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input  wire        rst_n,        // Reset_n - low to reset.

    input  wire  [7:0] ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                     // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output wire  [7:0] uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                     // Note that uo_out[0] is normally used for UART TX.

    input  wire  [5:0] address,      // Address within this peripheral's address space
    input  wire [31:0] data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input  wire  [1:0] data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input  wire  [1:0] data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits

    output wire [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output wire        data_ready,

    output wire        user_interrupt  // Dedicated interrupt request for this peripheral
);

    reg hsync;
    reg vsync;
    wire visible;
    reg [9:0] pix_x;
    reg [9:0] pix_y;
    
    wire [1:0]R,G,B ;
    
    video_controller u_video_controller(
        .clk      	(clk       ),
        .reset    	(rst_n     ),
        .polarity 	(1'b1      ), // 0 = negative polarity (VGA, SVGA), 1 = positive polarity (XGA, SXGA)
        .hsync    	(hsync     ),
        .vsync    	(vsync     ),
        .visible  	(visible   ),
        .pix_x    	(pix_x     ),
        .pix_y    	(pix_y     )
    );
    

wire [1:0] bg_R, bg_G, bg_B;
    bg background (
        .clk(clk),
        .rst_n(rst_n),
        .video_active(visible),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .vsync(vsync),
        .R(bg_R),
        .G(bg_G),
        .B(bg_B)
    );

    //-------------------------------------------------------------------
    // Sprite Engine - up to 8 objects, fluid RAM format
    //-------------------------------------------------------------------
    wire sprite_pixel_on;
    fluid_sprite #(.MAX_SPRITES(8)) sprite_engine (
        .clk(clk),
        .rst_n(rst_n),
        .video_active(visible),
        .pix_x(pix_x),
        .pix_y(pix_y),
        .vsync(vsync),
        // Flat RAM Bus exposure
        .address(address),
        .data_in(data_in),
        .data_write_n(data_write_n),
        .data_read_n(data_read_n),
        .data_out(data_out),
        .data_ready(data_ready),
        .user_interrupt(user_interrupt),
        // Result: pixel
        .sprite_pixel_on(sprite_pixel_on)
    );

    //-------------------------------------------------------------------
    // Final Foreground-over-Background
    //-------------------------------------------------------------------
    assign R = sprite_pixel_on              ? 2'b11 : bg_R;
    assign G = R;
    assign B = R;




endmodule
