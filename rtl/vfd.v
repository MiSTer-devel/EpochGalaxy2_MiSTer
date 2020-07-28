
module vfd(
	input clk,
	output reg [18:0] vfd_addr,
	output reg [7:0] vfd_dout,
	output reg vfd_vram_we,

	output reg [24:0] sdram_addr,
	input [7:0] sdram_data,
	output reg sdram_rd,

	input [3:0] C,
	input [3:0] D,
	input [3:0] E,
	input [3:0] F,
	input [3:0] G,
	input [3:0] H,
	input [2:0] I,

	input rdy
);

reg [3:0] grid; // col
always @*
 case ({ C[0], C[1], C[2], C[3], D[0], D[1], D[2], D[3], E[0], E[1] })
		10'b0000000001: grid = 4'd0;
		10'b0000000010: grid = 4'd1;
		10'b0000000100: grid = 4'd2;
		10'b0000001000: grid = 4'd3;
		10'b0000010000: grid = 4'd4;
		10'b0000100000: grid = 4'd5;
		10'b0001000000: grid = 4'd6;
		10'b0010000000: grid = 4'd7;
		10'b0100000000: grid = 4'd8;
		10'b1000000000: grid = 4'd9;
		default: grid = 4'hf;
	endcase

reg [16:0] cache[8:0];
always @(posedge clk)
	if (grid != 4'hf)
	 cache[grid] <= { F[3], F[2], G[2], F[1], G[1], G[0], F[0], H[3], H[2], G[3], I[0], I[2], I[1], H[0], H[1] };


// BG pxl to col/row decoder
wire [3:0] col = sdram_data[7:4] <= 4'd9 ? sdram_data[7:4] : sdram_data[3:0];
wire [4:0] row = sdram_data[7:4] == 4'd10 ? 5'd16 : { 1'd0, sdram_data[3:0] };

reg [2:0] state;
reg seg_en;
reg [24:0] sdram_mask_addr;

always @(posedge clk)
	if (rdy)
		case (state)

			3'b000: begin // init
				vfd_addr <= 0;
				sdram_addr <= 640*480;
				state <= 3'b001;
			end

			3'b001: begin // prepare sdram read mask pxl
				sdram_rd <= 1'b1;
				sdram_addr <= sdram_addr + 25'd1;
				state <= 3'b010;
			end

			3'b010: begin
				sdram_rd <= 1'b0;
				sdram_mask_addr <= sdram_addr;
				seg_en <= cache[col][row];
				state <= 3'b011;
			end

			3'b011: begin // setup bg read
				sdram_rd <= 1'b1;
				sdram_addr <= sdram_addr - 640*480; // point to bg
				state <= 3'b100;
			end

			3'b100: begin // read bg color
				vfd_vram_we <= 1'b1;
				vfd_addr <= sdram_addr;
				sdram_rd <= 1'b0;
				if (seg_en) begin
					vfd_dout <= sdram_data;
				end
			 	else begin
	  				vfd_dout <= { 2'b00, sdram_data[7], 2'b00, sdram_data[4], 1'b0, sdram_data[1] };
	  			end
				sdram_addr <= sdram_mask_addr;
				state <= sdram_addr >= 640*480 ? 3'b000 : 3'b001;
			end

		endcase



endmodule