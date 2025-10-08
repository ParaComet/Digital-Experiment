library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Temperature_I2C is
  generic (
    INPUT_CLK : integer := 1_000_000;  -- FPGA 主时钟 (Hz)
    I2C_CLK   : integer := 100_000     -- I2C 总线速率 (Hz)
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    ena       : in  std_logic;
    addr      : in  std_logic_vector(6 downto 0);
    rw        : in  std_logic;               -- 0=write, 1=read
    data_wr   : in  std_logic_vector(7 downto 0);
    data_rd   : out std_logic_vector(7 downto 0);
    busy      : out std_logic;
    ack_error : out std_logic;
    scl       : out std_logic;
    sda       : inout std_logic;
    byte_valid: out std_logic
  );
end entity;

architecture rtl of Temperature_I2C is

  constant HALF_TICKS : integer := INPUT_CLK / (2 * I2C_CLK);

  signal scl_reg    : std_logic := '1';
  signal sda_reg    : std_logic := '1';
  signal sda_dir    : std_logic := '1'; -- 1: drive, 0: release
  signal scl_enable : std_logic := '0';

  signal data_rd_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal busy_r     : std_logic := '0';
  signal ack_err_r  : std_logic := '0';
  signal byte_valid_r : std_logic := '0';

  type state_type is (
    IDLE, START, SEND_ADDR, ACK_SLAVE, SEND_DATA, ACK_AFTER_SEND,
    RECV_DATA, RECV_ACK_MASTER, AFTER_NACK_LOW, STOP_WAIT
  );
  signal state     : state_type := IDLE;

  signal recv_left : integer range 0 to 2 := 0;

