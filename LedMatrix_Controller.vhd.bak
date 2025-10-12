library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix_Controller is
    port (
        clk_pwm     : in  std_logic;
        clk_1khz   : in  std_logic;
        rst         : in  std_logic;
    
        frame_data_Red   : in  std_logic_vector(63 downto 0);
        frame_data_Green : in  std_logic_vector(63 downto 0);

        pwm_level_R   : in integer range 0 to 15;
        pwm_level_G   : in integer range 0 to 15;

        Row_out : out std_logic_vector(7 downto 0);
        Col_out_Red   : out std_logic_vector(7 downto 0);
        Col_out_Green : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of LedMatrix_Controller is

constant PWM_COUNT_MAX : integer := 15;
signal pwm_counter : integer range 0 to PWM_COUNT_MAX := 0;

signal current_row_index : integer range 0 to 7 := 0;
signal current_row_data_R : std_logic_vector(7 downto 0) := (others => '0');
signal current_row_data_G : std_logic_vector(7 downto 0) := (others => '0');

signal pwm_row_data_R : std_logic_vector(7 downto 0) := (others => '0');
signal pwm_row_data_G : std_logic_vector(7 downto 0) := (others => '0');

begin

    process(clk_1khz, rst)
    begin
        if rst = '1' then
            current_row_index <= 0;
            current_row_data_R <= (others => '0');
            current_row_data_G <= (others => '0');
            Row_out <= (others => '1');
        elsif rising_edge(clk_1khz) then
            current_row_index <= (current_row_index + 1) mod 8;
            Row_out <= (others => '1');
            Row_out(current_row_index) <= '0';
            
            current_row_data_R <= frame_data_Red(current_row_index*8+7 downto current_row_index*8);
            current_row_data_G <= frame_data_Green(current_row_index*8+7 downto current_row_index*8);
        end if;
    
    end process;
    
    process(clk_pwm, rst)
    begin
        if rst = '1' then
            pwm_counter <= 0;
            pwm_row_data_R <= (others => '0');
            pwm_row_data_G <= (others => '0');
        elsif rising_edge(clk_pwm) then
            pwm_counter <= (pwm_counter + 1) mod PWM_COUNT_MAX;

            for i in 0 to 7 loop
                if current_row_data_R(i) = '1' and pwm_counter < pwm_level_R then
                    pwm_row_data_R(i) <= '1';
                else
                    pwm_row_data_R(i) <= '0';
                end if;
            end loop;

            for i in 0 to 7 loop
                if current_row_data_G(i) = '1' and pwm_counter < pwm_level_G then
                    pwm_row_data_G(i) <= '1';
                else
                    pwm_row_data_G(i) <= '0';
                end if;
             
            end loop;

        end if;
    end process;

    Col_out_Red   <=  pwm_row_data_R;
    Col_out_Green <=  pwm_row_data_G;

end architecture;
