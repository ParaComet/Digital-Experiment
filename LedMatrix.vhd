library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix is 
    port (
        clk : in std_logic;
        clk_100hz : in std_logic;
        rst : in std_logic;
        stage : in integer range 0 to 4;
        
        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R : out std_logic_vector(63 downto 0);
        matrix_G : out std_logic_vector(63 downto 0)
    );
end entity;

architecture rtl of LedMatrix is

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
            rst             : in  std_logic;
            clk_100hz       : in  std_logic;

            frame_data_Red   : in  std_logic_vector(63 downto 0);
            frame_data_Green : in  std_logic_vector(63 downto 0);

            pwm_level_R     : in integer range 0 to 15;
            pwm_level_G     : in integer range 0 to 15;

            Row_out         : out std_logic_vector(7 downto 0);
            Col_out_Red     : out std_logic_vector(7 downto 0);
            Col_out_Green   : out std_logic_vector(7 downto 0)       
        );
    end component; 

    signal Data_red : std_logic_vector(63 downto 0);
    signal Data_green : std_logic_vector(63 downto 0);

    signal pwmlevelR : integer range 0 to 15;
    signal pwmlevelG : integer range 0 to 15;

begin
    LedMatrix_Animation_Inst : LedMatrix_Animation
        port map (clk_Update => clk, rst => rst, stage => stage, LedMatrix_Red => Data_red, LedMatrix_Green => Data_green, Pwm_Level_R => pwmlevelR, Pwm_Level_G => pwmlevelG);
end architecture;