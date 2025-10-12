library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Water_Lc is
    port (
        clk_50mhz : in std_logic;
        rst : in std_logic;

        btn_1 : in std_logic;
        btn_2 : in std_logic;
        sw0 : in std_logic;

        echo : in std_logic;
        trig : out std_logic;
        beep : out std_logic;


        LedMatrix_Row : out std_logic_vector(7 downto 0);
        LedMatrix_Col_R : out std_logic_vector(7 downto 0);
        LedMatrix_Col_G : out std_logic_vector(7 downto 0);

        en_out : out std_logic_vector(7 downto 0);
        deg_out : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of Water_Lc is

constant INPUT_CLK : integer := 50_000_000;  -- 主时钟（Hz）
constant DETECT_TICKS : integer := INPUT_CLK / 1_000 * 100; -- 100ms

signal clk_1mhz : std_logic;
signal clk_1khz : std_logic;
signal clk_100hz : std_logic;

signal stage : integer range 0 to 8 := 0; -- 当前水位阶段 0-8
signal Detect_cnt : integer range 0 to 100 := 0;

signal release_i : std_logic := '0'; --是否释放
signal release_auto : std_logic := '0'; --自动释放或手动释放
signal release_stage : integer range 0 to 3 := 0; --手动释放挡位

signal matrix_en_i : std_logic_vector(7 downto 0);
signal matrix_R_i : std_logic_vector(7 downto 0);
signal matrix_G_i : std_logic_vector(7 downto 0);
signal en_out_i : std_logic_vector(7 downto 0);
signal deg_out_i : std_logic_vector(7 downto 0);
signal key_flag : integer range 0 to 2;

signal level : integer range 0 to 4 := 0; -- 释放等级 0-4
signal is_time_to_release : std_logic := '0';
signal is_time_to_detect : std_logic := '0';
signal start : std_logic := '0';
signal busy_r : std_logic;
signal valid : std_logic;
signal beep_en : std_logic := '0';
signal stage_beep : integer range 0 to 4 := 0; -- 蜂鸣器响度等级 0-4
signal shine : std_logic := '0';

signal dist_int : integer range 0 to 999 := 0;

type State_Type is (IDLE, WAIT_DETECT_START, WAIT_DETECT_END, WAIT_RELEASE_END, WAIT_STATE);

signal current_state, next_state : State_Type := IDLE;


begin
    Button_Inst : entity work.Button
        port map (
            clk_1khz => clk_1khz,
            rst => rst,
            btn0 => btn_1,
            btn2 => btn_2,
            key_flag => key_flag
        );
    Clk_Generater_Inst : entity work.Clk_Generater
        generic map (
            INPUT_CLK => 50_000_000
        )
        port map (
            clk => clk_50mhz,
            rst => rst,
            clk_1khz => clk_1khz,
            clk_100hz => clk_100hz,
            clk_1mhz => clk_1mhz
        );
    
    LedMatrix_inst: entity work.LedMatrix
     port map(
        clk => clk_1mhz,
        clk_1khz => clk_1khz,
        clk_100hz => clk_100hz,
        rst => rst,
        stage => stage,
        release_i => release_i,
        release_auto => release_auto,
        release_stage => release_stage,
        matrix_en => matrix_en_i,
        matrix_R => matrix_R_i,
        matrix_G => matrix_G_i
    );

    DigitalDisplay_inst: entity work.DigitalDisplay
     port map(
        clk => clk_50mhz,
        rst => rst,
        dist_int => dist_int,
        stage => stage,
        level => level,
        en_out => en_out_i,
        deg_out => deg_out_i
    );

    UltraSonic_inst: entity work.UltraSonic
     port map(
        clk => clk_50mhz,
        rst => rst,
        start => start,
        echo => echo,
        trig => trig,
        busy => busy_r,
        distance_mm => dist_int,
        valid => valid
    );

    Beep_inst: entity work.Beep
     port map(
        clk => clk_50mhz,
        rst => rst,
        beep_en => beep_en,
        stage => stage_beep,
        beep => beep
    );


    process(clk_50mhz, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            next_state <= IDLE;
            Detect_cnt <= 0;    
        elsif rising_edge(clk_50mhz) then
            current_state <= next_state;
            start <= '0';
            case current_state is
                when IDLE =>
                    Detect_cnt <= 0;
                    if Detect_cnt = DETECT_TICKS -1 then
                        next_state <= WAIT_DETECT_START;
                        Detect_cnt <= 0;
                    else
                        next_state <= IDLE;
                        Detect_cnt <= Detect_cnt + 1;
                        start <= '1';
                    end if;
                when WAIT_DETECT_START =>
                    if busy_r = '1' then
                        next_state <= WAIT_DETECT_END;
                    else
                        next_state <= WAIT_DETECT_START;
                    end if;
                when WAIT_DETECT_END =>
                
                    if busy_r = '0' then
                        if valid = '1' then
                            if dist_int < 200 then
                                stage <= 8;
                                is_time_to_release <= '1'; 
                            elsif dist_int < 300 then
                                stage <= 7;

                            elsif dist_int < 400 then
                                stage <= 6;
                            elsif dist_int < 500 then
                                stage <= 5;
                            elsif dist_int < 600 then
                                stage <= 4;
                            elsif dist_int < 700 then
                                stage <= 3;
                            elsif dist_int < 800 then
                                stage <= 2;
                            elsif dist_int < 900 then
                                stage <= 1;
                            else
                                stage <= 0;
                            end if;
                        end if;
                        next_state <= WAIT_RELEASE_END;
                    else
                        next_state <= WAIT_DETECT_END;
                    end if;
                when WAIT_RELEASE_END =>

                    if stage = 8 or stage = 7 then
                        shine <= '1';
                    else
                        shine <= '0';
                    end if;
                    if stage = 8 or stage = 7 then
                        stage_beep <= 3;
                        beep_en <= '1';

                    elsif stage = 6 or stage = 5 then
                        stage_beep <= 1;
                        beep_en <= '1';

                    else
                        stage_beep <= 0;
                        beep_en <= '0';

                    end if;

                    next_state <= IDLE;
                when others =>
                    next_state <= IDLE;
            end case;
        end if;
    end process;
    process(clk_1khz, rst)
    begin
        if rst = '1' then
            release_i <= '0';
            release_auto <= '0';
            release_stage <= 0;
        elsif rising_edge(clk_1khz) then

            -- BTN7 控制手动开/关泄洪
            if key_flag = 1 then
                if (dist_int >= 600 and dist_int <= 800) then
                    release_i <= not release_i;
                end if;
            end if;

            -- 若正在泄洪，但水位低于安全线，则自动关闭
            if (release_i = '1' and dist_int < 600) then
                release_i <= '0';
            end if;

            -- 模式判断
            if sw0 = '0' then
                -- 自动模式
                release_auto <= '1';
                case dist_int is
                    when 400 to 600 =>
                        release_stage <= 1; -- 低速
                    when 601 to 800 =>
                        release_stage <= 2; -- 中速
                    when 801 to 999 =>
                        release_stage <= 3; -- 高速
                    when others =>
                        release_stage <= 0;
                end case;

            else
                -- 手动模式
                release_auto <= '0';
                if key_flag = 2 then
                    if release_i = '1' then
                        if release_stage = 3 then
                            release_stage <= 0;
                        else
                            release_stage <= release_stage + 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;


    process(clk_100hz, rst)
        
    variable shine_counter : integer := 0;
    variable shine_state : std_logic := '0';
    begin
        if rst = '1' then
        elsif rising_edge(clk_100hz) then
            if shine = '1' then
                if shine_counter < 50 then
                    shine_counter := shine_counter + 1;
                    shine_state := not shine_state;
                else
                    shine_counter := 0;
                end if;

                if shine = '1' and shine_state = '1' then
                    en_out <= en_out_i;
                    en_out(6 downto 4) <= (others => '1');
                else
                    en_out <= en_out_i;
                end if;
            end if;
        end if;

    end process;
    deg_out <= deg_out_i;
    LedMatrix_Row <= matrix_en_i;
    LedMatrix_Col_R <= matrix_R_i;
    LedMatrix_Col_G <= matrix_G_i;

end architecture;