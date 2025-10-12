library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UltraSonic is
    port (
        clk         : in  std_logic;  -- 50 MHz ʱ��
        rst         : in  std_logic;
        start       : in  std_logic;  -- �ⲿʹ�����壨��������أ�����һ�β�����
        echo        : in  std_logic;  -- HC-SR04 ECHO ����
        trig        : out std_logic;  -- HC-SR04 TRIG ��������� >=10us ���壩
        busy        : out std_logic;  -- �����ڼ�Ϊ '1'
        distance_mm : out integer range 0 to 5000; -- �����������λ mm��������Χ���� 5000��
        valid       : out std_logic   -- ������ɵ�������Ч����
    );
end entity;

architecture rtl of UltraSonic is

    type state_t is (IDLE, TRIG_PULSE, WAIT_ECHO, MEASURE, DONE);
    signal state       : state_t := IDLE;
    signal start_prev  : std_logic := '0';

    -- ������50MHz ʱ��
    constant CLK_FREQ           : integer := 50000000;
    constant TRIG_US            : integer := 10;  -- 10 us trigger
    constant TRIG_CYCLES        : integer := (CLK_FREQ / 1000000) * TRIG_US; -- 500 cycles

    -- ����� 4000mm ��Ӧ�ز�ʱ��Լ 23.53 ms -> 1_176_470 cycles @50MHz
    constant MAX_ECHO_CYCLES    : integer := 1500000; -- ��ȫ��ʱʱ�䣨Լ30ms��

    signal trig_cnt    : integer range 0 to TRIG_CYCLES := 0;
    signal wait_cnt    : integer range 0 to MAX_ECHO_CYCLES := 0;
    signal echo_cnt    : integer range 0 to MAX_ECHO_CYCLES := 0;

    signal trig_r      : std_logic := '0';
    signal busy_r      : std_logic := '0';
    signal dist_r      : integer range 0 to 5000 := 0;
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
            valid_r <= '0';
            start_prev <= start;

            case state is
                when IDLE =>
                    trig_r <= '0';
                    busy_r <= '0';
                    trig_cnt <= 0;
                    wait_cnt <= 0;
                    echo_cnt <= 0;
                    if (start = '1' and start_prev = '0') then  -- �����ش���һ�β���
                        busy_r <= '1';
                        trig_r <= '1';
                        trig_cnt <= 0;
                        state <= TRIG_PULSE;
                    end if;

                when TRIG_PULSE =>
                    -- ���� >=10us �� TRIG �ߵ�ƽ
                    if trig_cnt < TRIG_CYCLES - 1 then
                        trig_cnt <= trig_cnt + 1;
                    else
                        trig_r <= '0';
                        wait_cnt <= 0;
                        state <= WAIT_ECHO;
                    end if;

                when WAIT_ECHO =>
                    -- �ȴ� ECHO ��������ʱ���������dist=5000��valid=0��
                    if echo = '1' then
                        echo_cnt <= 0;
                        state <= MEASURE;
                    else
                        if wait_cnt < MAX_ECHO_CYCLES then
                            wait_cnt <= wait_cnt + 1;
                        else
                            -- ��ʱδ�յ��ز�
                            busy_r <= '0';
                            dist_r <= 5000;  -- ���ޱ�־
                            valid_r <= '1';  -- ������Ϊ������ɵ����Ϊ��ʱ
                            state <= IDLE;
                        end if;
                    end if;

                when MEASURE =>
                    -- ���� ECHO �ߵ�ƽʱ�䣬ֱ�� ECHO �½���ʱ
                    if echo = '1' then
                        if echo_cnt < MAX_ECHO_CYCLES then
                            echo_cnt <= echo_cnt + 1;
                        else
                            -- ��ʱ����ֹ���޼�����
                            busy_r <= '0';
                            dist_r <= 5000;
                            valid_r <= '1';
                            state <= IDLE;
                        end if;
                    else
                        -- ECHO ������������루mm��
                        -- ���㷽����distance_mm = echo_time_s * 340000 / 2
                        -- echo_time_s = echo_cnt * (1/50e6) -> distance_mm = echo_cnt * 34 / 10
                        prod := echo_cnt * 34;
                        tmp_mm := prod / 10;
                        if tmp_mm > 5000 then
                            dist_r <= 999;
                        elsif tmp_mm < 0 then
                            dist_r <= 0;
                        else
                            dist_r <= tmp_mm;
                        end if;
                        busy_r <= '0';
                        valid_r <= '1';
                        state <= IDLE;
                    end if;

                when DONE =>
                    -- δʹ�õ�ռλ״̬��������
                    state <= IDLE;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;