begin

  scl <= scl_reg;
  sda <= sda_reg when sda_dir = '1' else 'Z';
  data_rd <= data_rd_r;
  busy    <= busy_r;
  ack_error <= ack_err_r;
  byte_valid <= byte_valid_r;

  -- 合并分频与状态机：在同一进程内用变量即时判断边沿，使用变量 shifter_v 收集位
  combined_proc: process(clk, rst)
    variable clk_cnt_v  : integer := 0;
    variable scl_v      : std_logic := '1';
    variable scl_prev_v : std_logic := '1';
    variable rising_ev  : boolean := false;
    variable falling_ev : boolean := false;
    variable bit_cnt_v  : integer := 7;
    variable shifter_v  : std_logic_vector(7 downto 0) := (others => '0');
  begin
    if rst = '1' then
      clk_cnt_v := 0;
      scl_v := '1';
      scl_prev_v := '1';
      rising_ev := false;
      falling_ev := false;

      scl_reg <= '1';
      sda_reg <= '1';
      sda_dir <= '1';
      scl_enable <= '0';

      busy_r <= '0';
      ack_err_r <= '0';
      data_rd_r <= (others => '0');
      byte_valid_r <= '0';
      recv_left <= 0;

      state <= IDLE;
      bit_cnt_v := 7;
      shifter_v := (others => '0');
    elsif rising_edge(clk) then
      -- SCL 分频逻辑（变量）
      if scl_enable = '1' then
        if clk_cnt_v >= HALF_TICKS - 1 then
          clk_cnt_v := 0;
          scl_v := not scl_v;
        else
          clk_cnt_v := clk_cnt_v + 1;
        end if;
      else
        clk_cnt_v := 0;
        scl_v := '1';
      end if;

      -- 边沿检测（立即可用）
      rising_ev  := (scl_prev_v = '0' and scl_v = '1');
      falling_ev := (scl_prev_v = '1' and scl_v = '0');

      -- 更新对外 SCL
      scl_reg <= scl_v;
      scl_prev_v := scl_v;

      -- 默认清短脉冲
      byte_valid_r <= '0';

      -- 状态机（使用变量 shifter_v/bit_cnt_v）
      case state is
        when IDLE =>
          busy_r <= '0';
          scl_enable <= '0';
          if ena = '1' then
            busy_r <= '1';
            ack_err_r <= '0';
            -- prepare address+rw (MSB first)
            shifter_v := addr & rw;
            bit_cnt_v := 7;
            sda_dir <= '1';
            sda_reg <= '1';
            state <= START;
          end if;

        when START =>
          -- SDA 在 SCL = 1 时下降
          sda_reg <= '0';
          sda_dir <= '1';
          scl_enable <= '1';
          -- 初始化 bit counters for address send
          bit_cnt_v := 7;
          -- transfer to next
          state <= SEND_ADDR;

        when SEND_ADDR =>
          if falling_ev then
            sda_reg <= shifter_v(bit_cnt_v);
            sda_dir <= '1';
          end if;
          if rising_ev then
            if bit_cnt_v = 0 then
              bit_cnt_v := 7;
              sda_dir <= '0'; -- release for ACK
              state <= ACK_SLAVE;
            else
              bit_cnt_v := bit_cnt_v - 1;
            end if;
          end if;

        when ACK_SLAVE =>
          if rising_ev then
            if sda = '1' then
              ack_err_r <= '1';
            else
              ack_err_r <= '0';
            end if;
            if rw = '0' then
              -- write data byte
              shifter_v := data_wr;
              bit_cnt_v := 7;
              sda_dir <= '1';
              state <= SEND_DATA;
            else
              -- read: prepare to receive N bytes
              recv_left <= 2;
              sda_dir <= '0';
              bit_cnt_v := 7;
              state <= RECV_DATA;
            end if;
          end if;

        when SEND_DATA =>
          if falling_ev then
            sda_reg <= shifter_v(bit_cnt_v);
            sda_dir <= '1';
          end if;
          if rising_ev then
            if bit_cnt_v = 0 then
              bit_cnt_v := 7;
              sda_dir <= '0';
              state <= ACK_AFTER_SEND;
            else
              bit_cnt_v := bit_cnt_v - 1;
            end if;
          end if;

        when ACK_AFTER_SEND =>
          if rising_ev then
            if sda = '1' then
              ack_err_r <= '1';
            else
              ack_err_r <= '0';
            end if;
            -- request stop sequence
            sda_dir <= '1';
            sda_reg <= '1';
            scl_enable <= '0';
            state <= STOP_WAIT;
          end if;

        when RECV_DATA =>
          sda_dir <= '0';
          if rising_ev then
            -- 立即把采到的位写入变量 shifter_v
            shifter_v(bit_cnt_v) := sda;
            if bit_cnt_v = 0 then
              -- 完整字节到达：将变量写回输出寄存器，并产生 byte_valid 脉冲
              data_rd_r <= shifter_v;
              byte_valid_r <= '1';
              bit_cnt_v := 7;
              state <= RECV_ACK_MASTER;
            else
              bit_cnt_v := bit_cnt_v - 1;
            end if;
          end if;

        when RECV_ACK_MASTER =>
          if falling_ev then
            if recv_left > 1 then
              sda_dir <= '1';
              sda_reg <= '0'; -- ACK (pull low)
            else
              sda_dir <= '1';
              sda_reg <= '1'; -- NACK (drive high / release)
            end if;
          end if;

          if rising_ev then
            if recv_left > 1 then
              recv_left <= recv_left - 1;
              sda_dir <= '0';
              bit_cnt_v := 7;
              state <= RECV_DATA;
            else
              -- NACK 已被从机采样，进入 STOP 生成序列
              state <= AFTER_NACK_LOW;
            end if;
          end if;

        when AFTER_NACK_LOW =>
          if falling_ev then
            sda_dir <= '1';
            sda_reg <= '0'; -- pull low to prepare STOP rising edge
            state <= STOP_WAIT;
          end if;

        when STOP_WAIT =>
          if scl_v = '1' then
            sda_dir <= '1';
            sda_reg <= '1'; -- STOP: SDA rises while SCL high
            busy_r <= '0';
            state <= IDLE;
          end if;

        when others =>
          state <= IDLE;
      end case;
    end if;
  end process combined_proc;

end rtl;