-- =============================================================================
-- fp_add.vhd
-- FP add/subtract functional unit (FADD.S / FSUB.S).
--
-- 2-stage pipeline: stage 1 computes the IEEE 754 result; stage 2 registers
-- it to the output.  Handles both OP_FADD_S (op_i = 23) and OP_FSUB_S
-- (op_i = 24) by toggling the sign bit of rs2 before the addition.
-- Behavioral floating-point arithmetic via VHDL 'real' - simulation only.
--
-- Port map (matches the SystemVerilog FU convention):
--   clk, rst_n  : standard clock / active-low reset
--   valid_i     : input operands valid this cycle
--   op_i        : 6-bit opcode (23 = FADD.S, 24 = FSUB.S)
--   tag_i       : 4-bit ROB tag echoed to CDB
--   rs1_i/rs2_i : IEEE 754 single-precision source operands
--   valid_o     : result valid (2 cycles after valid_i)
--   tag_o       : ROB tag forwarded with result
--   result_o    : IEEE 754 single-precision sum/difference
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity fp_add is
    port (
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        valid_i  : in  std_logic;
        op_i     : in  std_logic_vector(5 downto 0);
        tag_i    : in  std_logic_vector(3 downto 0);
        rs1_i    : in  std_logic_vector(31 downto 0);
        rs2_i    : in  std_logic_vector(31 downto 0);
        valid_o  : out std_logic;
        tag_o    : out std_logic_vector(3 downto 0);
        result_o : out std_logic_vector(31 downto 0)
    );
end entity fp_add;

architecture behavioral of fp_add is

    constant OP_FSUB_S : std_logic_vector(5 downto 0) := std_logic_vector(to_unsigned(24, 6));

    -- Pipeline stage 1 registers
    signal s1_valid  : std_logic;
    signal s1_tag    : std_logic_vector(3 downto 0);
    signal s1_result : std_logic_vector(31 downto 0);

    -- Convert IEEE 754 single-precision bits to VHDL real.
    function slv_to_real(slv : std_logic_vector(31 downto 0)) return real is
        variable exp  : integer;
        variable mant : real;
    begin
        if slv(30 downto 23) = "00000000" then
            mant := real(to_integer(unsigned(slv(22 downto 0)))) / (2.0 ** 23);
            exp  := -126;
        else
            exp  := to_integer(unsigned(slv(30 downto 23))) - 127;
            mant := 1.0 + real(to_integer(unsigned(slv(22 downto 0)))) / (2.0 ** 23);
        end if;
        if slv(31) = '1' then
            return -mant * (2.0 ** exp);
        else
            return  mant * (2.0 ** exp);
        end if;
    end function;

    -- Convert VHDL real to IEEE 754 single-precision bits.
    function real_to_slv(r : real) return std_logic_vector is
        variable sign     : std_logic;
        variable exp      : integer;
        variable mant     : real;
        variable mant_int : integer;
        variable result   : std_logic_vector(31 downto 0);
    begin
        if r = 0.0 then
            return (others => '0');
        end if;
        if r < 0.0 then sign := '1'; mant := -r;
        else              sign := '0'; mant :=  r;
        end if;
        exp := 0;
        while mant >= 2.0 loop mant := mant / 2.0; exp := exp + 1; end loop;
        while mant < 1.0 loop mant := mant * 2.0; exp := exp - 1; end loop;
        mant      := mant - 1.0;
        mant_int  := integer(floor(mant * (2.0 ** 23)));
        result(31)           := sign;
        result(30 downto 23) := std_logic_vector(to_unsigned(exp + 127, 8));
        result(22 downto 0)  := std_logic_vector(to_unsigned(mant_int, 23));
        return result;
    end function;

begin

    process(clk, rst_n)
        variable a, b, res : real;
        variable rs2_eff   : std_logic_vector(31 downto 0);
    begin
        if rst_n = '0' then
            s1_valid  <= '0';
            s1_tag    <= (others => '0');
            s1_result <= (others => '0');
            valid_o   <= '0';
            tag_o     <= (others => '0');
            result_o  <= (others => '0');
        elsif rising_edge(clk) then
            -- Stage 2: propagate stage-1 to output
            valid_o  <= s1_valid;
            tag_o    <= s1_tag;
            result_o <= s1_result;

            -- Stage 1: compute
            s1_valid <= valid_i;
            s1_tag   <= tag_i;
            if valid_i = '1' then
                rs2_eff    := rs2_i;
                -- FSUB: negate rs2 by flipping sign bit
                if op_i = OP_FSUB_S then
                    rs2_eff(31) := not rs2_i(31);
                end if;
                a         := slv_to_real(rs1_i);
                b         := slv_to_real(rs2_eff);
                res       := a + b;
                s1_result <= real_to_slv(res);
            else
                s1_result <= (others => '0');
            end if;
        end if;
    end process;

end architecture behavioral;
