library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Q2_lyf is
    port(
        clk,
        clk_100hz, 
        button,
        rst : in std_logic := '0';

        matrix_en,
        matrix_R,
        matrix_G : out std_logic_vector(7 downto 0)

    );
end Q2_lyf;

architecture behavioral of Q2_lyf is
    signal stage : integer range 0 to 4 := 0;

component LedMatrix is 
    port (
        clk : in std_logic;
        clk_100hz : in std_logic;
        rst : in std_logic;
        stage : in integer range 0 to 4;
        
        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R : out std_logic_vector(7 downto 0);
        matrix_G : out std_logic_vector(7 downto 0)
    );
end component;

begin
    led_matrix_inst : LedMatrix 
        port map(clk => clk, clk_100hz => clk_100hz, rst => rst, stage => stage, matrix_en => matrix_en, matrix_R => matrix_R, matrix_G => matrix_G);

    process(clk, rst)
    begin 
        if (rst = '1') then
            stage <= 0;
        elsif rising_edge(clk) then
            if (button = '1') then
                if (stage = 4) then
                    stage <= 0;
                else
                    stage <= stage + 1;
                end if;
            end if;
        end if;
    end process;

end behavioral;