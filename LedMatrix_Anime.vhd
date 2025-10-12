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
    -- stage¼Ä´æÆ÷
    stage_reg <= stage;

    process(clk_Update, rst)
    begin
        if rst = '1' then
            stage_reg <= 0;
            pwm_out_G <= (others => '0');
            pwm_out_R <= (others => '0');
            stage_reg <= 0;
        elsif rising_edge(clk_Update) then
            pwm_out_G <= (others => '0');
            pwm_out_R <= (others => '0');

            if is_release = '0' then    
                pwm_out_G(8*stage_reg+7 downto 0) <= (others => '1');
                pwm_out_R(8*stage_reg+7 downto 0) <= (others => '1');
            else
                if stage_reg mod 2 = 0 then
                    pwm_out_G(8*stage_reg+7 downto 8*stage_reg+7-release_pos) <= (others => '1');
                    pwm_out_R(8*stage_reg+7 downto 8*stage_reg+7-release_pos) <= (others => '1');
                    pwm_out_G(8*stage_reg-1 downto 0) <= (others => '1');
                    pwm_out_R(8*stage_reg-1 downto 0) <= (others => '1');
                else 
                    pwm_out_G(8*stage_reg+release_pos downto 0) <= (others => '1');
                    pwm_out_R(8*stage_reg+release_pos downto 0) <= (others => '1');
                end if;
            end if;
        end if;
    end process;
    -- ¶¯»­¿ØÖÆ
    LedMatrix_Red   <= pwm_out_R;
    LedMatrix_Green <= pwm_out_G;
    Pwm_Level_R     <= PwmR(stage_reg);
    Pwm_Level_G     <= PwmG(stage_reg);

end architecture rtl;
