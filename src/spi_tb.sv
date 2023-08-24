module spi_tb;
  
int TESTS = 1000;

// parameters
parameter CLK_PER_SCLK_EDGE = 1;
parameter DATA_WIDTH = 8;

logic[1:0] mode;
logic CPOL;
logic CPHA;
logic clk;
logic rst;
logic MISO;
logic start;
logic SCLK;
logic MOSI;
logic SS;
logic done;
logic ready;
logic[DATA_WIDTH - 1:0] master_data;
logic[DATA_WIDTH - 1:0] slave_data;
logic[DATA_WIDTH - 1:0] MOSI_data;
logic[DATA_WIDTH - 1:0] MISO_data;

int MISO_idx;
int MOSI_idx;

assign CPHA = mode[0];
assign CPOL = mode[1];


spi #(.CLK_PER_SCLK_EDGE (CLK_PER_SCLK_EDGE),
      .DATA_WIDTH (DATA_WIDTH)) dut
       (.mode (mode),
        .snd_data (master_data),
        .clk (clk),
        .rst (rst),
        .MISO (MISO),
        .start (start),
        .SCLK (SCLK),
        .MOSI (MOSI),
        .SS (SS),
        .rcv_data (MISO_data),
        .done (done),
        .ready (ready));

// Clock
always begin
	clk = 0;
	#5ns;
	clk = 1;
	#5ns;
end

// sample / shift data during spi transfer
always @(posedge SCLK) begin
    if(!SS) begin
        if(mode == 0 || mode == 3)
            shift_MOSI_data();
        else
            shift_MISO_data();
    end
end

always @(negedge SCLK) begin
    if (!SS) begin
        if(mode == 0 || mode == 3)
            shift_MISO_data();
        else
            shift_MOSI_data();
    end
end

initial begin
    start = 0;
    rst = 1;
    #2ns; 
    rst = 0;

    for(int i = 0; i < TESTS; i++) begin
        mode = $urandom_range(0, 3);
        $display("TEST No. %d, Mode = %d", i, mode);
        wait(ready);
        start = 1;
        master_data = $urandom();
        slave_data = $urandom();
        MOSI_idx = 0;
        MISO_idx = 0;
        // when CPHA == 0, the slave shifts the first bit
        // half a clock cycle before the first(leading) edge
        // which is the time when the SS signal becomes 0
        @(negedge SS) begin
            start = 0;
            if(!CPHA) 
                shift_MISO_data();
        end
        // wait till the operation is completed
        wait(done);
        assert(SS);
        assert(MOSI_data == master_data);
        assert(MISO_data == slave_data);
        $display("MOSI_data = %d \n", MOSI_data);
        $display("MISO_data = %d \n", MISO_data);
    end
    $display("Tests completed successfully! \n");
    $stop;
end

task shift_MOSI_data();
    MOSI_data[MOSI_idx] <= MOSI;
    MOSI_idx++;
endtask

task shift_MISO_data();
    MISO <= slave_data[MISO_idx];
    MISO_idx++;
endtask

endmodule
