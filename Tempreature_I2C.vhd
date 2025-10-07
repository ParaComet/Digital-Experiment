library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Temperature_I2C is
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
    data_rd   : out std_logic_vector(7 downto 0); -- 读数据（每接收完一个字节更新）
    busy      : out std_logic;          -- 忙信号
    ack_error : out std_logic;          -- ACK 错误（保留）
    scl       : out std_logic;          -- I2C 时钟
    sda       : inout std_logic;        -- I2C 数据
    byte_valid: out std_logic           -- 每当接收完一个字节时单周期有效
  );
end entity;

architecture rtl of Temperature_I2C is

  constant HALF_TICKS : integer := INPUT_CLK / (2 * I2C_CLK);
  signal clk_cnt      : integer range 0 to HALF_TICKS := 0;
  signal scl_reg      : std_logic := '1';
  signal sda_reg      : std_logic := '1';
  signal sda_dir      : std_logic := '1'; -- 1: 输出, 0: 输入
  signal scl_enable   : std_logic := '0'; -- 使能 SCL 生成（事务期间有效）
  signal scl_rising   : std_logic := '0'; -- 在 SCL 下降沿那个时钟周期为 '1'
  signal scl_falling  : std_logic := '0'; -- 在 SCL 上升沿那个时钟周期为 '1'

  signal bit_cnt      : integer range 0 to 7 := 7;
  signal shifter      : std_logic_vector(7 downto 0) := (others => '0');

  type state_type is (IDLE, START, SEND_ADDR, ACK_SLAVE, SEND_DATA, ACK_AFTER_SEND,
                      RECV_DATA, RECV_ACK_MASTER, AFTER_NACK_LOW, STOP_WAIT, STOP_DONE);
  signal state        : state_type := IDLE;

  -- 用于多字节接收计数（接收 2 字节）
  signal recv_left    : integer range 0 to 2 := 0;
  signal byte_valid_r : std_logic := '0';

