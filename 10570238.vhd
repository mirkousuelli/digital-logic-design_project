----------------------------------------------------------------------------------
-- Type definitions
----------------------------------------------------------------------------------
PACKAGE type_defs IS

	TYPE state_type IS (
        IDLE_STATE,
        FETCH_STATE,
        WAIT_STATE,
        READ_STATE,
        MATCH_STATE,
        ENCODE_STATE,
        WRITE_STATE,
        DONE_STATE
    );

END type_defs;

PACKAGE BODY type_defs IS
END type_defs;
----------------------------------------------------------------------------------
-- Project
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

USE work.type_defs.ALL;

ENTITY project_reti_logiche IS
    PORT (
        -- clock signal generated from test-brench
        i_clk           :   IN  std_logic;

        -- START signal which makes starting the process
        i_start         :   IN  std_logic;

        -- RESET signal which initialize the FSM ready to get START = 1
        i_rst           :   IN  std_logic;

        -- ADDR read from the memory ready to be encoded
        i_data          :   IN  std_logic_vector(7 DOWNTO 0);

        -- ADDR encoded to be written into the memory
        o_address       :   OUT std_logic_vector(15 DOWNTO 0) := x"0000";

        -- DONE signals which tells when elaboration is over and ADDR encoded
        -- has been written into the memory
        o_done          :   OUT std_logic := '0';

        -- ENABLE signal to use the memory both W and R mode
        o_en            :   OUT std_logic := '0';

        -- WRITE ENABLE set to 1 when W is needed to apply to the memory or 0
        -- to use R mode
        o_we            :   OUT std_logic := '0';

        -- signal which goes to the memory
        o_data          :   OUT std_logic_vector(7 DOWNTO 0) := x"00"
    );
END project_reti_logiche;

ARCHITECTURE Behavioral OF project_reti_logiche IS
    -- types
    TYPE one_hot_t IS ARRAY (3 DOWNTO 0) OF std_logic_vector (3 DOWNTO 0);

    -- working-zone signals
    SIGNAL wz               :   std_logic_vector (7 DOWNTO 0) := x"00";
    SIGNAL wz_wait         :   std_logic := '0';
    SIGNAL wz_read          :   std_logic := '0';
    SIGNAL wz_done         :   std_logic := '0';
    SIGNAL wz_bit           :   std_logic := '0';
    SIGNAL wz_num           :   std_logic_vector (2 DOWNTO 0) := "000";
    SIGNAL wz_offset        :   std_logic_vector (3 DOWNTO 0) := x"1";
    SIGNAL wz_border        :   std_logic := '0';
    SIGNAL wz_match         :   std_logic := '0';

    -- other signals
    SIGNAL to_conv          :   std_logic_vector (6 DOWNTO 0) := "0000000";
    SIGNAL conv             :   std_logic_vector (7 DOWNTO 0) := x"00";
    SIGNAL nxt_addr         :   std_logic_vector (15 DOWNTO 0) := x"0000";
    SIGNAL state            :   state_type;
    SIGNAL one_hot          :   one_hot_t := (
        0 => "0001",
        1 => "0010",
        2 => "0100",
        3 => "1000"
    );

    -- constants
    CONSTANT ADDR_TO_CONV   :   std_logic_vector (15 DOWNTO 0) := x"0008";
    CONSTANT ADDR_CONV      :   std_logic_vector (15 DOWNTO 0) := x"0009";

