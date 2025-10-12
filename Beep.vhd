library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Beep is
    port (
        clk     : in  std_logic;         
        rst     : in  std_logic;         
        beep_en : in  std_logic;         
        stage   : in  integer range 0 to 4; 
        beep    : out std_logic          
    );
end entity Beep;

architecture rtl of Beep is

    constant FREQ_300 : integer := 50_000_000 / (300 * 2);   
    constant FREQ_500 : integer := 50_000_000 / (500 * 2);   
    constant FREQ_700 : integer := 50_000_000 / (700 * 2);  
    constant FREQ_1000: integer := 50_000_000 / (1000 * 2); 

    signal cnt      : integer := 0;
    signal cnt_max  : integer := FREQ_300;  
    signal beep_reg : std_logic := '0';

begin

    
    process(stage)
    begin
        case stage is
            when 0 => cnt_max <= 0;          -- 静音
            when 1 => cnt_max <= FREQ_300;   -- 300 Hz
            when 2 => cnt_max <= FREQ_500;   -- 500 Hz
            when 3 => cnt_max <= FREQ_700;   -- 700 Hz
            when 4 => cnt_max <= FREQ_1000;  -- 1000 Hz
            when others => cnt_max <= 0;
        end case;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            cnt <= 0;
            beep_reg <= '0';
        elsif rising_edge(clk) then
            if (beep_en = '1') and (stage /= 0) then
                if cnt = cnt_max-1 then
                    cnt <= 0;
                    beep_reg <= not beep_reg; 
                else
                    cnt <= cnt + 1;
                end if;
            else
                cnt <= 0;
                beep_reg <= '0'; 
            end if;
        end if;
    end process;

    beep <= beep_reg;

end architecture rtl;



