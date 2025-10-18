library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Q2_lyf is
    port(
        clk       : in std_logic;
        button1   : in std_logic;
        button2   : in std_logic;
        remote_in : in std_logic;
        rst       : in std_logic := '0';

        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R  : out std_logic_vector(7 downto 0);
        matrix_G  : out std_logic_vector(7 downto 0);

        beep_out  : out std_logic;
        power     : out std_logic;
        en_out    : out std_logic_vector(7 downto 0);
        deg_out   : out std_logic_vector(7 downto 0);


        scl       : out std_logic;
        sda       : inout std_logic
    );
end Q2_lyf;

architecture behavioral of Q2_lyf is

    signal stage        : integer range 0 to 4 := 0;
    signal manual_stage : integer range 0 to 4 := 0;
    signal auto_stage   : integer range 0 to 4 := 0;

    signal clk_1khz     : std_logic;
    signal clk_100hz    : std_logic;
    signal clk_8khz     : std_logic;


    signal is_manual    : std_logic := '0'; -- '0' = Auto, '1' = Manual
    signal power_on     : std_logic := '1'; 

    -- Button 
    signal key_flag     : integer range 0 to 2 := 0; -- 0 none, 1 btn1, 2 btn2

    -- Temp module 
    signal temp_reg     : integer range 0 to 63 := 0;
    signal temp_dot_reg : std_logic := '0';
    signal temp_ena     : std_logic := '0';
    signal temp_busy    : std_logic := '0';

    signal read_cnt     : integer range 0 to 100000 := 0;
    constant READ_TICKS : integer := 100000; -- 0.2s @ 1MHz

    
    type rstate is (R_IDLE, R_WAIT_BUSY_START, R_WAIT_BUSY_DONE);
    signal rstate_sig : rstate := R_IDLE;

    signal en_out_i     : std_logic_vector(7 downto 0) := (others => '0');
    signal deg_out_i    : std_logic_vector(7 downto 0) := (others => '0');
    signal matrix_en_i  : std_logic_vector(7 downto 0) := (others => '0');
    signal matrix_R_i   : std_logic_vector(7 downto 0) := (others => '0');
    signal matrix_G_i   : std_logic_vector(7 downto 0) := (others => '0');
    signal beep_en_i    : std_logic := '0';
    signal is_manual_i  : integer range 0 to 1 := 0;

    -- IR module
    signal repeat_en    : std_logic;
    signal data_en      : std_logic;
    signal data_en_r    : std_logic := '0';
    signal ir_data      : std_logic_vector(7 downto 0);
    signal beep_mute    : std_logic := '1';
    signal timer_en     : integer range 0 to 2 := 0;
    signal timer_set_r  : integer range 0 to 9 := 0;
    signal timer_set_c  : integer range 0 to 4 := 0;
    signal time_ten_r   : integer range 0 to 9 := 0;
    signal time_int_r   : integer range 0 to 9 := 0;
    signal time_start   : std_logic := '0';
    signal time_finish  : std_logic := '0';
    signal time_show    : std_logic := '0';

    component Clk_Generater is
        generic (INPUT_CLK : integer := 1_000_000);
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            clk_8khz  : out std_logic;
            clk_1khz  : out std_logic;
            clk_100hz : out std_logic
        );
    end component;

    component Button is
        port (
            clk_8khz : in  std_logic;
            rst      : in  std_logic;
            btn0     : in  std_logic;  
            btn2     : in  std_logic;  
            key_flag : out integer range 0 to 2  -- 0 none, 1 btn1, 2 btn2
        );
    end component;

    component DigitalDisplay is
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            temp_int   : in  integer range 0 to 63;
            temp_dot   : in  std_logic;
            stage      : in  integer range 0 to 4;
            is_manual  : in  integer range 0 to 1;

            time_ten   : in integer range 0 to 9;
            time_int   : in integer range 0 to 9;
            time_start : in std_logic;
            time_show  : in std_logic;
            time_fi    : out std_logic; 

            en_out     : out std_logic_vector(7 downto 0);
            deg_out    : out std_logic_vector(7 downto 0)
        );
    end component;

    component LedMatrix is
        port (
            clk       : in  std_logic;
            clk_1khz  : in  std_logic;
            clk_100hz : in  std_logic;
            rst       : in  std_logic;
            stage     : in  integer range 0 to 4;

            matrix_en : out std_logic_vector(7 downto 0);
            matrix_R  : out std_logic_vector(7 downto 0);
            matrix_G  : out std_logic_vector(7 downto 0)
        );
    end component;

    component Beep is
        port (
            clk     : in  std_logic;
            rst     : in  std_logic;
            beep_en : in  std_logic;
            stage   : in  integer range 0 to 4;
            beep    : out std_logic
        );
    end component;

    component Tempreature is
        port (
            clk   : in  std_logic;
            rst   : in  std_logic;
            ena   : in  std_logic;
            button: in  std_logic;

            temp  : out integer range 0 to 63;
            temp_dot : out std_logic; 

            scl   : out std_logic;
            sda   : inout std_logic;
            busy  : out std_logic
        );
    end component;

    component Ir_Module is
        port (
            clk_8khz   : in  std_logic;
            rst_n      : in  std_logic;
            remote_in  : in  std_logic;

            repeat_en  : out std_logic;
            data_en    : out std_logic;
            data       : out std_logic_vector (7 downto 0)
        );
    end component;

