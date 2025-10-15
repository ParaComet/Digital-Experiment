library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Clk_Generater is
    generic (
        INPUT_CLK : integer := 50_000_000  -- 主时钟（Hz）
    );
    port (
        clk       : in  std_logic;  -- 主时钟
        rst       : in  std_logic;  -- 异步复位，高有效
        clk_1khz  : out std_logic;  -- 1 kHz 时钟输出
        clk_100hz : out std_logic;  -- 100 Hz 时钟输出
        clk_1mhz  : out std_logic   -- 1 MHz 时钟输出
    );
end entity Clk_Generater;

architecture rtl of Clk_Generater is
    -- 半周期计数：从 INPUT_CLK 产生目标频率的方波
    constant HALF_TICKS_1K  : integer := INPUT_CLK / (2 * 1000);
    constant HALF_TICKS_100 : integer := INPUT_CLK / (2 * 100);
    constant HALF_TICKS_1M : integer := INPUT_CLK / (2 * 1_000_000);

    signal cnt1k  : integer := 0;
    signal cnt100 : integer := 0;
    signal cnt1m  : integer := 0;
    signal clk1k_r  : std_logic := '0';
    signal clk100_r : std_logic := '0';
    signal clk1m_r  : std_logic := '0';
begin

    clk_1mhz  <= clk1m_r;
    clk_1khz  <= clk1k_r;
    clk_100hz <= clk100_r;

    process(clk, rst)
    begin
        if rst = '1' then
            cnt1k     <= 0;
            cnt100    <= 0;
            clk1k_r   <= '0';
            clk100_r  <= '0';
        elsif rising_edge(clk) then
            -- 1 MHz 分频（切换产生方波）
            if cnt1m >= HALF_TICKS_1M - 1 then
                cnt1m <= 0;
                clk1m_r <= not clk1m_r;
            else
                cnt1m <= cnt1m + 1;
            end if;

            -- 1 kHz 分频（切换产生方波）
            if cnt1k >= HALF_TICKS_1K - 1 then
                cnt1k <= 0;
                clk1k_r <= not clk1k_r;
            else
                cnt1k <= cnt1k + 1;
            end if;

            -- 100 Hz 分频
            if cnt100 >= HALF_TICKS_100 - 1 then
                cnt100 <= 0;
                clk100_r <= not clk100_r;
            else
                cnt100 <= cnt100 + 1;
            end if;
        end if;
    end process;

end architecture rtl;