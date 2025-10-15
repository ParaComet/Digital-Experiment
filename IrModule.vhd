
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Ir_Module is
    port(
        clk_8khz        : in  std_logic;    -- 系统时钟（8kHz）
        rst_n      : in  std_logic;    -- 低有效复位
        remote_in  : in  std_logic;    -- 红外接收输入
        repeat_en  : out std_logic;    -- 重复码有效信号
        data_en    : out std_logic;    -- 数据有效信号
        data       : out std_logic_vector (7 downto 0)  -- 红外控制码
    );
end entity;

architecture rtl of Ir_Module is
    -- 状态编码
    type state_t is (IDLE, START_LOW_9MS, START_JUDGE, REC_DATA, REPEAT_CODE);
    signal cur_state  : state_t := IDLE;
    signal next_state : state_t := IDLE;


    -- 对输入采样以检测边沿
    signal remote_in_d0 : std_logic := '0';
    signal remote_in_d1 : std_logic := '0';

    -- 时间计数（以 div_clk 为周期，周期 = 0.125ms）
    signal time_cnt      : unsigned(7 downto 0) := (others => '0');
    signal time_cnt_clr  : std_logic := '0';
    signal time_done     : std_logic := '0';
    signal error_en      : std_logic := '0';
    signal judge_flag    : std_logic := '0'; -- 0: 同步码 1: 重复码

    signal data_temp     : unsigned(15 downto 0) := (others => '0');
    signal data_cnt      : unsigned(5 downto 0) := (others => '0');

    -- internal outputs
    signal repeat_en_s : std_logic := '0';
    signal data_en_s   : std_logic := '0';
    signal data_s      : std_logic_vector(7 downto 0) := (others => '0');

    -- edges
    signal ir_pos : std_logic;
    signal ir_neg : std_logic;

