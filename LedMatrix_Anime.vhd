library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity LedMatrix_Anime is
    port (
        clk_Update           : in  std_logic;
        rst           : in  std_logic;

        stage         : in  integer range 0 to 8;
        release_pos   : in  integer range 0 to 7;
        is_release    : in  std_logic;
        
        LedMatrix_Red   : out std_logic_vector(63 downto 0);
        LedMatrix_Green : out std_logic_vector(63 downto 0);

        Pwm_Level_R   : out integer range 0 to 15;
        Pwm_Level_G   : out integer range 0 to 15
    );
end entity LedMatrix_Anime;

architecture rtl of LedMatrix_Anime is

    type pwm_array is array (0 to 8) of integer range 0 to 15;

    constant PwmR : pwm_array := (0, 0, 0, 0, 5, 5, 15, 15, 15);
    constant PwmG : pwm_array := (15, 15, 15, 15, 13, 13, 5, 5, 5);

    signal pwm_out_R  : std_logic_vector(63 downto 0) := (others => '0');
    signal pwm_out_G  : std_logic_vector(63 downto 0) := (others => '0');
    signal stage_reg  : integer range 0 to 8 := 0;

begin
    -- stage?????
    stage_reg <= stage-1 when stage > 0 else 0;

process(clk_Update, rst)
    variable tempG : std_logic_vector(63 downto 0);
    variable tempR : std_logic_vector(63 downto 0);
begin
    if rst = '1' then
        pwm_out_G <= (others => '0');
        pwm_out_R <= (others => '0');
    elsif rising_edge(clk_Update) then
        tempG := (others => '0');
        tempR := (others => '0');

        if is_release = '0' then
            -- 普通水位显示：亮当前水位行
            for j in 0 to 63 loop
                if (j >= (8*stage_reg)) and (j <= (8*stage_reg + 7)) then
                    tempG(j) := '1';
                    tempR(j) := '1';
                end if;
            end loop;

        else
            if (stage_reg mod 2) = 0 then
                for j in 0 to 63 loop
                    if (j >= (8*stage_reg + 7 - release_pos)) and (j <= (8*stage_reg + 7)) then
                        tempG(j) := '1';
                        tempR(j) := '1';
                    elsif (j < (8*stage_reg)) then
                        tempG(j) := '1';
                        tempR(j) := '1';
                    end if;
                end loop;
            else
                for j in 0 to 63 loop
                    if j <= (8*stage_reg + release_pos) then
                        tempG(j) := '1';
                        tempR(j) := '1';
                    end if;
                end loop;
            end if;
        end if;

        pwm_out_G <= tempG;
        pwm_out_R <= tempR;
    end if;
end process;


    LedMatrix_Red   <= pwm_out_R;
    LedMatrix_Green <= pwm_out_G;
    Pwm_Level_R     <= PwmR(stage_reg);
    Pwm_Level_G     <= PwmG(stage_reg);

end architecture rtl;
