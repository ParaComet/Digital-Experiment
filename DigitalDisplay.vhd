library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity DigitalDisplay is
    port (
        clk          : in  std_logic;
        rst          : in  std_logic;
        dist_int     : in  integer range 0 to 999; -- dist * 2 (�����ʾ)
        stage        : in  integer range 0 to 8;  -- ˮλ״̬�����ڵ�7λ��ʾ
        level        : in  integer range 0 to 4;   -- �ͷŵȼ������ڵ�6λ��ʾ

        en_out       : out std_logic_vector(7 downto 0);
        deg_out      : out std_logic_vector(7 downto 0)
    );
end entity DigitalDisplay;

architecture rtl of DigitalDisplay is 

    signal en_index : integer range 0 to 7 := 0;
    signal deg_index : integer range 0 to 11 := 0;
    signal stage_reg : integer range 0 to 4 := 0;
    
    signal dist_1     : integer range 0 to 9 := 0; -- ��λ
    signal dist_2     : integer range 0 to 9 := 0; -- ʮλ
    signal dist_3     : integer range 0 to 9 := 0; -- ��λ
    signal dp_now     : std_logic := '0';          -- ��ǰɨ��λ�Ƿ���ʾС����

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
    process(dist_int)
        variable v : integer range 0 to 999 := 0;
    begin
        v := dist_int;
        dist_3  <= v / 100;
        dist_2  <= (v / 10) mod 10;
        dist_1  <= v mod 10;
    end process;

    -- ���ݵ�ǰλѡ��Ҫ��ʾ���ַ�����������߼���
    process(en_index, dist_1, dist_2, dist_3)
    begin
        case en_index is
            when 0 => 
                if stage_reg < 5 then
                    deg_index <= stage_reg;  -- ��ʾˮλ�׶� 0-4
                else
                    deg_index <= 11;  -- ��ʾ�հ�
                end if;
            when 1 => deg_index <= dist_3;   -- ��λ
            when 2 => 
                deg_index <= dist_2;  -- ʮλ
            when 3 => 
                deg_index <= dist_1;  -- ��λ
            when 6 => deg_index <= level;  -- ��ʾ 5 �� �հ�
            when others => deg_index <= 11;
        end case;
    end process;

    -- 7 �κ�С������루8 λ��bit7 = DP��
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
                                    "0000000" when others; -- �հ� / Ĭ��
    
    with stage select
        stage_reg <= 1 when 0 | 1 | 2 | 3,
                     2 when 4 | 5,
                     3 when 6 | 7,
                     4 when 8;
                     -- ��ʾ 5 �� �հ�

    deg_out_reg(7) <= dp_now; -- С���㣨���� dp_now ���ƣ�
    deg_out <= deg_out_reg;

end architecture rtl;