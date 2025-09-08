library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Q2_lyf is
    port(
        clk, rst: in std_logic;
        led: out std_logic_vector(7 downto 0)
    );
end entity Q2_lyf;

architecture behavioral of Q2_lyf is
    signal led_signal: std_logic_vector(7 downto 0) := (others => '0'); -- 初始化为0
begin
    process(clk, rst)
    begin
        if(rst = '1') then
            led_signal <= (others => '0'); -- 复位时清零
        elsif(rising_edge(clk)) then
            -- 手动实现加法
            led_signal <= std_logic_vector(unsigned(led_signal) + 1);
        end if;
    end process;

    led <= led_signal; -- 直接输出
end architecture behavioral;


