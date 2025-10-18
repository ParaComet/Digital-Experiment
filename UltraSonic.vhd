library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UltraSonic is
    port (
        clk         : in  std_logic;  -- 50 MHz 时钟
        rst         : in  std_logic;
        start       : in  std_logic;  -- 外部使能脉冲（检测上升沿，启动一次测量）
        echo        : in  std_logic;  -- HC-SR04 ECHO 输入
        trig        : out std_logic;  -- HC-SR04 TRIG 输出（产生 >=10us 脉冲）
        busy        : out std_logic;  -- 测量期间为 '1'
        distance_mm : out integer range 0 to 1000; -- 测量结果，单位 mm（超过范围返回 5000）
        valid       : out std_logic   -- 测量完成单周期有效脉冲
    );
end entity;

architecture rtl of UltraSonic is

    type state_t is (IDLE, TRIG_PULSE, WAIT_ECHO, MEASURE, DONE);
    signal state       : state_t := IDLE;
    signal start_prev  : std_logic := '0';

    -- 参数：50MHz 时钟
    constant CLK_FREQ           : integer := 1_000_000;
    constant TRIG_US            : integer := 10;  -- 10 us trigger
    constant TRIG_CYCLES        : integer := (CLK_FREQ / 1_000_000) * TRIG_US; -- 500 cycles

    -- 最大测距 4000mm 对应回波时间约 23.53 ms -> 1_176_470 cycles @50MHz
    constant MAX_ECHO_CYCLES    : integer := 50_000; -- 安全超时时间（约30ms）

    signal trig_cnt    : integer range 0 to TRIG_CYCLES := 0;
    signal wait_cnt    : integer range 0 to MAX_ECHO_CYCLES := 0;
    signal echo_cnt    : integer range 0 to MAX_ECHO_CYCLES := 0;

    signal trig_r      : std_logic := '0';
    signal busy_r      : std_logic := '0';
    signal dist_r      : integer range 0 to 1000 := 0;
    signal valid_r     : std_logic := '0';

begin

    trig        <= trig_r;
    busy        <= busy_r;
    distance_mm <= dist_r;
    valid       <= valid_r;

    process(clk, rst)
        variable tmp_mm   : integer;
        variable prod     : integer;
    begin
        if rst = '1' then
            state      <= IDLE;
            start_prev <= '0';
            trig_r     <= '0';
            busy_r     <= '0';
            trig_cnt   <= 0;
            wait_cnt   <= 0;
            echo_cnt   <= 0;
            dist_r     <= 0;
            valid_r    <= '0';
        elsif rising_edge(clk) then
            -- default: clear one-cycle flags
            start_prev <= start;

            case state is
                when IDLE =>
                    trig_r <= '0';
                    busy_r <= '0';
                    valid_r <= '0';
                    if (start = '1' and start_prev = '0') then  -- 上升沿触发一次测量
                        busy_r <= '1';
                        trig_r <= '1';
                        trig_cnt <= 0;
                        state <= TRIG_PULSE;
                    end if;

                when TRIG_PULSE =>
                    -- 产生 >=10us 的 TRIG 高电平
                    if trig_cnt < TRIG_CYCLES - 1 then
                        trig_cnt <= trig_cnt + 1;
                    else
                        trig_r <= '0';
                        trig_cnt <= 0;
                        wait_cnt <= 0;
                        state <= WAIT_ECHO;
                    end if;

                when WAIT_ECHO =>
                    -- 等待 ECHO 上升，超时则给出错误（dist=5000，valid=0）
                    if echo = '1' then
                        echo_cnt <= 1;
                        state <= MEASURE;
                    else
                        if wait_cnt < MAX_ECHO_CYCLES then
                            wait_cnt <= wait_cnt + 1;
                        else
                            -- 超时未收到回波
                            busy_r <= '0';
                            dist_r <= 0;  -- 超限标志
                            valid_r <= '1';  -- 可以视为测量完成但结果为超时
                            state <= DONE;
                        end if;
                    end if;

                when MEASURE =>
                    -- 计数 ECHO 高电平时间，直到 ECHO 下降或超时
                    if echo = '1' then
                        if echo_cnt < MAX_ECHO_CYCLES then
                            echo_cnt <= echo_cnt + 1;
                        else
                            -- 超时（防止无限计数）
                            busy_r <= '0';
                            dist_r <= 0;
                            valid_r <= '1';
                            state <= DONE;
                        end if;
                    else
                        -- ECHO 结束，计算距离（mm）
                        -- 计算方法：distance_mm = echo_time_s * 340000 / 2
                        -- echo_time_s = echo_cnt * (1/50e6) -> distance_mm = echo_cnt * 34 / 10
                        prod := echo_cnt * 17;
                        tmp_mm := prod / 100;
                        if tmp_mm > 999 then
                            dist_r <= 0;
                        elsif tmp_mm < 0 then
                            dist_r <= 999;
                        else
                            dist_r <= 1000-tmp_mm;
                        end if;
                        busy_r <= '0';
                        valid_r <= '1';
                        state <= DONE;
                    end if;

                when DONE =>
                    -- 未使用的占位状态（保留）
                    state <= IDLE;
                    echo_cnt <= 0;
                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;