begin

  -- SCL 输出 & SDA 双向
  scl <= scl_reg;
  sda <= sda_reg when sda_dir = '1' else 'Z';

  byte_valid <= byte_valid_r;

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

  -- 状态机：支持一次读两个字节（主机在第一个字节后发 ACK，再读第二字节并 NACK）
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
      recv_left <= 0;
      byte_valid_r <= '0';
    elsif rising_edge(clk) then
      -- 默认短脉冲清零
      byte_valid_r <= '0';

      case state is
        when IDLE =>
          busy <= '0';
          scl_enable <= '0';
          if ena = '1' then
            -- 开始事务：准备写指针或读（上层用 addr 与 rw 决定）
            busy <= '1';
            ack_error <= '0';
            shifter <= addr & rw;
            sda_dir <= '1';
            sda_reg <= '1';
            bit_cnt <= 7;
            scl_enable <= '0';
            state <= START;
          end if;

        when START =>
          -- 产生 START：SDA 在 SCL 为高时下降
          sda_reg <= '0';
          sda_dir <= '1';
          -- 开始产生时钟
          scl_enable <= '1';
          state <= SEND_ADDR;

        when SEND_ADDR =>
          -- 在 SCL 下降沿驱动下一位数据
          if scl_falling = '1' then
            sda_reg <= shifter(bit_cnt);
            sda_dir <= '1';
          end if;
          -- 在 SCL 上升沿移动位计数或转到 ACK 采样
          if scl_rising = '1' then
            if bit_cnt = 0 then
              bit_cnt <= 7;
              sda_dir <= '0'; -- 释放 SDA 以等待 ACK（从机 ACK）
              state <= ACK_SLAVE;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when ACK_SLAVE =>
          -- 在 SCL 上升沿采样从机 ACK（addr 或写字节的 ACK）
          if scl_rising = '1' then
            if sda = '1' then
              ack_error <= '1';
            else
              ack_error <= '0';
            end if;
            -- 如果是写操作且还有要写的数据，则进入 SEND_DATA
            if rw = '0' then
              shifter <= data_wr;
              sda_dir <= '1';
              bit_cnt <= 7;
              state <= SEND_DATA;
            else
              -- 读操作：准备接收多个字节（设置为接收 2 字节）
              recv_left <= 2;
              sda_dir <= '0'; -- 释放 SDA
              bit_cnt <= 7;
              state <= RECV_DATA;
            end if;
          end if;

        when SEND_DATA =>
          -- 写数据给从机（如果需要）
          if scl_falling = '1' then
            sda_reg <= shifter(bit_cnt);
            sda_dir <= '1';
          end if;
          if scl_rising = '1' then
            if bit_cnt = 0 then
              bit_cnt <= 7;
              sda_dir <= '0';
              state <= ACK_AFTER_SEND;
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when ACK_AFTER_SEND =>
          -- 采样从机对写数据的 ACK
          if scl_rising = '1' then
            if sda = '1' then
              ack_error <= '1';
            else
              ack_error <= '0';
            end if;
            -- 写完后直接 STOP
            sda_dir <= '1';
            sda_reg <= '1';
            scl_enable <= '0';
            state <= STOP_WAIT;
          end if;

        when RECV_DATA =>
          -- 接收字节：在 SCL 上升沿采样数据位（MSB -> LSB）
          sda_dir <= '0'; -- 保持输入
          if scl_rising = '1' then
            -- 逐位写入 shifter
            shifter(bit_cnt) <= sda;
            if bit_cnt = 0 then
              -- 一个字节接收完毕，输出并通知上层
              data_rd <= shifter;
              byte_valid_r <= '1'; -- 单周期有效，上层可在下个时钟采样
              state <= RECV_ACK_MASTER; -- 主机驱动 ACK/NACK
            else
              bit_cnt <= bit_cnt - 1;
            end if;
          end if;

        when RECV_ACK_MASTER =>
          -- 在 SCL 下降沿设置 ACK/NACK
          if scl_falling = '1' then
            if recv_left > 1 then
              sda_dir <= '1';
              sda_reg <= '0'; -- ACK (拉低)
            else
              sda_dir <= '1';
              sda_reg <= '1'; -- NACK (驱高/释放，以便从机在随后的 SCL 高期采样到 NACK)
            end if;
          end if;

          -- 在 SCL 上升沿决定后续动作
          if scl_rising = '1' then
            if recv_left > 1 then
              -- 还有数据要收：准备接收下一个字节
              recv_left <= recv_left - 1;
              sda_dir <= '0';
              bit_cnt <= 7;
              state <= RECV_DATA;
            else
              -- NACK 已被发送并在该 SCL 高期被从机采样
              -- 接下来为保证产生规范 STOP，需要：
              -- 1) 在下一个 SCL 低期主动把 SDA 拉低（确保 STOP 前 SDA 为低）
              -- 2) 再等待 SCL 回到高，并在其高期把 SDA 设高以产生 0->1 的 STOP 边沿
              state <= AFTER_NACK_LOW;
            end if;
          end if;

        when AFTER_NACK_LOW =>
          -- 在 SCL 的低期把 SDA 拉低（在 scl_falling 时刻可以安全操作）
          if scl_falling = '1' then
            sda_dir <= '1';
            sda_reg <= '0'; -- 拉低，准备产生 STOP 时的上升沿
            -- 保持 SCL 继续切换，等待上升到高
            state <= STOP_WAIT;
          end if;

        when STOP_WAIT =>
          -- 等待 SCL 回到高，在 SCL 高期把 SDA 设为高以产生 STOP（0->1 while SCL=1）
          if scl_reg = '1' then
            sda_dir <= '1';
            sda_reg <= '1'; -- 在 SCL 高期产生上升沿 -> STOP
            -- 结束事务
            state <= STOP_DONE;
          end if;

        when STOP_DONE =>
          busy <= '0';
          state <= IDLE;

      end case;
    end if;
  end process sm;

end rtl;
