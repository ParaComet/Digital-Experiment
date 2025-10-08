library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Q2_lyf is
    port(
        clk       : in std_logic;
        button1   : in std_logic;
        button2   : in std_logic;
        rst       : in std_logic := '0';

        matrix_en : out std_logic_vector(7 downto 0);
        matrix_R  : out std_logic_vector(7 downto 0);
        matrix_G  : out std_logic_vector(7 downto 0);

        beep_out  : out std_logic;
        en_out    : out std_logic_vector(7 downto 0);
        deg_out   : out std_logic_vector(7 downto 0);

        -- 把 I2C 引脚暴露到顶层，避免内部 tri-state（必须为 resolved std_logic）
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

    -- 删除内部 temp_scl/temp_sda 信号（改为顶层端口）
    -- signal temp_scl     : std_logic;
    -- signal temp_sda     : std_logic := 'Z';

    -- 控制/模式信号
    signal is_manual    : std_logic := '0'; -- '0' = Auto, '1' = Manual
    signal power_on     : std_logic := '1'; -- 开/关机（Auto 模式下由 button1 切换）

    -- Button 输出
    signal key_flag     : integer range 0 to 2 := 0; -- 0 none, 1 btn1, 2 btn2

    -- Temp module 接口
    signal temp_twice   : integer range 0 to 80 := 0; -- 定点温度（*2）
    signal temp_ena     : std_logic := '0';
    signal temp_busy    : std_logic := '0';

    -- 读周期计数（以主 clk 计数，默认主时钟 1MHz -> 0.1s = 100000 ticks）
    signal read_cnt     : integer := 0;
    constant READ_TICKS : integer := 100000; -- 0.1s @ 1MHz

    -- 等待 I2C 事务状态机
    type rstate is (R_IDLE, R_WAIT_BUSY_START, R_WAIT_BUSY_DONE);
    signal rstate_sig : rstate := R_IDLE;

    signal en_out_i     : std_logic_vector(7 downto 0);
    signal deg_out_i    : std_logic_vector(7 downto 0);
    signal matrix_en_i  : std_logic_vector(7 downto 0);
    signal matrix_R_i   : std_logic_vector(7 downto 0);
    signal matrix_G_i   : std_logic_vector(7 downto 0);
    signal beep_en_i       : std_logic;



    component Clk_Generater is
        generic (INPUT_CLK : integer := 1_000_000);
        port (
            clk       : in  std_logic;
            rst       : in  std_logic;
            clk_1khz  : out std_logic;
            clk_100hz : out std_logic
        );
    end component;

    component Button is
        port (
            clk_1khz : in  std_logic;
            rst      : in  std_logic;
            btn0     : in  std_logic;  -- 按键1
            btn2     : in  std_logic;  -- 按键2
            key_flag : out integer range 0 to 2  -- 0 none, 1 btn1, 2 btn2
        );
    end component;

    component DigitalDisplay is
        port (
            clk        : in  std_logic;
            rst        : in  std_logic;
            temp_twice : in  integer range 0 to 80; -- temp * 2 (定点表示)
            stage      : in  integer range 0 to 4;  -- 外部状态，用于第7位显示

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

            temp  : out integer range 0 to 80; -- temp * 2 (定点表示)

            scl   : out std_logic;
            sda   : inout std_logic;
            busy  : out std_logic
        );
    end component;

begin

    ----------------------------------------------------------------
    -- 实例化子模块
    ----------------------------------------------------------------
    clkgen_inst : component Clk_Generater
        generic map (INPUT_CLK => 1_000_000)
        port map (clk => clk, rst => rst, clk_1khz => clk_1khz, clk_100hz => clk_100hz);

    button_inst : component Button
        port map (
            clk_1khz => clk_1khz,
            rst      => rst,
            btn0     => button1, -- 按键1 映射到 btn0 (key_flag=1)
            btn2     => button2, -- 按键2 映射到 btn2 (key_flag=2)
            key_flag => key_flag
        );

    Display_Inst : component DigitalDisplay
        port map (
            clk        => clk,
            rst        => rst,
            temp_twice => temp_twice,
            stage      => stage,
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
            beep_en => beep_en_i, -- 关机时禁止蜂鸣器
            stage   => stage,
            beep    => beep_out
        );

    Temp_Inst : component Tempreature
        port map (
            clk   => clk,
            rst   => rst,
            ena   => temp_ena,   -- 单周期脉冲触发一次读（在 clk 域）
            button=> '0',       -- 未使用
            temp  => temp_twice,
            scl   => scl,
            sda   => sda,
            busy  => temp_busy
        );

    en_out   <= (others => '1') when power_on = '0' else en_out_i;
    deg_out  <= (others => '0') when power_on = '0' else deg_out_i;
    matrix_en<= (others => '1') when power_on = '0' else matrix_en_i;
    matrix_R <= (others => '0') when power_on = '0' else matrix_R_i;
    matrix_G <= (others => '0') when power_on = '0' else matrix_G_i;
    beep_en_i <= power_on; -- 关机时禁止蜂鸣器


    ----------------------------------------------------------------
    -- 按键处理（按键 mapping 与模式/电源控制）
    -- key_flag 是 Button 的单周期脉冲（在 clk_1khz 域）；
    -- 因为主时钟 clk 与 clk_1khz 同步（clk_1khz 来源于 clk），在 clk 域采样即可。
    ----------------------------------------------------------------
    process(clk_1khz, rst)
    begin
        if rst = '1' then
            is_manual <= '0';
            power_on  <= '1';
            manual_stage <= 0;
        elsif rising_edge(clk_1khz) then
            -- 读取 key_flag（单周期），对事件响应
            if key_flag = 2 then
                -- btn2 切换手动/自动
                if is_manual = '0' then
                    is_manual <= '1';
                else
                    is_manual <= '0';
                end if;
            elsif key_flag = 1 then
                -- btn1 在 Auto 模式为开/关机，在 Manual 模式循环切换 stage
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
        end if;
    end process;

    ----------------------------------------------------------------
    -- 周期读温度 & 计算挡位（使用主时钟 clk 做计数，默认 1MHz）
    -- 逻辑：
    --  - 当 power_on='1' 时，read_cnt 每 clk 累加，达到 READ_TICKS 后产生一次 temp_ena（单周期）
    --  - 触发后进入等 busy 上升/下降的等待，再做 calc：若为 Auto 且 power_on='1' 则根据 temp_twice 更新 stage
    --  - Manual 模式不修改 stage（仍保留由按键控制），但温度仍周期读回并显示
    ----------------------------------------------------------------
    process(clk, rst)
    begin
        if rst = '1' then
            read_cnt  <= 0;
            temp_ena  <= '0';
            rstate_sig<= R_IDLE;
        elsif rising_edge(clk) then
            temp_ena <= '0'; -- 默认单周期拉低

            case rstate_sig is
                when R_IDLE =>
                    if power_on = '1' then
                        if read_cnt < READ_TICKS - 1 then
                            read_cnt <= read_cnt + 1;
                        else
                            read_cnt <= 0;
                            temp_ena <= '1'; -- 在 clk 域产生单周期启动 Tempreature 的脉冲
                            rstate_sig <= R_WAIT_BUSY_START;
                        end if;
                    else
                        -- 关机时保持计数为 0
                        read_cnt <= 0;
                    end if;

                when R_WAIT_BUSY_START =>
                    -- 等待 busy 上升表明事务已开始
                    if temp_busy = '1' then
                        rstate_sig <= R_WAIT_BUSY_DONE;
                    end if;

                when R_WAIT_BUSY_DONE =>
                    -- 等待事务结束（busy 回到 0）
                    if temp_busy = '0' then
                        -- 读取完成：在 Auto 且开机时更新 stage
                        if is_manual = '0' and power_on = '1' then
                            -- thresholds（temp_twice 单位 = temp * 2）
                            if temp_twice < 48 then             -- <24°C
                                auto_stage <= 0;
                            elsif temp_twice < 52 then         -- [24,26)
                                auto_stage <= 1;
                            elsif temp_twice < 56 then         -- [26,28)
                                auto_stage <= 2;
                            elsif temp_twice < 60 then         -- [28,30)
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