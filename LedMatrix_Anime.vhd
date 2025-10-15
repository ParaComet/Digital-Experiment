library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix_Anime is
    port (
        clk_Update           : in  std_logic;
        rst           : in  std_logic;

        stage         : in  integer range 0 to 8;
        is_release    : in  std_logic;
        
        LedMatrix_Red   : out std_logic_vector(63 downto 0);
        LedMatrix_Green : out std_logic_vector(63 downto 0);

        Pwm_Level_R   : out integer range 0 to 15;
        Pwm_Level_G   : out integer range 0 to 15
    );
end entity LedMatrix_Anime;

architecture rtl of LedMatrix_Anime is

    type pwm_array is array (0 to 8) of integer range 0 to 15;
    type level_array is array (0 to 7) of std_logic_vector(63 downto 0);
    type release_array is array (0 to 3) of std_logic_vector(63 downto 0);

    constant PwmR : pwm_array := (0, 0, 0, 0, 5, 5, 15, 15, 15);
    constant PwmG : pwm_array := (15, 15, 15, 15, 13, 13, 5, 5, 5);
    constant Level1 : std_logic_vector (63 downto 0) := x"00000000000000FF"; -- 64'b
    constant Level2 : std_logic_vector (63 downto 0) := x"000000000000FFFF"; -- 64'b
    constant Level3 : std_logic_vector (63 downto 0) := x"0000000000FFFFFF"; -- 64'b
    constant Level4 : std_logic_vector (63 downto 0) := x"00000000FFFFFFFF"; -- 64'b
    constant Level5 : std_logic_vector (63 downto 0) := x"000000FFFFFFFFFF"; -- 64'b
    constant Level6 : std_logic_vector (63 downto 0) := x"0000FFFFFFFFFFFF"; -- 64'b
    constant Level7 : std_logic_vector (63 downto 0) := x"00FFFFFFFFFFFFFF"; -- 64'b
    constant Level8 : std_logic_vector (63 downto 0) := x"FFFFFFFFFFFFFFFF"; -- 64'b

    constant Table_Level : level_array := (Level1, Level2, Level3, Level4, Level5, Level6, Level7, Level8 );
    constant Table_release : release_array := (
        x"BF" & x"A1" & x"AD" & x"A5" & x"A5" & x"BD" & x"81" & x"FF",
        x"7F" & x"41" & x"5D" & x"55" & x"45" & x"7D" & x"01" & x"FF",
        x"FF" & x"81" & x"BD" & x"A5" & x"A5" & x"B5" & x"85" & x"FD",
        x"FF" & x"80" & x"BF" & x"A1" & x"A5" & x"BD" & x"81" & x"FF"
    );

    signal pwm_out_R  : std_logic_vector(63 downto 0) := (others => '0');
    signal pwm_out_G  : std_logic_vector(63 downto 0) := (others => '0');
    signal stage_reg  : integer range 0 to 8 := 0;

begin
    -- stage?????
    stage_reg <= stage;

process(clk_Update, rst)
    variable tempG : std_logic_vector(63 downto 0);
    variable tempR : std_logic_vector(63 downto 0);
    variable release_index : integer range 0 to 4 := 0;
begin
    if rst = '1' then
        pwm_out_G <= (others => '0');
        pwm_out_R <= (others => '0');
    elsif rising_edge(clk_Update) then
        tempG := (others => '0');
        tempR := (others => '0');

        if is_release = '0' then
            -- 普通水位显示
            if stage_reg > 0 then
                tempG := Table_Level(stage_reg - 1);
                tempR := Table_Level(stage_reg - 1);
            end if;
        else
            if release_index < 4 then
                tempG := Table_release(release_index);
                tempR := Table_release(release_index);
                release_index := release_index + 1;
            else
                release_index := 0;
            end if;
        end if;

    end if;
    LedMatrix_Green <= tempG;
    LedMatrix_Red <= tempR;
end process;

    Pwm_Level_R     <= PwmR(stage_reg);
    Pwm_Level_G     <= PwmG(stage_reg);

end architecture rtl;
