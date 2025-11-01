
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity Temperature_I2C is
  generic (
    INPUT_CLK : integer := 1_000_000;
    I2C_CLK   : integer := 100_000
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    ena       : in  std_logic;
    addr      : in  std_logic_vector(6 downto 0);
    rw        : in  std_logic;
    data_wr   : in  std_logic_vector(7 downto 0);
    data_rd   : out std_logic_vector(7 downto 0);
    busy      : out std_logic;
    ack_error : out std_logic;
    scl       : out std_logic;
    sda       : inout std_logic;
    byte_valid: out std_logic
  );
end entity;

architecture logic of Temperature_I2C is
  constant divider : integer := (INPUT_CLK/I2C_CLK)/4;
  type machine is(ready, start, command, slv_ack1, wr, rd, slv_ack2, mstr_ack, stop);
  signal state         : machine;
  signal data_clk      : std_logic;
  signal data_clk_prev : std_logic;
  signal scl_clk       : std_logic;
  signal scl_ena       : std_logic := '0';
  signal sda_int       : std_logic := '1';
  signal sda_ena_n     : std_logic;
  signal addr_rw       : std_logic_vector(7 downto 0);
  signal data_tx       : std_logic_vector(7 downto 0);
  signal data_rx       : std_logic_vector(7 downto 0);
  signal bit_cnt       : integer range 0 to 7 := 7;
  --signal stretch       : std_logic := '0';
  signal busy_sig      : std_logic := '0';
  signal ack_error_sig : std_logic := '0';
  signal byte_valid_sig: std_logic := '0';
  signal read_count    : integer range 0 to 2 := 0;

begin
  busy      <= busy_sig;
  ack_error <= ack_error_sig;
  byte_valid<= byte_valid_sig;

  scl <= '0' when (scl_ena = '1' and scl_clk = '0') else 'Z';
  sda <= '0' when sda_ena_n = '0' else 'Z';

  
  with state select
    sda_ena_n <= data_clk_prev when start,
                 not data_clk_prev when stop,
                 sda_int when others;

  p1:process (clk, rst)
    variable count : integer range 0 to divider * 4;
  begin
    if rst = '1' then
      count := 0;
      data_clk_prev <= '0';
    elsif rising_edge(clk) then
      data_clk_prev <= data_clk;
      if (count = divider * 4 - 1) then
        count := 0;
      else
        count := count + 1;
      end if;
      case count is
        when 0 to divider - 1 =>
          scl_clk  <= '0';
          data_clk <= '0';
        when divider to divider * 2 - 1 =>
          scl_clk  <= '0';
          data_clk <= '1';
        when divider * 2 to divider * 3 - 1 =>
          scl_clk <= '1';
          data_clk <= '1';
        when others =>
          scl_clk  <= '1';
          data_clk <= '0';
      end case;
    end if;
  end process;

  p2:process (clk, rst)
  begin
    if rst = '1' then
      state     <= ready;
      busy_sig  <= '0';
      scl_ena   <= '0';
      sda_int   <= '1';
      ack_error_sig <= '0';
      bit_cnt   <= 7;
      data_rx   <= (others => '0');
      byte_valid_sig <= '0';
      read_count <= 0;
    elsif rising_edge(clk) then
      byte_valid_sig <= '0';
      if (data_clk = '1' and data_clk_prev = '0') then
        case state is
          when ready =>
            if (ena = '1') then
              busy_sig <= '1';
              addr_rw  <= addr & rw;
              data_tx  <= data_wr;
              state    <= start;
            else
              busy_sig <= '0';
              state    <= ready;
            end if;
          when start =>
            busy_sig <= '1';
            sda_int  <= addr_rw(bit_cnt);
            state    <= command;
          when command =>
            if (bit_cnt = 0) then
              sda_int <= '1';
              bit_cnt <= 7;
              state   <= slv_ack1;
            else
              bit_cnt <= bit_cnt - 1;
              sda_int <= addr_rw(bit_cnt - 1);
              state   <= command;
            end if;
          when slv_ack1 =>
            if (addr_rw(0) = '0') then
              sda_int <= data_tx(bit_cnt);
              state   <= wr;
            else
              sda_int <= '1';
              read_count <= 0;
              state   <= rd;
            end if;
          when wr =>
            if (bit_cnt = 0) then
              sda_int <= '1';
              bit_cnt <= 7;
              state   <= slv_ack2;
            else
              bit_cnt <= bit_cnt - 1;
              sda_int <= data_tx(bit_cnt - 1);
              state   <= wr;
            end if;
          when rd =>
            if (bit_cnt = 0) then
              if (read_count = 0) then
                sda_int <= '0';
              else
                sda_int <= '1';
              end if;
              byte_valid_sig <= '1';
              data_rd <= data_rx;
              read_count <= read_count + 1;
              state <= mstr_ack;
              bit_cnt <= 7;
            else
              bit_cnt <= bit_cnt - 1;
              state   <= rd;
            end if;
          when slv_ack2 =>
            if (ena = '1') then
              busy_sig <= '0';
              addr_rw <= addr & rw;
              data_tx <= data_wr;
              if (addr_rw = addr & rw) then
                sda_int <= data_wr(bit_cnt);
                state <= wr;
              else
                state <= start;
              end if;
            else
              state <= stop;
            end if;
          when mstr_ack =>
            if (read_count = 2 or ack_error_sig = '1') then
              state   <= stop;
            else
              sda_int <= '1';
              state   <= rd;
            end if;
          when stop =>
            busy_sig <= '0';
            state   <= ready;
        end case;
      elsif (data_clk = '0' and data_clk_prev = '1') then
        case state is
          when start =>
            if (scl_ena = '0') then
              scl_ena   <= '1';
              ack_error_sig <= '0';
            end if;
          when slv_ack1 =>
            if (sda /= '0' or ack_error_sig = '1') then
              ack_error_sig <= '1';
            end if;
          when rd =>
            data_rx(bit_cnt) <= sda;
          when slv_ack2 =>
            if (sda /= '0' or ack_error_sig = '1') then
              ack_error_sig <= '1';
            end if;
          when stop =>
            scl_ena <= '0';
          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

end logic;