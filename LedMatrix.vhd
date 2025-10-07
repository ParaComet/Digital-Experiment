library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix is 
    port (
        clk : in std_logic;
        clk_1khz : in std_logic;
        clk_100hz : in std_logic;
        rst : in std_logic;
        stage : in integer range 0 to 4;
        
        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R : out std_logic_vector(7 downto 0);
        matrix_G : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of LedMatrix is

    type Frequency is array (0 to 4) of integer range 0 to 62;

    constant ANIMATION_UPDATE_FREQ : Frequency := (60, 60, 40, 20, 10);  -- 100Hz

    component LedMatrix_Animation is
        port (
            clk_Update           : in  std_logic;
            rst           : in  std_logic;

            stage         : in  integer range 0 to 4;
            
            LedMatrix_Red   : out std_logic_vector(63 downto 0);
            LedMatrix_Green : out std_logic_vector(63 downto 0);

            Pwm_Level_R   : out integer range 0 to 15;
            Pwm_Level_G   : out integer range 0 to 15
        );
    end component;

    component LedMatrix_PwmController is
        port (
            clk_pwm         : in  std_logic;
            clk_1khz       : in  std_logic;
            rst             : in  std_logic;
 

            frame_data_Red   : in  std_logic_vector(63 downto 0);
            frame_data_Green : in  std_logic_vector(63 downto 0);

            pwm_level_R     : in integer range 0 to 15;
            pwm_level_G     : in integer range 0 to 15;

            Row_out         : out std_logic_vector(7 downto 0);
            Col_out_Red     : out std_logic_vector(7 downto 0);
            Col_out_Green   : out std_logic_vector(7 downto 0)       
        );
    end component; 

    signal clk_div : std_logic;
    signal clkcount : integer range 0 to 60;

    signal Data_red : std_logic_vector(63 downto 0);
    signal Data_green : std_logic_vector(63 downto 0);

    signal pwmlevelR : integer range 0 to 15;
    signal pwmlevelG : integer range 0 to 15;

begin
    LedMatrix_Animation_Inst : LedMatrix_Animation
        port map (clk_Update => clk_div, rst => rst, stage => stage, 
            LedMatrix_Red => Data_red, LedMatrix_Green => Data_green, 
            Pwm_Level_R => pwmlevelR, Pwm_Level_G => pwmlevelG);

    LedMatrix_PwmController_Inst : LedMatrix_PwmController
        port map (clk_pwm => clk, rst => rst, clk_1khz => clk_1khz, 
            frame_data_Red => Data_red, frame_data_Green => Data_green, 
            pwm_level_R => pwmlevelR, pwm_level_G => pwmlevelG,
            Row_out => matrix_en, Col_out_Red => matrix_R, Col_out_Green => matrix_G);


    process(clk_100hz, rst)
    begin
        if (rst = '1') then
            clk_div <= '0';
            clkcount <= 0;
        elsif rising_edge(clk_100hz) then
            if clkcount = 60 then
                clkcount <= 0;
            end if;
            if clkcount = ANIMATION_UPDATE_FREQ(stage) - 1 then
                clk_div <= '1';
                clkcount <= 0;
            else
                clk_div <= '0';
                clkcount <= clkcount + 1;
            end if;
        end if;
    end process;

end architecture;