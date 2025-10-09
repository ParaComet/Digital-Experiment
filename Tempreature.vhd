library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Tempreature is
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        ena         : in  std_logic;
        button      : in  std_logic;

        -- 定点输出：temp = 温度 * 2，LSB = 0.5°C，范围 0..80 对应 0.0..40.0°C
        temp        : out integer range 0 to 63;
        temp_dot     : out std_logic;  -- 温度是否有小数点（0.5°C）

        scl         : out std_logic;
        sda         : inout std_logic;
        busy        : out std_logic
    );
end entity Tempreature;

architecture rtl of Tempreature is

component Temperature_I2C is
    generic (
        INPUT_CLK : integer := 1_000_000;  -- 系统时钟频率
        I2C_CLK   : integer := 100_000      -- I2C 时钟频率
    );
    port (
        clk       : in  std_logic;          
        rst       : in  std_logic;          
        ena       : in  std_logic;          
        addr      : in  std_logic_vector(6 downto 0);
        rw        : in  std_logic;          -- 0=写, 1=读
        data_wr   : in  std_logic_vector(7 downto 0);
        data_rd   : out std_logic_vector(7 downto 0);
        busy      : out std_logic;
        ack_error : out std_logic;
        scl       : out std_logic;
        sda       : inout std_logic;
        byte_valid: out std_logic
    );
end component;

-- 模块控制信号
signal busy_temp  : std_logic := '0';
signal prev_ena   : std_logic := '0';
signal prev_busy  : std_logic := '0';

-- I2C 信号
signal ena_i2c    : std_logic := '0';
signal busy_i2c   : std_logic := '0';
signal rw_i2c     : std_logic := '0';
signal data_wr_sig: std_logic_vector(7 downto 0) := (others => '0');
signal data_rd_i2c: std_logic_vector(7 downto 0);
signal byte_valid_i2c : std_logic := '0';
signal prev_byte_valid : std_logic := '0';

signal msb_byte   : std_logic_vector(7 downto 0) := (others => '0');
signal lsb_byte   : std_logic_vector(7 downto 0) := (others => '0');
signal bytes_received : integer range 0 to 2 := 0;

-- 状态机
type seq_type is (S_IDLE, S_WAIT_WRITE_START, S_WAIT_WRITE_DONE,
                  S_WAIT_READ_START, S_WAIT_BYTES, S_CALC_TEMP);
signal seq_state : seq_type := S_IDLE;


begin

    busy <= busy_temp;

    I2C_Master : Temperature_I2C
        generic map (
            INPUT_CLK => 1_000_000,
            I2C_CLK   => 100_000
        )
        port map(
            clk => clk,
            rst => rst,
            ena => ena_i2c,
            addr => "1001000",  -- DS1775 默认地址
            rw => rw_i2c,
            data_wr => data_wr_sig,
            data_rd => data_rd_i2c,
            busy => busy_i2c,
            ack_error => open,
            scl => scl,
            sda => sda,
            byte_valid => byte_valid_i2c
        );

    -- 序列：外部 ena 边沿触发 -> 写指针(0x00) -> 一次读取两个字节 -> 更新 temp_twice
    process(clk, rst)
        variable signed_msb : integer range -128 to 127;
        variable half_bit   : std_logic;
  
    begin
        if rst = '1' then
            prev_ena <= '0';
            prev_busy <= '0';
            prev_byte_valid <= '0';
            ena_i2c <= '0';
            rw_i2c <= '0';
            data_wr_sig <= (others => '0');
            msb_byte <= (others => '0');
            lsb_byte <= (others => '0');
            seq_state <= S_IDLE;
            busy_temp <= '0';
            bytes_received <= 0;
        elsif rising_edge(clk) then
            prev_ena <= ena;
            prev_busy <= busy_i2c;

            case seq_state is
                when S_IDLE =>
                    if (ena = '1' and prev_ena = '0') then
                        -- 发写指针事务，把内部指针指向 0x00
                        data_wr_sig <= x"00";
                        rw_i2c <= '0';         -- 写
                        ena_i2c <= '1';
                        busy_temp <= '1';
                        
                        seq_state <= S_WAIT_WRITE_START;
                    end if;

                when S_WAIT_WRITE_START =>
                    if (busy_i2c = '1' and prev_busy = '0') then
                        ena_i2c <= '0'; -- 默认单周期脉冲
                        seq_state <= S_WAIT_WRITE_DONE;
                    end if;

                when S_WAIT_WRITE_DONE =>
                    if (busy_i2c = '0' and prev_busy = '1') then
                        -- 写指针完成，发一次读事务，请求连续读取两个字节
                        rw_i2c <= '1';
                        ena_i2c <= '1';
                        bytes_received <= 0;
                        seq_state <= S_WAIT_READ_START;
                    end if;

                when S_WAIT_READ_START =>
                    -- 等待事务开始（busy 上升）
                    if (busy_i2c = '1' and prev_busy = '0') then
                        -- 事务刚开始：清除旧缓存，准备接收字节
                        ena_i2c <= '0'; -- 使能位清零为下次准备
                        bytes_received <= 0;
                        msb_byte <= (others => '0');
                        lsb_byte <= (others => '0');
                        seq_state <= S_WAIT_BYTES;
                    end if;
                
                when S_WAIT_BYTES =>
                    -- 捕获每个字节到 msb/lsb（使用上升沿检测）
                    if (byte_valid_i2c = '1' and prev_byte_valid = '0') then
                        if bytes_received = 0 then
                            msb_byte <= data_rd_i2c;
                            bytes_received <= 1;
                        elsif bytes_received = 1 then
                            lsb_byte <= data_rd_i2c;
                            bytes_received <= 2;
                        end if;
                    end if;
                    if (busy_i2c = '0' and prev_busy = '1') then
                        -- 事务结束，进入计算状态
                        seq_state <= S_CALC_TEMP;
                    end if;

                when S_CALC_TEMP =>
                    -- 等待事务结束（busy 回到 0），此时已接收完字节

                        -- 事务结束，若已经收到两个字节则更新 temp_twice
                    if bytes_received >= 2 then
                        -- 解析 MSB/LSB -> temp_twice
                        signed_msb := to_integer(signed(msb_byte));
                        if lsb_byte(7) = '1' then
                            half_bit := '1';
                        else
                            half_bit := '0';
                        end if;
                        if signed_msb < 0 then
                            signed_msb := 0;
                        elsif signed_msb > 63 then
                            signed_msb := 63;
                        end if;
                            
                    end if;
                    temp_dot <= half_bit;
                    temp <= signed_msb;
                    seq_state <= S_IDLE;
                    busy_temp <= '0';
            
            end case;

            -- 在进程结尾同步 prev_byte_valid 以供下一周期检测
            prev_byte_valid <= byte_valid_i2c;
        end if;
    end process;

end architecture;

