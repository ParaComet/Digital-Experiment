library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DigitalDisplay is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        temp_int     : in  integer range 0 to 63; -- temp * 2 (定点表示)
        temp_dot     : in  std_logic;
        stage        : in  integer range 0 to 4;  -- 外部状态，用于第7位显示
        is_manual    : in  integer range 0 to 1;              -- 是否手动模式，用于第6位显示

        time_ten     : in integer range 0 to 9;
        time_int     : in integer range 0 to 9;
        time_start   : in std_logic; 
        time_show    : in std_logic;
        time_fi      : out std_logic := '0';

        en_out       : out std_logic_vector(7 downto 0);
        deg_out      : out std_logic_vector(7 downto 0)
    );
end entity DigitalDisplay;

architecture rtl of DigitalDisplay is 

    signal en_index : integer range 0 to 7 := 0;
    signal deg_index : integer range 0 to 11 := 0;
    signal time_count : integer range 0 to 1_000_000 := 0;
    
    signal temp_tens  : integer range 0 to 8 := 0; -- 十位
    signal temp_units : integer range 0 to 9 := 0; -- 个位
    signal dp_now     : std_logic := '0';          -- 当前扫描位是否显示小数点

    signal time_int_r : integer range 0 to 9 := 0;
    signal time_ten_r : integer range 0 to 9 := 0;

    signal deg_out_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal time_fi_r : std_logic := '0';

begin

    time_fi <= time_fi_r;
    p1:process(clk, rst)
    begin
        if rst = '1' then
            en_index <= 0;
            time_fi_r <= '0';
            time_int_r <= 0;
            time_ten_r <= 0;
        elsif rising_edge(clk) then
            en_index <= (en_index + 1) mod 8;
            if time_start = '1' then

                if time_count = 1_000_000 - 1 then
                    time_count <= 0;
                    if time_int_r = 0 then
                        if time_ten_r = 0 then
                            time_fi_r <= '1';
                        else 
                            time_ten_r <= time_ten_r - 1;
                            time_int_r <= 9;
                        end if;
                    else
                        time_int_r <= time_int_r - 1; 
                    end if;  

                else
                    time_count <= time_count + 1;
                end if;
            else
                time_int_r <= time_int;
                time_ten_r <= time_ten;
                time_count <= 0;
                time_fi_r <= '0';
            end if;
        end if;
    end process;

    p2:process(en_index)
    begin
        en_out <= (others => '1');
        en_out(en_index) <= '0';
    end process;
    p3:process(temp_int)
        variable v : integer range 0 to 63;
    begin
        v := temp_int;
        temp_tens  <= v / 10;
        temp_units <= v mod 10;
    end process;

    -- 根据当前位选择要显示的字符索引（组合逻辑）
    p4:process(en_index, temp_tens, temp_units, temp_dot, stage)
    begin 
        dp_now <= '0';
        case en_index is
            when 0 => deg_index <= temp_tens;   -- 十位
            when 1 => 
                deg_index <= temp_units;  -- 个位
                dp_now <= '1';
            when 2 => 
                if temp_dot = '1' then
                    deg_index <= 5; -- 显示 5 (表示 .5)
                else
                    deg_index <= 0; -- 显示 0
                end if;
            when 3 => deg_index <= 10;  -- C
            when 4 => 
                if time_show = '1' then
                    deg_index <= time_ten_r;
                else
                    deg_index <= 11;
                end if;
                --deg_index <= time_ten_r when time_show = '1' else 11;
            when 5 =>
                if time_show = '1' then
                    deg_index <= time_int_r;
                else
                    deg_index <= is_manual;
                end if;
                --deg_index <= time_int_r when time_show = '1' else is_manual;  -- 显示 5 或 空白
            when 6 =>
                if time_show = '1' then
                    deg_index <= is_manual;
                else
                    deg_index <= 11;
                end if;
                --deg_index <= is_manual when time_show = '1' else 11;   
            when 7 => 
                if stage >= 0 and stage <= 4 then
                    deg_index <= stage; -- 用 stage 显示 0..4
                else
                    deg_index <= 0;
                end if;
            when others => deg_index <= 0;
        end case;
    end process;

    -- 7 段和小数点编码（8 位，bit7 = DP）
    with deg_index select
        deg_out_reg(6 downto 0) <=  "0111111" when 0,  -- 0
                                    "0000110" when 1,  -- 1
                                    "1011011" when 2,  -- 2
                                    "1001111" when 3,  -- 3
                                    "1100110" when 4,  -- 4
                                    "1101101" when 5,  -- 5
                                    "1111101" when 6,  -- 6
                                    "0000111" when 7,  -- 7
                                    "1111111" when 8,  -- 8
                                    "1101111" when 9,  -- 9
                                    "0111001" when 10, -- C
                                    "0000000" when others; -- 空白 / 默认

    deg_out_reg(7) <= dp_now; -- 小数点（仅由 dp_now 控制）
    deg_out <= deg_out_reg;

end architecture rtl;