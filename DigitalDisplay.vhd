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
    signal deg_index : integer range 0 to 12 := 0;
    
    -- 解码用临时信号
    signal temp_tens  : integer range 0 to 8 := 0; -- 十位（0..8）
    signal temp_units : integer range 0 to 9 := 0; -- 个位
    signal tempdot    : std_logic := '0';          -- 是否有 0.5（小数点）
    
begin

    -- 扫描计数器
    process(clk, rst)
    begin
        if rst = '1' then
            en_index <= 0;
        elsif rising_edge(clk) then
            en_index <= (en_index + 1) mod 8;
        end if;
    end process;

    -- 输出位选（低有效）
    process(en_index)
    begin
        en_out <= (others => '1');
        en_out(en_index) <= '0';
    end process;

    -- 从 temp_twice 解码出十位/个位/半位标志（组合逻辑）
    process(temp_twice)
        variable v : integer;
    begin
        v := temp_twice;
        if v < 0 then
            v := 0;
        elsif v > 80 then
            v := 80;
        end if;
        temp_tens  <= v / 10;
        temp_units <= v mod 10;
        if (v mod 2) = 1 then
            tempdot <= '1';
        else
            tempdot <= '0';
        end if;
    end process;

    -- 根据当前位选择要显示的字符索引（组合逻辑）
    process(en_index, temp_tens, temp_units, tempdot, stage)
    begin 
        case en_index is
            when 0 => deg_index <= temp_tens;   -- 十位
            when 1 => deg_index <= temp_units;  -- 个位
            when 2 => 
                if tempdot = '1' then
                    deg_index <= 12; -- dp-only
                else
                    deg_index <= 0;  -- 空白或 0 根据需求
                end if;
            when 3 => deg_index <= 10;  -- C
            when 4 => deg_index <= 11;  -- °
            when 5 => deg_index <= 0;   -- 保留空白
            when 6 => deg_index <= 0;   -- 保留空白
            when 7 => 
                if stage >= 0 and stage <= 4 then
                    deg_index <= stage; -- 用 stage 显示 0..4
                else
                    deg_index <= 0;
                end if;
            when others => deg_index <= 0;
        end case;
    end process;

    -- 7 段和小数点编码（8 位，MSB 假定为 DP）
    with deg_index select
        deg_out <= "00111111" when 0,  -- 0
                   "00000110" when 1,  -- 1
                   "01011011" when 2,  -- 2
                   "01001111" when 3,  -- 3
                   "01100110" when 4,  -- 4
                   "01101101" when 5,  -- 5
                   "01111101" when 6,  -- 6
                   "00000111" when 7,  -- 7
                   "01111111" when 8,  -- 8
                   "01101111" when 9,  -- 9
                   "01110111" when 10, -- C
                   "00111001" when 11, -- °
                   "10000000" when 12, -- dp-only（仅小数点）
                   "00000000" when others; -- 空白 / 默认
    
end architecture rtl;