begin


    clkgen_inst : component Clk_Generater
        generic map (INPUT_CLK => 1_000_000)
        port map (clk => clk, rst => rst, clk_8khz => clk_8khz, 
            clk_1khz => clk_1khz, clk_100hz => clk_100hz);

    button_inst : component Button
        port map (
            clk_8khz => clk_8khz,
            rst      => rst,
            btn0     => button1, 
            btn2     => button2, 
            key_flag => key_flag
        );

    Display_Inst : component DigitalDisplay
        port map (
            clk        => clk,
            rst        => rst,
            temp_int   => temp_reg,
            temp_dot   => temp_dot_reg,
            stage      => stage,
            is_manual  => is_manual_i,
            time_ten   => time_ten_r,
            time_int   => time_int_r,
            time_start => time_start,
            time_show  => time_show,
            time_fi    => time_finish,
            en_out     => en_out_i,
            deg_out    => deg_out_i
        );

    LedMatrix_Inst : component LedMatrix
        port map (
            clk       => clk,
            clk_1khz  => clk_1khz,
            clk_100hz => clk_100hz,
            rst       => rst,
            stage     => stage,
            matrix_en => matrix_en_i,
            matrix_R  => matrix_R_i,
            matrix_G  => matrix_G_i
        );

    Beep_Inst : component Beep
        port map (
            clk     => clk,
            rst     => rst,
            beep_en => beep_en_i, 
            stage   => stage,
            beep    => beep_out
        );

    Temp_Inst : component Tempreature
        port map (
            clk   => clk,
            rst   => rst,
            ena   => temp_ena,   
            button=> '0',       
            temp  => temp_reg,
            temp_dot => temp_dot_reg,
            scl   => scl,
            sda   => sda,
            busy  => temp_busy
        );

    Ir_Module_inst: component Ir_Module
     port map(
        clk_8khz => clk_8khz,
        rst_n => rst,
        remote_in => remote_in,
        repeat_en => repeat_en,
        data_en => data_en,
        data => ir_data
    );

    en_out   <= (others => '1') when power_on = '0' else en_out_i;
    deg_out  <= (others => '0') when power_on = '0' else deg_out_i;
    matrix_en<= (others => '1') when power_on = '0' else matrix_en_i;
    matrix_R <= (others => '0') when power_on = '0' else matrix_R_i;
    matrix_G <= (others => '0') when power_on = '0' else matrix_G_i;
    is_manual_i <= 1 when is_manual = '1' else 0;
    power <= power_on;
    beep_en_i <= power_on and beep_mute;
    

    process(clk_8khz, rst)
    begin
        if rst = '1' then
            is_manual <= '0';
            power_on  <= '1';
            manual_stage <= 0;

            time_show <= '0';
            time_start <= '0';
            timer_en <= 0;
            timer_set_c <= 0;
            time_int_r <= 0;
            time_ten_r <= 0;
        elsif rising_edge(clk_8khz) then

            data_en_r <= data_en;        
            if data_en_r = '0' and data_en = '1' then
                if timer_en = 1 then
                    timer_set_c <= timer_set_c + 1;
                end if;
                if ir_data = x"16" then
                    is_manual <= not is_manual;
                elsif ir_data = x"1C" then
                    power_on <= not power_on;
                elsif ir_data = x"19" then
                    if is_manual = '1' and timer_en /= 1 then
                        manual_stage <= 0;
                    elsif timer_en = 1 then
                        timer_set_r <= 0;
                    end if;
                elsif ir_data = x"45" then
                    if is_manual = '1' and timer_en /= 1 then
                        manual_stage <= 1;
                    elsif timer_en = 1 then
                        timer_set_r <= 1;
                    end if;
                elsif ir_data = x"46" then
                    if is_manual = '1' and timer_en /= 1 then
                        manual_stage <= 2;
                    elsif timer_en = 1 then
                        timer_set_r <= 2;
                    end if;
                elsif ir_data = x"47" then
                    if is_manual = '1' and timer_en /= 1 then
                        manual_stage <= 3;
                    elsif timer_en = 1 then
                        timer_set_r <= 3;
                    end if;
                elsif ir_data = x"44" then
                    if is_manual = '1' and timer_en /= 1 then
                        manual_stage <= 4;
                    elsif timer_en = 1 then
                        timer_set_r <= 4;
                    end if;
                elsif ir_data = x"40" then
                    if timer_en = 1 then
                        timer_set_r <= 5;
                    end if;
                elsif ir_data = x"43" then
                    if timer_en = 1 then
                        timer_set_r <= 6;
                    end if;
                elsif ir_data = x"07" then
                    if timer_en = 1 then
                        timer_set_r <= 7;
                    end if;
                elsif ir_data = x"15" then
                    if timer_en = 1 then
                        timer_set_r <= 8;
                    end if;
                elsif ir_data = x"09" then
                    if timer_en = 1 then
                        timer_set_r <= 9;
                    end if;
                elsif ir_data = x"08" then
                    beep_mute <= not beep_mute;
                elsif ir_data = x"0D" then
                    if timer_en = 2 then
                        timer_en <= 0;
                    else
                        timer_en <= timer_en + 1;
                    end if;
                elsif ir_data = x"18" then
                    if is_manual = '1' then
                        if manual_stage = 4 then
                            manual_stage <= 0;
                        else
                            manual_stage <= manual_stage + 1;
                        end if;
                    end if;
                elsif ir_data = x"52" then
                    if is_manual = '1' then
                        if manual_stage = 0 then
                            manual_stage <= 4;
                        else
                            manual_stage <= manual_stage - 1;
                        end if;
                    end if;
                end if;
            elsif key_flag = 2 then
                is_manual <= not is_manual;
            elsif key_flag = 1 then
  
                if is_manual = '0' then
                    power_on <= not power_on;
                else
                    if manual_stage = 4 then
                        manual_stage <= 0;
                    else
                        manual_stage <= manual_stage + 1;
                    end if;
                end if;
            end if;

            if timer_en = 1 then
                time_show <= '1'; 
                if timer_set_c = 1 then
                    time_ten_r <= timer_set_r;
                elsif timer_set_c = 2 then
                    time_int_r <= timer_set_r;
                    timer_set_c <= 0;
                end if;
            elsif timer_en = 2 then
                time_start <= '1';
                if time_finish = '1' then
                    timer_en <= 0;
                    time_start <= '0';
                    power_on <= '0';
            
                end if;
            else
                time_show <= '0';
                time_start <= '0';
                timer_set_c <= 0;
            end if;
        end if;
    end process;

    process(clk, rst)
    begin
        if rst = '1' then
            read_cnt  <= 0;
            temp_ena  <= '0';
            rstate_sig<= R_IDLE;
        elsif rising_edge(clk) then
            temp_ena <= '0';
            case rstate_sig is
                when R_IDLE =>
                    if power_on = '1' then
                        if read_cnt < READ_TICKS - 1 then
                            read_cnt <= read_cnt + 1;
                        else
                            read_cnt <= 0;
                            temp_ena <= '1';
                            rstate_sig <= R_WAIT_BUSY_START;
                        end if;
                    else
                        read_cnt <= 0;
                    end if;

                when R_WAIT_BUSY_START =>
                    if temp_busy = '1' then
                        rstate_sig <= R_WAIT_BUSY_DONE;
                    end if;

                when R_WAIT_BUSY_DONE =>
                    
                    if temp_busy = '0' then
                        if is_manual = '0' and power_on = '1' then
                       
                            if temp_reg < 24 then           
                                auto_stage <= 0;
                            elsif temp_reg < 26 then         -- [24,26)
                                auto_stage <= 1;
                            elsif temp_reg < 28 then         -- [26,28)
                                auto_stage <= 2;
                            elsif temp_reg < 30 then         -- [28,30)
                                auto_stage <= 3;
                            else
                                auto_stage <= 4;                    -- >=30
                            end if;
                        end if;
                        rstate_sig <= R_IDLE;
                    end if;
            end case;
        end if;
    end process;

    stage <= manual_stage when is_manual = '1' else auto_stage;

end behavioral;