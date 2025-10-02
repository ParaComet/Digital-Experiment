library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
  generic (
    INPUT_CLK : integer := 50_000_000;  -- FPGA 主时钟 (Hz)
    I2C_CLK   : integer := 100_000      -- I2C 总线速率 (Hz, DS1775 可到 400kHz)
  );
  port (
    clk       : in  std_logic;          -- FPGA 时钟
    rst       : in  std_logic;          -- 异步复位，高有效
    ena       : in  std_logic;          -- 开始一次事务
    addr      : in  std_logic_vector(6 downto 0); -- 7 位从机地址
    rw        : in  std_logic;          -- 读/写 (0=写, 1=读)
    data_wr   : in  std_logic_vector(7 downto 0); -- 写数据
    data_rd   : out std_logic_vector(7 downto 0); -- 读数据
    busy      : out std_logic;          -- 忙信号
    ack_error : out std_logic;          -- ACK 错误
    scl       : out std_logic;          -- I2C 时钟
    sda       : inout std_logic         -- I2C 数据
  );
end entity;

architecture rtl of i2c_master is

  type state_type is (IDLE, START, SEND_ADDR, SEND_DATA, RECV_DATA, ACK, STOP);
  signal state    : state_type := IDLE;
  signal clk_cnt  : integer range 0 to INPUT_CLK/I2C_CLK := 0;
  signal scl_reg  : std_logic := '1';
  signal sda_reg  : std_logic := '1';
  signal sda_dir  : std_logic := '1'; -- 1:输出, 0:输入
  signal bit_cnt  : integer range 0 to 7 := 7;
  signal shifter  : std_logic_vector(7 downto 0);

begin

  -- SCL 输出
  scl <= scl_reg;

  -- SDA 双向控制
  sda <= sda_reg when sda_dir = '1' else 'Z';

  -- 状态机
  process(clk, rst)
  begin
    if rst = '1' then
      state    <= IDLE;
      scl_reg  <= '1';
      sda_reg  <= '1';
      sda_dir  <= '1';
      clk_cnt  <= 0;
      bit_cnt  <= 7;
      busy     <= '0';
      ack_error <= '0';
      data_rd  <= (others => '0');

    elsif rising_edge(clk) then

      case state is
        when IDLE =>
          busy <= '0';
          if ena = '1' then
            busy <= '1';
            shifter <= addr & rw;
            state <= START;
          end if;

        when START =>
          -- 产生 START 条件 (SDA下降，SCL保持高)
          sda_reg <= '0';
          sda_dir <= '1';
          state <= SEND_ADDR;

        when SEND_ADDR =>
          scl_reg <= '0'; -- 拉低 SCL，准备发送
          sda_reg <= shifter(bit_cnt);
          if clk_cnt = INPUT_CLK/I2C_CLK/2 then
            scl_reg <= '1'; -- 拉高 SCL，采样 SDA
            if bit_cnt = 0 then
              bit_cnt <= 7;
              state <= ACK;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
            clk_cnt <= 0;
          else
            clk_cnt <= clk_cnt + 1;
          end if;

        when ACK =>
          scl_reg <= '0';
          sda_dir <= '0'; -- 切换 SDA 为输入，检测 ACK
          if scl_reg = '1' then
            if sda = '1' then
              ack_error <= '1'; -- 没有收到 ACK
            end if;
            -- 根据 rw 进入下一个状态
            if rw = '0' then
              shifter <= data_wr;
              state <= SEND_DATA;
            else
              state <= RECV_DATA;
            end if;
            sda_dir <= '1';
          end if;

        when SEND_DATA =>
          scl_reg <= '0';
          sda_reg <= shifter(bit_cnt);
          if clk_cnt = INPUT_CLK/I2C_CLK/2 then
            scl_reg <= '1';
            if bit_cnt = 0 then
              bit_cnt <= 7;
              state <= STOP;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
            clk_cnt <= 0;
          else
            clk_cnt <= clk_cnt + 1;
          end if;

        when RECV_DATA =>
          scl_reg <= '0';
          sda_dir <= '0'; -- 输入模式
          if clk_cnt = INPUT_CLK/I2C_CLK/2 then
            scl_reg <= '1';
            data_rd(bit_cnt) <= sda;
            if bit_cnt = 0 then
              bit_cnt <= 7;
              state <= STOP;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
            clk_cnt <= 0;
          else
            clk_cnt <= clk_cnt + 1;
          end if;

        when STOP =>
          scl_reg <= '1';
          sda_reg <= '1'; -- SDA 拉高
          state <= IDLE;

      end case;
    end if;
  end process;

end rtl;
