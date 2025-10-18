library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Water_Lc is
    port (
        clk : in std_logic;
        rst : in std_logic;

        btn_1 : in std_logic;
        btn_2 : in std_logic;
        sw0 : in std_logic;

        echo : in std_logic;
        trig : out std_logic;
        beep : out std_logic;

        busy : out std_logic;
        echoled : out std_logic;


        LedMatrix_Row : out std_logic_vector(7 downto 0);
        LedMatrix_Col_R : out std_logic_vector(7 downto 0);
        LedMatrix_Col_G : out std_logic_vector(7 downto 0);

        en_out : out std_logic_vector(7 downto 0);
        deg_out : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of Water_Lc is

--constant INPUT_CLK : integer := 1_000_000;  -- 主时钟（Hz）
constant DETECT_TICKS : integer := 1_00_000; -- 100ms


signal clk_1khz : std_logic;
signal clk_100hz : std_logic;
signal clk_1mhz  : std_logic;

signal stage : integer range 0 to 8 := 0; -- 当前水位阶段 0-8
signal Detect_cnt : integer range 0 to 100_000 := 0;

signal release_i : std_logic := '0'; --是否释放


signal matrix_en_i : std_logic_vector(7 downto 0);
signal matrix_R_i : std_logic_vector(7 downto 0);
signal matrix_G_i : std_logic_vector(7 downto 0);
signal en_out_i : std_logic_vector(7 downto 0);
signal deg_out_i : std_logic_vector(7 downto 0);
signal key_flag : integer range 0 to 2;

signal release_level_auto : integer range 0 to 3 := 0; -- 释放等级 0-4
signal release_level_manual : integer range 0 to 3 := 0;
signal level : integer range 0 to 3;
signal is_time_to_release : std_logic := '0';

signal start : std_logic := '0';
signal busy_r : std_logic;
signal valid : std_logic;
signal beep_en : std_logic := '0';
signal warning_stage : integer range 0 to 4 := 0; 

signal is_release : std_logic := '0'; -- 是否在释放

signal dist_int : integer range 0 to 1001 := 0;
signal shine    : std_logic := '0';

type State_Type is (IDLE, WAIT_DETECT_START, WAIT_DETECT_END, WAIT_RELEASE_END, WAIT_STATE);

signal current_state, next_state : State_Type := IDLE;


begin
    Button_Inst : entity work.Button
        port map (
            clk_1khz => clk_1mhz,
            rst => rst,
            btn0 => btn_1,
            btn2 => btn_2,
            key_flag => key_flag
        );
    Clk_Generater_Inst : entity work.Clk_Generater
        generic map (
            INPUT_CLK => 1_000_000
        )
        port map (
            clk => clk,
            rst => rst,
            clk_1khz => clk_1khz,
            clk_100hz => clk_100hz
        );
    
    LedMatrix_inst: entity work.LedMatrix
     port map(
        clk => clk_1mhz,
        clk_1khz => clk_1khz,
        clk_100hz => clk_100hz,
        rst => rst,
        stage => stage,
        level => level,
        release_i => is_release,
        matrix_en => matrix_en_i,
        matrix_R => matrix_R_i,
        matrix_G => matrix_G_i
    );

    DigitalDisplay_inst: entity work.DigitalDisplay
     port map(
        clk => clk_1mhz,
        rst => rst,
        dist_int => dist_int,
        warning_stage => warning_stage,
        level => level,
        is_release => is_release,
        en_out => en_out_i,
        deg_out => deg_out_i
    );

    UltraSonic_inst: entity work.UltraSonic
     port map(
        clk => clk_1mhz,
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
        clk => clk_1mhz,
        rst => rst,
        beep_en => beep_en,
        stage => stage,
        beep => beep
    );

    clk_1mhz <= clk;
    busy <= busy_r;
    echoled <= echo;

    process(clk_1mhz, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            next_state <= IDLE;
            Detect_cnt <= 0;  
            is_time_to_release <= '0';
            start <= '0';
            stage <= 1;  
        elsif rising_edge(clk_1mhz) then
            current_state <= next_state;

            case current_state is
                when IDLE =>
                    --Detect_cnt <= 0;
                    if Detect_cnt = DETECT_TICKS -1 then
                        next_state <= WAIT_DETECT_START;
                        Detect_cnt <= 0;
                        start <= '1';
                    else
                        next_state <= IDLE;
                        Detect_cnt <= Detect_cnt + 1;

                    end if;
                when WAIT_DETECT_START =>
                    if busy_r = '1' then
                        start <= '0';
                        next_state <= WAIT_DETECT_END;
                    else
                        next_state <= WAIT_DETECT_START;
                    end if;
                when WAIT_DETECT_END =>
                
                    if busy_r = '0' then
                        if valid = '1' then
                            if dist_int > 800 then
                                stage <= 8; 
                                warning_stage <= 4;
                            elsif dist_int >700 then
                                stage <= 7;
                                warning_stage <= 3;
                            elsif dist_int > 600 then
                                stage <= 6;
                                warning_stage <= 3;
                            elsif dist_int > 500 then
                                stage <= 5;
                                warning_stage <= 2;
                            elsif dist_int > 400 then
                                stage <= 4;
                                warning_stage <= 2;
                            elsif dist_int > 300 then
                                stage <= 3;
                                warning_stage <= 1;
                            elsif dist_int > 200 then
                                stage <= 2;
                                warning_stage <= 1;
                            elsif dist_int > 100 then
                                stage <= 1;
                                warning_stage <= 1;
                            else
                                stage <= 1;
                                warning_stage <= 0;
                            end if;
                        end if;
                        next_state <= WAIT_RELEASE_END;
                    else
                        next_state <= WAIT_DETECT_END;
                    end if;
                when WAIT_RELEASE_END =>
                    case warning_stage is   
                        when 4 | 3 | 2 => beep_en <= '1';
                        when others => beep_en <= '0';
                    end case;  
                    if stage = 8 then
                        is_time_to_release <= '1';
                    elsif stage < 4 then
                        is_time_to_release <= '0';
                    end if;
                    next_state <= IDLE;
                when others =>
                    next_state <= IDLE;
            end case;
        end if;
    end process;
    process(clk_1mhz, rst)
    begin
        if rst = '1' then
            is_release <= '0';
            
        elsif rising_edge(clk_1mhz) then

            if is_time_to_release = '1' then
                is_release <= '1';
            else
                if stage <= 3 then
                    is_release <= '0';
                end if;

                if key_flag = 1 then
                    if stage =6 or stage =7 then
                        is_release <= not is_release;
                    end if;
                elsif key_flag = 2 then
                    if release_level_auto = 3 then
                        release_level_auto <= 1;
                    else 
                        release_level_auto <= release_level_auto + 1;
                    end if; 
                end if;
            end if;

        end if;
    end process;

    process(clk_100hz)
    variable cnt : integer range 0 to 50 := 0;
    begin
        if rst = '1' then
            shine <= '0';
        elsif rising_edge(clk_100hz) then
            if warning_stage = 3 then
                if cnt = 49 then
                    cnt := 0;
                    shine <= not shine;
                else
                    cnt := cnt + 1;
                end if;
            else
                shine <= '0';
            end if;
        end if;
    end process;
    release_level_manual <= warning_stage - 1 when warning_stage > 1 else 1;
    level <= release_level_manual when sw0 = '0' else release_level_auto; 
    en_out(7 downto 3) <= en_out_i(7 downto 3);
    en_out(2 downto 0) <= en_out_i(2 downto 0) when shine = '0' else (others => '1');
    deg_out <= deg_out_i;
    LedMatrix_Row <= matrix_en_i;
    LedMatrix_Col_R <= matrix_R_i;
    LedMatrix_Col_G <= matrix_G_i;

end architecture;