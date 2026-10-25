`timescale 1ns / 1ps

module axi_ram_top #(
    parameter DATA_WIDTH = 32,  // Data bus width (usually 32 or 64)
    parameter ADDR_WIDTH = 10   // Address width (depth of RAM)
)(
    input  wire                  clk,       // System Clock
    input  wire                  rst_n,     // Active Low Reset

    // --- Write Address Channel (AW) ---
    input  wire [ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,

    // --- Write Data Channel (W) ---
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb, // Byte enables
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,

    // --- Write Response Channel (B) ---
    output wire [1:0]            s_axi_bresp,
    output wire                  s_axi_bvalid,
    input  wire                  s_axi_bready,

    // --- Read Address Channel (AR) ---
    input  wire [ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,

    // --- Read Data Channel (R) ---
    output wire [DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]            s_axi_rresp,
    output wire                  s_axi_rvalid,
    input  wire                  s_axi_rready
);

    // --- Internal Connection Wires ---
    
    // Write Address signals
    wire [ADDR_WIDTH-1:0] aw_addr_int;   // Latched write address
    wire                  aw_handshake_done; // Flag: Address received

    // Write Data signals
    wire [DATA_WIDTH-1:0] w_data_int;    // Latched write data
    wire [DATA_WIDTH/8-1:0] w_strb_int;  // Latched byte strobes
    wire                  w_handshake_done;  // Flag: Data received

    // Write Logic Control
    reg                   ram_write_en;  // Signal to trigger RAM write
    wire                  b_done_trigger; // Triggers the response channel

    // Read Address signals
    wire [ADDR_WIDTH-1:0] ar_addr_int;   // Latched read address
    wire                  ar_handshake_done; // Flag: Address received

    // Read Data signals
    wire [DATA_WIDTH-1:0] ram_rdata_int; // Data coming out of RAM
    // -------------------------------------------------------------------------
    // Logic to delay Read Data Available trigger by 1 cycle for Sync RAM
    // -------------------------------------------------------------------------
    reg ar_handshake_done_delayed;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ar_handshake_done_delayed <= 1'b0;
        else
            ar_handshake_done_delayed <= ar_handshake_done;
    end
    // -------------------------------------------------------------------------
    // 1. Write Address Channel Instance
    // -------------------------------------------------------------------------
    axi_write_addr_channel #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_aw_channel (
        .clk(clk),
        .rst_n(rst_n),
        .awvalid(s_axi_awvalid),
        .awready(s_axi_awready),
        .awaddr(s_axi_awaddr),
        .aw_addr_out(aw_addr_int),
        .aw_done(aw_handshake_done),
        .w_done_in(w_handshake_done), // Need to know if data is also ready
        .b_ready_in(s_axi_bready),
        .b_valid_in(s_axi_bvalid)
    );

    // -------------------------------------------------------------------------
    // 2. Write Data Channel Instance
    // -------------------------------------------------------------------------
    axi_write_data_channel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_w_channel (
        .clk(clk),
        .rst_n(rst_n),
        .wvalid(s_axi_wvalid),
        .wready(s_axi_wready),
        .wdata(s_axi_wdata),
        .wstrb(s_axi_wstrb),
        .w_data_out(w_data_int),
        .w_strb_out(w_strb_int),
        .w_done(w_handshake_done),
        .aw_done_in(aw_handshake_done) // Need to know if addr is also ready
    );

    // -------------------------------------------------------------------------
    // Logic to trigger the RAM Write and Response
    // -------------------------------------------------------------------------
    // We write to RAM only when both Write Address and Write Data handshakes are done.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ram_write_en <= 1'b0; // Disable write on reset
        end else begin
            // If both Address and Data are valid/latched, trigger the write
            if (aw_handshake_done && w_handshake_done && !s_axi_bvalid)
                ram_write_en <= 1'b1;
            else
                ram_write_en <= 1'b0;
        end
    end
    
    assign b_done_trigger = ram_write_en; // Send response after write attempt

    // -------------------------------------------------------------------------
    // 3. Write Response Channel Instance
    // -------------------------------------------------------------------------
    axi_write_resp_channel u_b_channel (
        .clk(clk),
        .rst_n(rst_n),
        .write_done_trigger(b_done_trigger), // Input: RAM write finished
        .bvalid(s_axi_bvalid),
        .bready(s_axi_bready),
        .bresp(s_axi_bresp)
    );

    // -------------------------------------------------------------------------
    // 4. Read Address Channel Instance
    // -------------------------------------------------------------------------
    axi_read_addr_channel #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ar_channel (
        .clk(clk),
        .rst_n(rst_n),
        .arvalid(s_axi_arvalid),
        .arready(s_axi_arready),
        .araddr(s_axi_araddr),
        .ar_addr_out(ar_addr_int),
        .ar_done(ar_handshake_done),
        .r_valid_in(s_axi_rvalid) // Wait if previous read data isn't taken yet
    );

    // -------------------------------------------------------------------------
    // 5. Read Data Channel Instance
    // -------------------------------------------------------------------------
    axi_read_data_channel #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_r_channel (
        .clk(clk),
        .rst_n(rst_n),
        .read_data_avail(ar_handshake_done_delayed), // CORRECTED: Delayed by 1 cycle
        .ram_data_in(ram_rdata_int),
        .rvalid(s_axi_rvalid),
        .rready(s_axi_rready),
        .rdata(s_axi_rdata),
        .rresp(s_axi_rresp)
    );

    // -------------------------------------------------------------------------
    // 6. RAM Module Instance
    // -------------------------------------------------------------------------
    ram_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_ram (
        .clk(clk),
        .we(ram_write_en),         // Write Enable calculated above
        .waddr(aw_addr_int),       // Address from AW channel
        .wdata(w_data_int),        // Data from W channel
        .wstrb(w_strb_int),        // Strobes from W channel
        .raddr(ar_addr_int),   // CORRECT: Use the safely latched address
        .rdata(ram_rdata_int)      // Data out to R channel
    );

endmodule
module axi_write_addr_channel #(
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // AXI Signals
    input  wire                  awvalid,      // Master says: Address is valid
    output reg                   awready,      // Slave says: I am ready to take address
    input  wire [ADDR_WIDTH-1:0] awaddr,       // The address

    // Internal Signals
    output reg  [ADDR_WIDTH-1:0] aw_addr_out,  // Latched address for RAM
    output reg                   aw_done,      // Handshake complete flag
    input  wire                  w_done_in,    // Status of Write Data channel
    input  wire                  b_ready_in,   // Status of Response channel
    input  wire                  b_valid_in    // Status of Response channel
);

    // Logic: Ready should be high when we are not already processing a write response
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready     <= 1'b0;         // Reset ready signal
            aw_done     <= 1'b0;         // Reset done flag
            aw_addr_out <= 0;            // Clear address
        end else begin
            // If valid is asserted and we aren't ready yet, and not blocked by previous response
            if (~awready && awvalid && (!b_valid_in || b_ready_in)) begin
                awready     <= 1'b1;     // Assert Ready to complete handshake
                aw_addr_out <= awaddr;   // Latch the address
                aw_done     <= 1'b1;     // Mark this step as done
            end else begin
                // Deassert Ready after one cycle (or if invalid)
                awready <= 1'b0; 
                
                // Clear the 'done' flag only when the full transaction (Data+Addr) is consumed
                if (w_done_in && aw_done) 
                    aw_done <= 1'b0;     // Reset done flag for next transaction
            end
        end
    end
endmodule
module axi_write_data_channel #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // AXI Signals
    input  wire                  wvalid,       // Master says: Data is valid
    output reg                   wready,       // Slave says: I am ready
    input  wire [DATA_WIDTH-1:0] wdata,        // The Data
    input  wire [DATA_WIDTH/8-1:0] wstrb,      // Write Strobes

    // Internal Signals
    output reg  [DATA_WIDTH-1:0] w_data_out,   // Latched data for RAM
    output reg  [DATA_WIDTH/8-1:0] w_strb_out, // Latched strobes for RAM
    output reg                   w_done,       // Handshake complete flag
    input  wire                  aw_done_in    // Status of Write Addr channel
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wready     <= 1'b0;          // Reset Ready
            w_done     <= 1'b0;          // Reset done flag
            w_data_out <= 0;             // Clear internal data
        end else begin
            // Handshake Logic: If valid comes and we are idle
            if (~wready && wvalid) begin
                wready      <= 1'b1;     // Assert Ready
                w_data_out  <= wdata;    // Latch Data
                w_strb_out  <= wstrb;    // Latch Strobes
                w_done      <= 1'b1;     // Mark done
            end else begin
                wready <= 1'b0;          // Deassert Ready
                
                // Clear done flag when both Addr and Data have met up
                if (aw_done_in && w_done) 
                    w_done <= 1'b0;
            end
        end
    end
endmodule
module axi_write_resp_channel (
    input  wire       clk,
    input  wire       rst_n,

    // Internal Signals
    input  wire       write_done_trigger, // Input from Top: RAM write finished

    // AXI Signals
    output reg        bvalid,       // Slave says: Response is valid
    input  wire       bready,       // Master says: I am ready for response
    output wire [1:0] bresp         // Response status (00 = OKAY)
);

    assign bresp = 2'b00; // Always return "OKAY" for this simple RAM

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvalid <= 1'b0;             // Reset valid
        end else begin
            // If the RAM write happened, we need to send a response
            if (write_done_trigger && ~bvalid) begin
                bvalid <= 1'b1;         // Assert Valid response
            end 
            // If Master accepted the response (Handshake complete)
            else if (bvalid && bready) begin
                bvalid <= 1'b0;         // Deassert Valid
            end
        end
    end
endmodule
module axi_read_addr_channel #(
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // AXI Signals
    input  wire                  arvalid,      // Master says: Address valid
    output reg                   arready,      // Slave says: Ready for address
    input  wire [ADDR_WIDTH-1:0] araddr,       // The Address

    // Internal Signals
    output reg  [ADDR_WIDTH-1:0] ar_addr_out,  // Latched Address for RAM
    output reg                   ar_done,      // Flag: Read Addr accepted
    input  wire                  r_valid_in    // Status: Is the R channel busy?
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready     <= 1'b0;         // Reset ready
            ar_done     <= 1'b0;         // Reset done flag
            ar_addr_out <= 0;
        end else begin
            // Accept address if valid and we aren't stuck sending previous data
            if (~arready && arvalid && !r_valid_in) begin
                arready     <= 1'b1;     // Assert Ready
                ar_addr_out <= araddr;   // Latch Address
                ar_done     <= 1'b1;     // Signal that we have a read request
            end else begin
                arready <= 1'b0;         // Deassert Ready
                
                // Clear the trigger pulse
                if (ar_done)
                    ar_done <= 1'b0; 
            end
        end
    end
endmodule
module axi_read_data_channel #(
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Internal Signals
    input  wire                  read_data_avail, // Input: Request occurred
    input  wire [DATA_WIDTH-1:0] ram_data_in,     // Data from RAM

    // AXI Signals
    output reg                   rvalid,      // Slave says: Data valid
    input  wire                  rready,      // Master says: Ready for data
    output reg  [DATA_WIDTH-1:0] rdata,       // The Data
    output wire [1:0]            rresp        // Response (00 = OKAY)
);

    assign rresp = 2'b00; // OKAY response

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid <= 1'b0;             // Reset Valid
            rdata  <= 0;                // Clear Data
        end else begin
            // If a read request happened (avail), present data and assert Valid
            if (read_data_avail && ~rvalid) begin
                rvalid <= 1'b1;         // Assert Valid
                rdata  <= ram_data_in;  // Load data onto bus
            end
            // If handshake completes (Master accepted data)
            else if (rvalid && rready) begin
                rvalid <= 1'b0;         // Deassert Valid (transaction done)
            end
        end
    end
endmodule
module ram_memory #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
)(
    input  wire                  clk,
    input  wire                  we,          // Write Enable
    input  wire [ADDR_WIDTH-1:0] waddr,       // Write Address
    input  wire [DATA_WIDTH-1:0] wdata,       // Write Data
    input  wire [DATA_WIDTH/8-1:0] wstrb,     // Write Strobes
    
    input  wire [ADDR_WIDTH-1:0] raddr,       // Read Address
    output reg  [DATA_WIDTH-1:0] rdata        // Read Data
);

    // Define the Memory Array
    reg [DATA_WIDTH-1:0] mem [(2**ADDR_WIDTH)-1:0];

    // Integer for loops
    integer i;

    // -------------------------------------------------------------------------
    // INITIALIZATION BLOCK (The Fix)
    // -------------------------------------------------------------------------
    initial begin
        for (i = 0; i < (2**ADDR_WIDTH); i = i + 1) begin
            mem[i] = 0; // Initialize all locations to Zero
        end
    end

    // --- Write Operation ---
    always @(posedge clk) begin
        if (we) begin
            for (i = 0; i < (DATA_WIDTH/8); i = i + 1) begin
                if (wstrb[i]) begin
                    mem[waddr][8*i +: 8] <= wdata[8*i +: 8]; 
                end
            end
        end
    end

    // --- Read Operation ---
    always @(posedge clk) begin
        rdata <= mem[raddr]; 
    end

endmodule
