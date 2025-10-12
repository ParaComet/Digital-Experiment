library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Button is
    port (
        clk_1khz     : in  std_logic;
        rst     : in  std_logic;
        btn0    : in  std_logic;
        btn2    : in  std_logic;
        key_flag: out integer range 0 to 2
    );
end entity Button;

architecture rtl of Button is

    -- debounce 
    constant DEBOUNCE_MS : integer := 20; -- 20 ms

    signal btn0_sync1, btn0_sync2 : std_logic := '0';
    signal btn2_sync1, btn2_sync2 : std_logic := '0';

    signal btn0_cnt : integer range 0 to 1000 := 0;
    signal btn2_cnt : integer range 0 to 1000 := 0;

    signal deb0, deb2       : std_logic := '0'; 
    signal prev_deb0, prev_deb2 : std_logic := '0';

    signal key_flag_reg : integer range 0 to 2 := 0;

begin

    sync_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                btn0_sync1 <= '0';
                btn0_sync2 <= '0';
                btn2_sync1 <= '0';
                btn2_sync2 <= '0';
            else
              
                btn0_sync1 <= btn0;     
                btn2_sync1 <= btn2;     

            
                btn0_sync2 <= btn0_sync1;
                btn2_sync2 <= btn2_sync1;
            end if;
        end if;
    end process sync_proc;


    debounce_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                btn0_cnt <= 0;
                btn2_cnt <= 0;
                deb0 <= '0';
                deb2 <= '0';
            else
                -- btn0
                if btn0_sync2 = deb0 then
                    btn0_cnt <= 0;
                else
                    if btn0_cnt < DEBOUNCE_MS then
                        btn0_cnt <= btn0_cnt + 1;
                    end if;
                    if btn0_cnt >= DEBOUNCE_MS then
                        deb0 <= btn0_sync2;
                        btn0_cnt <= 0;
                    end if;
                end if;

                -- btn2
                if btn2_sync2 = deb2 then
                    btn2_cnt <= 0;
                else
                    if btn2_cnt < DEBOUNCE_MS then
                        btn2_cnt <= btn2_cnt + 1;
                    end if;
                    if btn2_cnt >= DEBOUNCE_MS then
                        deb2 <= btn2_sync2;
                        btn2_cnt <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process debounce_proc;


    keyflag_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                prev_deb0 <= '0';
                prev_deb2 <= '0';
                key_flag_reg <= 0;
            else
                key_flag_reg <= 0;
                if (deb0 = '1' and prev_deb0 = '0') then
                    key_flag_reg <= 1;
                elsif (deb2 = '1' and prev_deb2 = '0') then
                    key_flag_reg <= 2;
                end if;

                prev_deb0 <= deb0;
                prev_deb2 <= deb2;
            end if;
        end if;
    end process keyflag_proc;

    key_flag <= key_flag_reg;

end architecture;

