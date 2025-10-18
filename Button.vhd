library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Button is
    port (
        clk_1khz     : in  std_logic;
        rst     : in  std_logic;
        btn0    : in  std_logic;
        btn2    : in  std_logic;
        key_flag: out integer range 0 to 2
    );
end entity Button;

architecture rtl of Button is

    -- debounce 参数（可根据需要调整）
    constant DEBOUNCE_MS : integer := 20_000; -- 20 ms

    -- 同步与消抖信号
    signal btn0_sync1, btn0_sync2 : std_logic := '0';
    signal btn2_sync1, btn2_sync2 : std_logic := '0';

    signal btn0_cnt : integer range 0 to 20_000 := 0;
    signal btn2_cnt : integer range 0 to 20_000 := 0;

    signal deb0, deb2       : std_logic := '0'; -- 稳定后的按键状态
    signal prev_deb0, prev_deb2 : std_logic := '0';

    signal key_flag_reg : integer range 0 to 2 := 0;

begin

    -- 两级同步，避免亚稳态（将异步按键信号安全同步到 clk_1khz 域）
    -- 说明：第一拍采样异步输入，第二拍采样第一拍输出，从而大幅降低亚稳态传播风险。
    -- 如果按键为低有效（按下为 '0'），可把下面 btnX_sync1 <= btnX 改为 btnX_sync1 <= not btnX
    sync_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                btn0_sync1 <= '0';
                btn0_sync2 <= '0';
                btn2_sync1 <= '0';
                btn2_sync2 <= '0';
            else
                -- 一级采样：把异步输入采到第一级触发器
                btn0_sync1 <= btn0;     -- 若低有效： btn0_sync1 <= not btn0;
                btn2_sync1 <= btn2;     -- 若低有效： btn2_sync1 <= not btn2;

                -- 二级采样：减小亚稳态影响，作为后续消抖的稳定采样信号
                btn0_sync2 <= btn0_sync1;
                btn2_sync2 <= btn2_sync1;
            end if;
        end if;
    end process sync_proc;

    -- 消抖：输入在 DEBOUNCE_MS 毫秒内稳定后才改变 debX
    debounce_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                btn0_cnt <= 0;
                btn2_cnt <= 0;
                deb0 <= '0';
                deb2 <= '0';
            else
                -- btn0
                if btn0_sync2 = deb0 then
                    btn0_cnt <= 0;
                else
                    if btn0_cnt < DEBOUNCE_MS then
                        btn0_cnt <= btn0_cnt + 1;
                    end if;
                    if btn0_cnt >= DEBOUNCE_MS then
                        deb0 <= btn0_sync2;
                        btn0_cnt <= 0;
                    end if;
                end if;

                -- btn2
                if btn2_sync2 = deb2 then
                    btn2_cnt <= 0;
                else
                    if btn2_cnt < DEBOUNCE_MS then
                        btn2_cnt <= btn2_cnt + 1;
                    end if;
                    if btn2_cnt >= DEBOUNCE_MS then
                        deb2 <= btn2_sync2;
                        btn2_cnt <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process debounce_proc;

    -- 产生按键上升沿脉冲到 key_flag（优先 btn0 -> 1，其次 btn2 -> 2）
    keyflag_proc: process(clk_1khz)
    begin
        if rising_edge(clk_1khz) then
            if rst = '1' then
                prev_deb0 <= '0';
                prev_deb2 <= '0';
                key_flag_reg <= 0;
            else
                key_flag_reg <= 0;
                if (deb0 = '1' and prev_deb0 = '0') then
                    key_flag_reg <= 1;
                elsif (deb2 = '1' and prev_deb2 = '0') then
                    key_flag_reg <= 2;
                end if;

                prev_deb0 <= deb0;
                prev_deb2 <= deb2;
            end if;
        end if;
    end process keyflag_proc;

    key_flag <= key_flag_reg;

end architecture;