BEGIN
    CURRENT_STATE : PROCESS (i_clk)
    -- variables
    VARIABLE INDEX          :   integer range 0 to 4 := 0;
    
    BEGIN
        IF rising_edge (i_clk) THEN
            CASE state IS
                WHEN IDLE_STATE =>
                    -- idle output conditions
                    o_en <= '0'; -- no memory access
                    o_we <= '0'; -- default reading mode
                    o_done <= '0'; -- not done yet
                    o_data <= x"00"; -- no data to write
                    o_address <= x"0000"; -- default
                    
                    -- wz params
                    wz <= x"00";
                    wz_num <= "000";
                    wz_offset <= x"1";
                    
                    -- flags
                    wz_wait <= '0';
                    wz_read <= '1';
                    wz_done <= '0';
                    wz_bit <= '0';
                    wz_border <= '0';
                    wz_match <= '0';
                    
                    -- nxt values
                    nxt_addr <= x"0000";

                WHEN FETCH_STATE =>
                    -- fetch output conditions
                    o_en <= '1'; -- memory enabled

                    -- assign 0x0008 address which consists of the value to be encoded
                    o_address <= ADDR_TO_CONV;

                    -- getting the value
                    to_conv <= i_data (6 DOWNTO 0);

                    -- i can go to the following state of wz-reading
                    wz_read <= not wz_read;
                    wz_wait <= '0';
                    
                    
                WHEN WAIT_STATE =>
                    IF (wz_read = '1') THEN
                        wz_wait <= not wz_wait;
                    ELSIF (wz_done = '1') THEN
                        o_done <= '1'; -- finally done!
                    END IF;

                WHEN READ_STATE =>
                    -- read output conditions
                    o_en <= '1'; -- memory enabled

                    -- until wz_7
                    IF (wz_num <= "111") THEN
                        -- output address
                        o_address <= nxt_addr;
                        -- reading each working-zone address
                        wz <= i_data;
                    END IF;
                       
                    IF (wz_wait = '0') THEN
                        wz_match <= '1';
                        INDEX := 0; -- reset the index
                    END IF;

                WHEN MATCH_STATE =>
                    -- match output conditions
                    o_en <= '0'; -- no memory access
                    
                    wz_match <= '0';
                    wz_wait <= '1';
                    
                    -- just started
                    wz_border <= '0';

                    -- shift through bit wising to the left in order to evalute the next address
                    wz_offset <= one_hot(INDEX); -- ONE-HOT encoding first step

                    -- until i checked 4 address (wz_* base included) and it doesn't belong yet
                    IF (INDEX <= 3) AND (wz_bit = '0') THEN
                        -- if it belongs
                        IF ( (( wz (6 DOWNTO 0)) + INDEX) = to_conv) THEN
                            wz_bit <= '1'; -- alert through wz_bit
                            wz_read <= '0'; -- stop reading
                        ELSE
                            -- i check for the following wz neightborhood
                            INDEX := INDEX + 1;

                            -- if i am out of scale i reset the index and i alert that it doesn't belong AT ALL
                            IF (INDEX = 4) THEN
                                -- start from the beginning for a new wz
                                INDEX := 0;
                                
                                -- i checked all 4 addrs
                                wz_border <= '1';

                                -- if i finished with the last one
                                IF (wz_num >= "111") THEN
                                    -- there is no other wz to check
                                    wz_read <= '0'; -- stop reading
                                ELSE
                                    -- next working zone to be stored
                                    wz_num <= std_logic_vector( unsigned (wz_num) + 1 );
                                    
                                    -- going into the following address
                                    nxt_addr <= std_logic_vector( unsigned (nxt_addr) + 1 ); -- keep readin
            
                                END IF;
             
                            END IF;

                        END IF;
                        
                    END IF;

                WHEN ENCODE_STATE =>
                    wz_read <= '0'; -- reset to be safe in any case
                    
                    IF (wz_bit = '1') THEN
                        -- *in-wz* encoding
                        conv <= ( wz_bit & wz_num & wz_offset );
                    ELSE
                        -- *not-in-wz* encoding
                        conv <= ( wz_bit & to_conv );
                    END IF;

                WHEN WRITE_STATE =>
                    -- writing output conditions
                    o_en <= '1'; -- memory enabled
                    o_we <= '1'; -- writing mode
                    o_done <= '0'; -- not done yet
                    o_address <= ADDR_CONV; -- address of the outcome
                    o_data <= conv; -- value econded to be written
                    
                    wz_done <= '1'; -- almost done

                WHEN DONE_STATE =>
                    -- done output conditions
                    o_en <= '0'; -- no memory access
                    o_we <= '0'; -- reading default mode
            END CASE;
        END IF;
    END PROCESS CURRENT_STATE;

    NEXT_STATE : PROCESS (i_clk, i_rst, i_start)
    BEGIN
        IF (i_rst = '1') THEN
            -- reset interrupt
            state <= IDLE_STATE;
        ELSIF rising_edge (i_clk) THEN
        -- foreach clock rising edge check..
            CASE state IS
                WHEN IDLE_STATE =>
                -- if i am asked to start i go to the fetch state
                    IF i_start = '1' THEN
                        state <= FETCH_STATE;
                    END IF;
                    
                WHEN FETCH_STATE =>
                    -- if i completed the fetch execution, then i am told to go to the wz-reading state
                    state <= WAIT_STATE;
                    
                WHEN WAIT_STATE =>
                    IF (wz_done = '1') THEN
                        state <= DONE_STATE;
                    ELSE
                        IF (wz_read = '1') THEN
                            state <= READ_STATE;
                        ELSE
                            state <= FETCH_STATE;
                        END IF;
                    END IF;
                
                WHEN READ_STATE =>
                    -- after i read a wz then i match it with the address to be converted
                    -- without any condition to attempt
                    IF (wz_match = '1') THEN
                        state <= MATCH_STATE;
                    ELSIF (wz_wait = '1') THEN
                        state <= WAIT_STATE;
                    END IF;

                WHEN MATCH_STATE =>
                    -- if i found its wz than i go to a separate state for a specific encoding
                    IF (wz_bit = '1') THEN
                        state <= ENCODE_STATE;
                    ELSE
                        -- not check all 4 wz spaces, remains in the current state
                        IF wz_border = '0' THEN
                            state <= MATCH_STATE;
                        ELSE
                            -- keep reading another wz
                            IF wz_read = '1' THEN
                                state <= READ_STATE;   
                            ELSE
                            -- no more wz, starts encoding
                                state <= ENCODE_STATE;
                            END IF;
                            
                        END IF;
                        
                    END IF;
                
                WHEN ENCODE_STATE =>
                    -- after encoding state goes straight to writing
                    state <= WRITE_STATE;
                
                WHEN WRITE_STATE =>
                    -- when writing is over then it is done
                    state <= WAIT_STATE;
                
                WHEN DONE_STATE =>
                    -- repeat from zero when
                    IF (i_start = '0') THEN
                        state <= IDLE_STATE;
                    END IF;

                -- default case
                WHEN OTHERS =>
                    state <= IDLE_STATE;    
            END CASE;

        END IF;
    END PROCESS;
END Behavioral;