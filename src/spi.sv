module spi#(CLK_PER_SCLK_EDGE = 1,                     // The number of the input clock's(clk) cycles per SCLK cycle.
            DATA_WIDTH = 8)                            // The number of bits of the data to be transmitted.
           (input  logic [1:0]               mode,     // SPI MODE
            input  logic [DATA_WIDTH - 1:0]  snd_data, // data to be sent
            input  logic                     start,    // 1 to start the transfer
            input  logic                     MISO,     // SPI MISO
            input  logic                     clk,      // input clock
            input  logic                     rst,      // asynchronous reset, 1 to reset
            output logic                     ready,    // 1 when ready
            output logic                     SCLK,     // SPI SCLK
            output logic                     MOSI,     // SPI MOSI
            output logic                     SS,       // SPI SS
            output logic [DATA_WIDTH - 1:0]  rcv_data, // received data (from slave)
            output logic                     done);    // 1 when finished


enum logic[2:0]  {sIdle      = 3'b000,
                  sWait      = 3'b001,
                  sFirstEdge = 3'b010,
                  sActive    = 3'b011,
                  sLastEdge  = 3'b100,
                  sDone      = 3'b101,
                  XXX        = 'x    } state;

logic CPOL;
logic CPHA;
logic idle_SCLK;
logic snd_shift_en;
logic rcv_shift_en;
logic snd_edge;
logic rcv_edge;
logic cnt_en;
logic SCLK_en;
logic once_per_SCLK_cycle;
logic half_cycle_end;
logic transfer_end;
logic init;
logic active;

logic[$clog2(DATA_WIDTH):0]        SCLK_cycle_cnt;
logic[$clog2(CLK_PER_SCLK_EDGE):0] CLK_cycle_cnt;

logic[DATA_WIDTH - 1:0] snd_data_buffer;
logic[DATA_WIDTH - 1:0] rcv_data_buffer;

/* FSM
    sIdle: Idle state, if start == 1 transition to sWait.
    sWait: Wait for one clock cycle
    sFirstEdge: SS signal becomes 0, SCLK is enabled, after one clk cycle transition to sActive.
                If CPHA == 0, the first bit of the data need to be present in MOSI,
                before the first (leading) edge.
    sActive: This is the state that the data transfer takes place. After the transfer is done,
             transition to sLastEdge.
    sLastEdge: The FSM reaches this state when the transfer is effectively completed. Here, the
               FSM waits for the final half SCLK cycle of the SPI transfer, before transitioning to sDone.
    sDone: Signals the end of the operation, after a clk cycle the FSM transitions to sIdle.
*/

always_ff @(posedge clk, posedge rst) begin
    if(rst) begin
        SS <= '1;
        ready <= '1;
        init <= '1;
        SCLK_en <= '0;
        cnt_en <= '0;
        active <= '0;
        done <= '0;
                                    state <= sIdle;
    end
    else begin
        case(state)
            sIdle : begin
                if(start) begin
                    SS <= '1;
                    ready <= '0;
                    init <= '0;
                    SCLK_en <= '0;
                    cnt_en <= '0;
                    active <= '0;
                    done <= '0;
                                    state <= sWait;
                end
            end
            sWait : begin
                SS <= '0;
                ready <= '0;
                init <= '0;
                SCLK_en <= '1;
                cnt_en <= '1;
                active <= '0;
                done <= '0;
                                    state <= sFirstEdge;
            end
            sFirstEdge : begin
                if(half_cycle_end) begin
                    SS <= '0;
                    ready <= '0;
                    init <= '0;
                    SCLK_en <= '1;
                    cnt_en <= '1;
                    active <= '1;
                    done <= '0;
                                    state <= sActive;
                end
            end
            sActive : begin
                if(transfer_end) begin
                    SS <= '0;
                    ready <= '0;
                    init <= '0;
                    SCLK_en <= '0;
                    cnt_en <= '1;
                    active <= '0;
                    done <= '0;
                                    state <= sLastEdge;
                end
            end
            sLastEdge : begin
                if(half_cycle_end) begin
                    SS <= '1;
                    ready <= '0;
                    init <= '0;
                    SCLK_en <= '0;
                    cnt_en <= '0;
                    active <= '0;
                    done <= '1;
                                    state <= sDone;
                end
            end
            sDone : begin
                SS <= '1;
                ready <= '1;
                init <= '1;
                SCLK_en <= '0;
                cnt_en <= '0;
                active <= '0;
                done <= '0;
                                    state <= sIdle;
            end
        endcase
    end
end

assign CPOL = mode[1];
assign CPHA = mode[0];

assign idle_SCLK = CPOL;

assign half_cycle_end = CLK_cycle_cnt == CLK_PER_SCLK_EDGE - 1;
assign transfer_end = (SCLK_cycle_cnt == DATA_WIDTH) && half_cycle_end;

assign snd_shift_en = snd_edge && active && half_cycle_end;
// data may be received at the first edge (when CPHA == 0)
assign rcv_shift_en = rcv_edge && SCLK_en && half_cycle_end;

always_ff @(posedge clk) begin
    if(init) begin
        SCLK <= idle_SCLK;
        // when CPHA == 1 we send data at the first edge
        snd_edge <= CPHA;
        // when CPHA == 0 we receive data at the first edge
        rcv_edge <= ~CPHA;
        CLK_cycle_cnt <= '0;
        SCLK_cycle_cnt <= '0;
        once_per_SCLK_cycle <= '1;
        snd_data_buffer <= snd_data;
    end
    if(half_cycle_end) begin
        if(cnt_en) begin
            CLK_cycle_cnt <= '0;
            SCLK_cycle_cnt <= SCLK_cycle_cnt + once_per_SCLK_cycle;
            once_per_SCLK_cycle <= ~once_per_SCLK_cycle;
            snd_edge <= ~snd_edge;
            rcv_edge <= snd_edge;
        end
        // if enabled, toggle SCLK at the end of half cycle
        if(SCLK_en)
            SCLK <= ~SCLK;
    end
    else if(cnt_en)
        // if not the end of half cycle & counter is enabled
        // increment
        CLK_cycle_cnt <= CLK_cycle_cnt + 1'b1;
    // shift data out
    if(snd_shift_en)
        snd_data_buffer <= snd_data_buffer >> 1;
    // shift data in
    if(rcv_shift_en) begin
        rcv_data_buffer <= rcv_data >> 1;
        rcv_data_buffer[DATA_WIDTH - 1] <= MISO;
    end
end

assign MOSI = snd_data_buffer[0];
assign rcv_data = rcv_data_buffer;

endmodule
