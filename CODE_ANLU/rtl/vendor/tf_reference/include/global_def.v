


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Parenthesize macro arithmetic before using it in other expressions.
// The refresh counter includes both zero and its terminal value.
`define SDR_CLK_PERIOD (1000000000 / 50000000)
`define SELF_REFRESH_INTERVAL ((64000000 / `SDR_CLK_PERIOD / (2 ** `ROW_WIDTH)) - 1)
