library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Water_Lc is
    port (
        clk_50mhz : in std_logic;
        rst : in std_logic;

        btn_1 : in std_logic;
        btn_2 : in std_logic;

        LedMatrix_Row : out std_logic_vector(7 downto 0);
        LedMatrix_Col_R : out std_logic_vector(7 downto 0);
        LedMatrix_Col_G : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of Water_Lc is

constant INPUT_CLK : integer := 50_000_000;  -- 主时钟（Hz）
constant DETECT_TICKS : integer := INPUT_CLK / 1_000 * 100; -- 100ms

signal clk_1mhz : std_logic;
signal clk_1khz : std_logic;
signal clk_100hz : std_logic;

signal stage : integer range 0 to 8 := 0;
signal Detect_cnt : integer range 0 to 100 := 0;

signal release_i : std_logic := '0'; --是否释放
signal release_auto : std_logic := '0'; --自动释放或手动释放
signal release_stage : integer range 0 to 3 := 0; --手动释放挡位

signal matrix_en_i : std_logic_vector(7 downto 0);
signal matrix_R_i : std_logic_vector(7 downto 0);
signal matrix_G_i : std_logic_vector(7 downto 0);
signal key_flag : integer range 0 to 2;

type State_Type is (IDLE, WAIT_DETECT_START, WAIT_DETECT_END);

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
    process(clk_50mhz, rst)
    begin
        if rst = '1' then
            current_state <= IDLE;
            next_state <= IDLE;
            Detect_cnt <= 0;    
        elsif rising_edge(clk_50mhz) then
            current_state <= next_state;
            case current_state is
                when IDLE =>
                    Detect_cnt <= 0;
                    if matrix_en_i = "11111111" then
                        next_state <= WAIT_DETECT_START;
                    else
                        next_state <= IDLE;
                    end if;
                when WAIT_DETECT_START =>
                    if matrix_en_i /= "11111111" then
                        next_state <= WAIT_DETECT_END;
                        Detect_cnt <= 0;
                    else
                        next_state <= WAIT_DETECT_START;
                    end if;
                when WAIT_DETECT_END =>
                    if matrix_en_i = "11111111" then
                        if Detect_cnt < DETECT_TICKS then
                            Detect_cnt <= Detect_cnt + 1;
                            next_state <= WAIT_DETECT_END;
                        else
                            release_i <= '1';
                            if stage < 8 then
                                stage <= stage + 1;
                            end if;
                            next_state <= IDLE;
                        end if;
                    else
                        Detect_cnt <= 0;
                        next_state <= WAIT_DETECT_END;
                    end if;
                when others =>
                    next_state <= IDLE;
            end case;
        end if;
    end process;
end architecture;