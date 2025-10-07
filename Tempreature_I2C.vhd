library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_master is
  generic (
    INPUT_CLK : integer := 1_000_000;  -- FPGA 主时钟 (Hz)
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

  -- 新增：基于半周期计数产生 SCL，并产生上升/下降沿脉冲
  constant HALF_TICKS : integer := INPUT_CLK / (2 * I2C_CLK);
  signal clk_cnt      : integer range 0 to HALF_TICKS := 0;
  signal scl_reg      : std_logic := '1';
  signal sda_reg      : std_logic := '1';
  signal sda_dir      : std_logic := '1'; -- 1: 输出, 0: 输入
  signal scl_enable   : std_logic := '0'; -- 使能 SCL 生成（事务期间有效）
  signal scl_rising   : std_logic := '0'; -- 在 SCL 上升沿那个时钟周期为 '1'
  signal scl_falling  : std_logic := '0'; -- 在 SCL 下降沿那个时钟周期为 '1'

  signal bit_cnt      : integer range 0 to 7 := 7;
  signal shifter      : std_logic_vector(7 downto 0);

  type state_type is (IDLE, START, SEND_ADDR, ACK, SEND_DATA, RECV_DATA, STOP);
  signal state        : state_type := IDLE;
begin

  -- SCL 输出 & SDA 双向保持不变
  scl <= scl_reg;
  sda <= sda_reg when sda_dir = '1' else 'Z';

  -- SCL 分频与边沿脉冲生成（独立进程）
  scl_gen: process(clk, rst)
  begin
    if rst = '1' then
      clk_cnt    <= 0;
      scl_reg    <= '1';
      scl_rising <= '0';
      scl_falling<= '0';
    elsif rising_edge(clk) then
      scl_rising  <= '0';
      scl_falling <= '0';
      if scl_enable = '1' then
        if clk_cnt >= HALF_TICKS - 1 then
          clk_cnt <= 0;
          scl_reg <= not scl_reg;
          if scl_reg = '0' then
            -- 即将变为 '1'，产生上升沿脉冲
            scl_rising <= '1';
          else
            -- 即将变为 '0'，产生下降沿脉冲
            scl_falling <= '1';
          end if;
        else
          clk_cnt <= clk_cnt + 1;
        end if;
      else
        clk_cnt <= 0;
        scl_reg <= '1';
      end if;
    end if;
  end process scl_gen;

  -- 状态机：在 SCL 下降沿更新 SDA（驱出下一位），在 SCL 上升沿采样/移动位计数
  sm: process(clk, rst)
  begin
    if rst = '1' then
      state     <= IDLE;
      busy      <= '0';
      ack_error <= '0';
      data_rd   <= (others => '0');
      sda_dir   <= '1';
      sda_reg   <= '1';
      scl_enable<= '0';
      bit_cnt   <= 7;
    elsif rising_edge(clk) then
      -- 默认清忙标志（在 IDLE 恢复）
      case state is
        when IDLE =>
          busy <= '0';
          scl_enable <= '0';
          if ena = '1' then
            busy <= '1';
            ack_error <= '0';
            shifter <= addr & rw;
            sda_dir <= '1';
            sda_reg <= '1';
            bit_cnt <= 7;
            -- 准备 START：确保 SCL 高，然后拉低 SDA（在下一周期开始 SCL 产生）
            scl_enable <= '0';
            sda_reg <= '1';
            state <= START;
          end if;

        when START =>
          -- 强制 SCL 高（scl_enable 已为 '0'），然后拉低 SDA 一周期以产生 START
          sda_reg <= '0';
          sda_dir <= '1';
          -- 开始产生时钟
          scl_enable <= '1';
          clk_cnt <= 0;
          state <= SEND_ADDR;

        when SEND_ADDR =>
          -- 在 SCL 下降沿驱动下一位数据
          if scl_falling = '1' then
            sda_reg <= shifter(bit_cnt);
            sda_dir <= '1';
          end if;
          -- 在 SCL 上升沿移动位计数或转到 ACK
          if scl_rising = '1' then
            if bit_cnt = 0 then
              bit_cnt <= 7;
              sda_dir <= '0'; -- 释放 SDA 以等待 ACK
              state <= ACK;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when ACK =>
          -- 在 SCL 上升沿采样 ACK（sda 为从机拉低表示 ACK）
          if scl_rising = '1' then
            if sda = '1' then
              ack_error <= '1';
            else
              ack_error <= '0';
            end if;
            -- 根据 rw 决定后续
            if rw = '0' then
              shifter <= data_wr;
              sda_dir <= '1';
              bit_cnt <= 7;
              state <= SEND_DATA;
            else
              sda_dir <= '0';
              bit_cnt <= 7;
              state <= RECV_DATA;
            end if;
          end if;

        when SEND_DATA =>
          if scl_falling = '1' then
            sda_reg <= shifter(bit_cnt);
            sda_dir <= '1';
          end if;
          if scl_rising = '1' then
            if bit_cnt = 0 then
              bit_cnt <= 7;
              sda_dir <= '1';
              state <= STOP;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when RECV_DATA =>
          sda_dir <= '0'; -- 保持输入
          if scl_rising = '1' then
            data_rd(bit_cnt) <= sda;
            if bit_cnt = 0 then
              bit_cnt <= 7;
              state <= STOP;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when STOP =>
          -- 确保 SCL 高后释放 SDA（产生 STOP）
          sda_dir <= '1';
          sda_reg <= '1';
          scl_enable <= '0';
          state <= IDLE;
          busy <= '0';

      end case;
    end if;
  end process sm;

end rtl;
