library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DigitalDisplay is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        temp_twice   : in  integer range 0 to 80; -- temp * 2 (定点表示)
        stage        : in  integer range 0 to 4;  -- 外部状态，用于第7位显示

        en_out       : out std_logic_vector(7 downto 0);
        deg_out      : out std_logic_vector(7 downto 0)
    );
end entity DigitalDisplay;

architecture rtl of DigitalDisplay is 

    signal en_index : integer range 0 to 7 := 0;
    signal deg_index : integer range 0 to 11 := 0;
    
    signal temp_tens  : integer range 0 to 8 := 0; -- 十位（0..8）
    signal temp_units : integer range 0 to 9 := 0; -- 个位
    signal tempdot    : std_logic := '0';          -- 是否有 0.5（小数点）
    signal dp_now     : std_logic := '0';          -- 当前扫描位是否显示小数点

    signal deg_out_reg : std_logic_vector(7 downto 0) := (others => '0');

begin

    process(clk, rst)
    begin
        if rst = '1' then
            en_index <= 0;
        elsif rising_edge(clk) then
            en_index <= (en_index + 1) mod 8;
        end if;
    end process;

    process(en_index)
    begin
        en_out <= (others => '1');
        en_out(en_index) <= '0';
    end process;
    process(temp_twice)
        variable v : integer range -1 to 81;
        variable integer_temp : integer range 0 to 40;
    begin
        v := temp_twice;
        if v < 0 then
            v := 0;
        elsif v > 80 then
            v := 80;
        end if;
        integer_temp := v / 2; -- 恢复实际温度（向下取整）
        temp_tens  <= integer_temp / 10;
        temp_units <= integer_temp mod 10;
        if (v mod 2) = 1 then
            tempdot <= '1';
        else
            tempdot <= '0';
        end if;
    end process;

    -- 根据当前位选择要显示的字符索引（组合逻辑）
    process(en_index, temp_tens, temp_units, tempdot, stage)
    begin 
        dp_now <= '0';
        case en_index is
            when 0 => deg_index <= temp_tens;   -- 十位
            when 1 => 
                deg_index <= temp_units;  -- 个位
                dp_now <= '1';
            when 2 => 
                if tempdot = '1' then
                    deg_index <= 5; -- 显示 5 (表示 .5)
                else
                    deg_index <= 0; -- 显示 0
                end if;
            when 3 => deg_index <= 10;  -- C
            when 4 => deg_index <= 0;
            when 5 => deg_index <= 0;   
            when 6 => deg_index <= 0;   
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