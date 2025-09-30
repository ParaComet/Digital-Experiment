library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix_Animation is
    port (
        clk_Update           : in  std_logic;
        rst           : in  std_logic;

        stage         : in  integer range 0 to 4;
        
        LedMatrix_Red   : out std_logic_vector(63 downto 0);
        LedMatrix_Green : out std_logic_vector(63 downto 0);

        Pwm_Level_R   : out integer range 0 to 15;
        Pwm_Level_G   : out integer range 0 to 15
    );
end entity LedMatrix_Animation;

architecture rtl of LedMatrix_Animation is

    -- 基础图案
    constant STEP0 : std_logic_vector(63 downto 0) := x"000000000000FF00"; -- line 1
    constant STEP1 : std_logic_vector(63 downto 0) := x"00000000000000FF"; -- line 2
    constant STEP2 : std_logic_vector(63 downto 0) := x"0000000000FF0000"; -- line 3
    constant STEP3 : std_logic_vector(63 downto 0) := x"00000000FF000000"; -- line 4

    type step_type is array (0 to 3) of std_logic_vector(63 downto 0);

    constant step_Table1 : step_type := (STEP0, STEP1, STEP2, STEP3);
    constant step_Table2 : step_type := (STEP0 or STEP2, STEP1 or STEP3, STEP0 or STEP2, STEP1 or STEP3);

    type table_array is array (0 to 4) of step_type;

    constant R_table : table_array := (
        0 => (others => (others => '0')), 
        1 => step_Table1,                 
        2 => step_Table1,                
        3 => step_Table2,                 
        4 => step_Table2                   
    );

    constant G_table : table_array := (
        0 => step_Table2, 
        1 => step_Table2, 
        2 => step_Table2, 
        3 => step_Table1, 
        4 => step_Table1  
    );

    type pwm_array is array (0 to 4) of integer range 0 to 15;

    constant PwmR : pwm_array := (0, 7, 11, 11, 11);
    constant PwmG : pwm_array := (11, 11, 11, 7, 11);

    signal step_index : integer range 0 to 3 := 0;
    signal pwm_out_R  : std_logic_vector(63 downto 0) := (others => '0');
    signal pwm_out_G  : std_logic_vector(63 downto 0) := (others => '0');

begin

    process(clk_Update, rst)
    begin
        if rst = '1' then
            step_index <= 0;
        elsif rising_edge(clk_Update) then
            step_index <= (step_index + 1) mod 4;
        end if;
    end process;

    process(clk_Update, rst)
    begin
        if rst = '1' then
            pwm_out_R <= (others => '0');
        elsif rising_edge(clk_Update) then
            pwm_out_R <= R_table(stage)(step_index);
            pwm_out_G <= G_table(stage)(step_index);
        end if;
    end process;

    LedMatrix_Red   <= pwm_out_R;
    LedMatrix_Green <= pwm_out_G;
    Pwm_Level_R     <= PwmR(stage);
    Pwm_Level_G     <= PwmG(stage);

end architecture rtl;
