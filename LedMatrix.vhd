library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix is 
    port (
        clk : in std_logic;
        clk_1khz : in std_logic;
        clk_100hz : in std_logic;
        rst : in std_logic;

        stage : in integer range 0 to 8;
        level : in integer range 0 to 4;
        release_i : in std_logic;  
 
        
        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R : out std_logic_vector(7 downto 0);
        matrix_G : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of LedMatrix is

    type Frequency is array (0 to 3) of integer range 0 to 63;

    constant ANIMATION_UPDATE_FREQ : Frequency := (48, 32, 16, 8);  -- 100Hz


    signal clk_div : std_logic;
    signal clkcount : integer range 0 to 60;

    signal Data_red : std_logic_vector(63 downto 0);
    signal Data_green : std_logic_vector(63 downto 0);

    signal pwmlevelR : integer range 0 to 15;
    signal pwmlevelG : integer range 0 to 15;
    

    signal release_speed_stage : integer range 0 to 3 := 0;

    signal stage_hold : integer range 0 to 8 := 0;
    signal pre_release_i : std_logic := '0';
    signal release_tick_cnt : integer range 0 to 1 := 0;

    signal busy : std_logic := '0';

begin


    LedMatrix_Animation_Inst : entity work.LedMatrix_Anime
        port map (clk_Update => clk_div, rst => rst, stage => stage, 
            is_release => release_i, LedMatrix_Red => Data_red, LedMatrix_Green => Data_green, 
            Pwm_Level_R => pwmlevelR, Pwm_Level_G => pwmlevelG);

    LedMatrix_PwmController_Inst : entity work.LedMatrix_Controller
        port map (clk_pwm => clk, rst => rst, clk_1khz => clk_1khz, 
            frame_data_Red => Data_red, frame_data_Green => Data_green, 
            pwm_level_R => pwmlevelR, pwm_level_G => pwmlevelG,
            Row_out => matrix_en, Col_out_Red => matrix_R, Col_out_Green => matrix_G);

    release_speed_stage <= level - 1 when level > 0 else 0;
    process(clk_100hz, rst)
    begin
        if (rst = '1') then
            clk_div <= '0';
            clkcount <= 0;

        elsif rising_edge(clk_100hz) then

            if clkcount = 63 then
                clkcount <= 0;
            end if;
            if clkcount >= ANIMATION_UPDATE_FREQ(release_speed_stage) then
                clk_div <= '1';
                clkcount <= 0;
            else
                clk_div <= '0';
                clkcount <= clkcount + 1;
            end if;

        end if;
    end process;

end architecture;