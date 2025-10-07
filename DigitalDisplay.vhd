library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DigitalDisplay is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        temp1        : in  integer range 0 to 9;
        temp0        : in  integer range 0 to 9;
        tempdot      : in  integer range 0 to 1;  -- 小数后一位
        stage        : in  integer range 0 to 4;  -- 显示模式

        en_out       : out std_logic_vector(7 downto 0);
        deg_out      : out std_logic_vector(7 downto 0)
    );
end entity DigitalDisplay;

architecture rtl of DigitalDisplay is 

    signal en_index : integer range 0 to 7 := 0;
    signal deg_index : integer range 0 to 11 := 0;
    
begin

    process(clk, rst)
    begin
        if rst = '1' then
            en_index <= 0;
        elsif rising_edge(clk) then
            en_index <= (en_index + 1) mod 8;
        end if;
        en_out <= (others => '1');
        en_out(en_index) <= '0';
    end process;

    process(en_index, temp1, temp0, tempdot)
    begin 
        case en_index is
            when 0 => deg_index <= temp1;
            when 1 => deg_index <= temp0;
            when 2 => 
                if tempdot = 1 then
                    deg_index <= 5;
                else
                    deg_index <= 0;
                end if;
            when 3 => deg_index <= 10;  -- C
            when 4 => deg_index <= 11;  -- °
            when 5 => deg_index <= 0;  -- °
            when 7 => deg_index <= stage;
            when others => deg_index <= 0;
        end case;
    end process;

    with deg_index select
        deg_out <= "00111111" when 0,  -- 0
                   "00000110" when 1,  -- 1
                   "01011011" when 2,  -- 2
                   "01001111" when 3,  -- 3
                   "01100110" when 4,  -- 4
                   "01101101" when 5,  -- 5
                   "01111101" when 6,  -- 6
                   "00000111" when 7,  -- 7
                   "01111111" when 8,  -- 8
                   "01101111" when 9,  -- 9
                   "01110111" when 10, -- C
                   "00111001" when 11, -- °
                   "00000000" when others; -- 空白
    
end architecture rtl;