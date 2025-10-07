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
        temp        : out integer range 0 to 80;

        scl         : out std_logic;
        sda         : inout std_logic;
        busy        : out std_logic
    );
end entity Tempreature;

architecture rtl of Tempreature is

component Temperature_I2C is
    generic (
        INPUT_CLK : integer := 10_000_000;  -- 系统时钟频率
        I2C_CLK   : integer := 400_000      -- I2C 时钟频率
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
        sda       : inout std_logic
    );
end component;

signal ena_i2c    : std_logic := '0';
signal busy_i2c   : std_logic := '0';
signal rw_i2c     : std_logic := '0';
signal data_wr_sig: std_logic_vector(7 downto 0) := (others => '0');
signal data_rd_i2c: std_logic_vector(7 downto 0);


signal msb_byte   : std_logic_vector(7 downto 0) := (others => '0');
signal lsb_byte   : std_logic_vector(7 downto 0) := (others => '0');

signal prev_ena   : std_logic := '0';
signal prev_busy  : std_logic := '0';

type seq_type is (S_IDLE, S_WAIT_WRITE_START, S_WAIT_WRITE_DONE,
                  S_WAIT_MSB_START, S_WAIT_MSB_DONE,
                  S_WAIT_LSB_START, S_WAIT_LSB_DONE,
                  S_UPDATE);
signal seq_state : seq_type := S_IDLE;

signal temp_twice : integer range 0 to 80 := 0; -- temp * 2 (定点表示)

begin

    busy <= busy_i2c;
    temp <= temp_twice;

    I2C_Master : Temperature_I2C
        generic map (
            INPUT_CLK => 10_000_000,
            I2C_CLK   => 400_000
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
            sda => sda
        );

    -- 序列：外部 ena 边沿触发 -> 写指针(0x00) -> 读 MSB -> 读 LSB -> 更新 temp_twice
    process(clk, rst)
        -- 在 process 的 declarative 部分声明变量（必须放这里）
        variable signed_msb : integer;
        variable half_bit   : integer;
        variable result     : integer;
    begin
        if rst = '1' then
            prev_ena <= '0';
            prev_busy <= '0';
            ena_i2c <= '0';
            rw_i2c <= '0';
            data_wr_sig <= (others => '0');
            msb_byte <= (others => '0');
            lsb_byte <= (others => '0');
            seq_state <= S_IDLE;
            temp_twice <= 0;
        elsif rising_edge(clk) then
            prev_ena <= ena;
            prev_busy <= busy_i2c;
            ena_i2c <= '0'; -- 默认单周期脉冲

            case seq_state is
                when S_IDLE =>
                    if (ena = '1' and prev_ena = '0') then
                        -- 发写指针事务，把内部指针指向 0x00
                        data_wr_sig <= x"00";
                        rw_i2c <= '0';         -- 写
                        ena_i2c <= '1';
                        seq_state <= S_WAIT_WRITE_START;
                    end if;

                when S_WAIT_WRITE_START =>
                    if (busy_i2c = '1' and prev_busy = '0') then
                        seq_state <= S_WAIT_WRITE_DONE;
                    end if;

                when S_WAIT_WRITE_DONE =>
                    if (busy_i2c = '0' and prev_busy = '1') then
                        -- 写指针完成，读 MSB
                        rw_i2c <= '1';
                        ena_i2c <= '1';
                        seq_state <= S_WAIT_MSB_START;
                    end if;

                when S_WAIT_MSB_START =>
                    if (busy_i2c = '1' and prev_busy = '0') then
                        seq_state <= S_WAIT_MSB_DONE;
                    end if;

                when S_WAIT_MSB_DONE =>
                    if (busy_i2c = '0' and prev_busy = '1') then
                        msb_byte <= data_rd_i2c;
                        -- 继续读 LSB（指针自动移到下一个寄存器）
                        rw_i2c <= '1';
                        ena_i2c <= '1';
                        seq_state <= S_WAIT_LSB_START;
                    end if;

                when S_WAIT_LSB_START =>
                    if (busy_i2c = '1' and prev_busy = '0') then
                        seq_state <= S_WAIT_LSB_DONE;
                    end if;

                when S_WAIT_LSB_DONE =>
                    if (busy_i2c = '0' and prev_busy = '1') then
                        lsb_byte <= data_rd_i2c;
                        seq_state <= S_UPDATE;
                    end if;

                when S_UPDATE =>
                    -- 使用上面声明的变量直接计算（不要在分支内再声明变量）
                    signed_msb := to_integer(signed(msb_byte));
                    if lsb_byte(7) = '1' then
                        half_bit := 1;
                    else
                        half_bit := 0;
                    end if;
                    result := signed_msb * 2 + half_bit;
                    if result < 0 then
                        result := 0;
                    elsif result > 80 then
                        result := 80;
                    end if;
                    temp_twice <= result;
                    seq_state <= S_IDLE;

            end case;
        end if;
    end process;

end architecture;