begin
    -- map outputs
    repeat_en <= repeat_en_s;
    data_en   <= data_en_s;
    data      <= data_s;

    ir_pos <= (not remote_in_d1) and remote_in_d0;
    ir_neg <= remote_in_d1 and (not remote_in_d0);


    -- time counter（在 clk_8khz 上升沿计数）
    process(clk_8khz, rst_n)
    begin
        if rst_n = '1' then
            time_cnt <= (others => '0');
        elsif rising_edge(clk_8khz) then
            if time_cnt_clr = '1' then
                time_cnt <= (others => '0');
            else
                time_cnt <= time_cnt + 1;
            end if;
        end if;
    end process;

    -- remote_in 延时打拍，基于 clk_8khz
    process(clk_8khz, rst_n)
    begin
        if rst_n = '1' then
            remote_in_d0 <= '0';
            remote_in_d1 <= '0';
        elsif rising_edge(clk_8khz) then
            remote_in_d0 <= remote_in;
            remote_in_d1 <= remote_in_d0;
        end if;
    end process;

    -- 状态寄存（同步到 div_clk）
    process(clk_8khz, rst_n)
    begin
        if rst_n = '1' then
            cur_state <= IDLE;
        elsif rising_edge(clk_8khz) then
            cur_state <= next_state;
        end if;
    end process;

    -- 组合下一个状态逻辑
    process(cur_state, remote_in_d0, time_done, error_en, judge_flag, ir_pos, ir_neg, data_cnt)
    begin
        next_state <= IDLE;
        case cur_state is
            when IDLE =>
                if remote_in_d0 = '0' then
                    next_state <= START_LOW_9MS;
                else
                    next_state <= IDLE;
                end if;
            when START_LOW_9MS =>
                if time_done = '1' then
                    next_state <= START_JUDGE;
                elsif error_en = '1' then
                    next_state <= IDLE;
                else
                    next_state <= START_LOW_9MS;
                end if;
            when START_JUDGE =>
                if time_done = '1' then
                    if judge_flag = '0' then
                        next_state <= REC_DATA;
                    else
                        next_state <= REPEAT_CODE;
                    end if;
                elsif error_en = '1' then
                    next_state <= IDLE;
                else
                    next_state <= START_JUDGE;
                end if;
            when REC_DATA =>
                if ir_pos = '1' and data_cnt = to_unsigned(32, data_cnt'length) then
                    next_state <= IDLE;
                else
                    next_state <= REC_DATA;
                end if;
            when REPEAT_CODE =>
                if ir_pos = '1' then
                    next_state <= IDLE;
                else
                    next_state <= REPEAT_CODE;
                end if;
            when others =>
                next_state <= IDLE;
        end case;
    end process;

    -- 主状态机：行为在 clk_8khz 上更新
    process(clk_8khz, rst_n)
    begin
        if rst_n = '1' then
            time_cnt_clr <= '0';
            time_done <= '0';
            error_en <= '0';
            judge_flag <= '0';
            data_en_s <= '0';
            data_s <= (others => '0');
            repeat_en_s <= '0';
            data_cnt <= (others => '0');
            data_temp <= (others => '0');
        elsif rising_edge(clk_8khz) then
            -- 默认信号
            time_cnt_clr <= '0';
            time_done <= '0';
            error_en <= '0';
            repeat_en_s <= '0';
            data_en_s <= '0';

            case cur_state is
                when IDLE =>
                    time_cnt_clr <= '1';
                    if remote_in_d0 = '0' then
                        time_cnt_clr <= '0';
                    end if;

                when START_LOW_9MS =>
                    -- 9ms: 9/0.125 = 72;
                    if ir_pos = '1' then
                        time_cnt_clr <= '1';
                        if time_cnt >= to_unsigned(69, time_cnt'length) and time_cnt <= to_unsigned(75, time_cnt'length) then
                            time_done <= '1';
                        else
                            error_en <= '1';
                        end if;
                    end if;

                when START_JUDGE =>
                    if ir_neg = '1' then
                        time_cnt_clr <= '1';
                        -- 重复码高电平 2.25ms -> 18 (range 15..20)
                        if time_cnt >= to_unsigned(15, time_cnt'length) and time_cnt <= to_unsigned(20, time_cnt'length) then
                            time_done <= '1';
                            judge_flag <= '1';
                        -- 同步码高电平 4.5ms -> 36 (range 33..38)
                        elsif time_cnt >= to_unsigned(33, time_cnt'length) and time_cnt <= to_unsigned(38, time_cnt'length) then
                            time_done <= '1';
                            judge_flag <= '0';
                        else
                            error_en <= '1';
                        end if;
                    end if;

                when REC_DATA =>
                    if ir_pos = '1' then
                        time_cnt_clr <= '1';
                        if data_cnt = to_unsigned(32, data_cnt'length) then
                            data_en_s <= '1';
                            data_cnt <= (others => '0');
                            data_temp <= (others => '0');
                            -- 校验控制码与反码，低 8 位为数据，高 8 位为反码
                            if std_logic_vector(data_temp(7 downto 0)) = std_logic_vector(not data_temp(15 downto 8)) then
                                data_s <= std_logic_vector(data_temp(7 downto 0));
                            end if;
                        end if;
                    elsif ir_neg = '1' then
                        time_cnt_clr <= '1';
                        data_cnt <= data_cnt + 1;
                        -- 解析数据位：当处于第 16 至 31 位为控制码与反码
                        if data_cnt >= to_unsigned(16, data_cnt'length) and data_cnt <= to_unsigned(31, data_cnt'length) then
                            -- 0: 0.565ms -> ~4.52 (range 2..6 in Verilog)
                            if time_cnt >= to_unsigned(2, time_cnt'length) and time_cnt <= to_unsigned(6, time_cnt'length) then
                                data_temp <= '0' & data_temp(15 downto 1); -- 右移并插入 0
                            -- 1: 1.69ms -> ~13.52 (range 10..15)
                            elsif time_cnt >= to_unsigned(10, time_cnt'length) and time_cnt <= to_unsigned(15, time_cnt'length) then
                                data_temp <= '1' & data_temp(15 downto 1); -- 右移并插入 1
                            end if;
                        end if;
                    end if;

                when REPEAT_CODE =>
                    if ir_pos = '1' then
                        time_cnt_clr <= '1';
                        repeat_en_s <= '1';
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;

end architecture;
