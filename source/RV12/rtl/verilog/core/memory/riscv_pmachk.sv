/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//    RISC-V                                                       //
//    Physical Memory Attributes Checker                           //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2018-2022 ROA Logic BV                //
//             www.roalogic.com                                    //
//                                                                 //
//     Unless specifically agreed in writing, this software is     //
//   licensed under the RoaLogic Non-Commercial License            //
//   version-1.0 (the "License"), a copy of which is included      //
//   with this file or may be found on the RoaLogic website        //
//   http://www.roalogic.com. You may not use the file except      //
//   in compliance with the License.                               //
//                                                                 //
//     THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY           //
//   EXPRESS OF IMPLIED WARRANTIES OF ANY KIND.                    //
//   See the License for permissions and limitations under the     //
//   License.                                                      //
//                                                                 //
////////////////////////////////////////////////////////////////////


module riscv_pmachk
import riscv_pma_pkg::*;
import riscv_state_pkg::*; //pmpcfg_a_t; //Quartus doesn't like this
import biu_constants_pkg::*;
#(
  parameter XLEN    = 32,
  parameter PLEN    = XLEN == 32 ? 34 : 56,
  parameter HAS_RVC = 0,
  parameter PMA_CNT = 16
)
(
  input  logic               clk_i,
  input  logic               stall_i,

  //PMA  configuration
  input  pmacfg_t            pma_cfg_i [PMA_CNT],
  input  logic    [XLEN-1:0] pma_adr_i [PMA_CNT],

  //Memory Access
  input  logic               instruction_i, //This is an instruction access
  input  logic    [PLEN-1:0] adr_i,         //Physical Memory address (i.e. after translation)
  input  biu_size_t          size_i,        //Transfer size
  input  logic               lock_i,        //AMO : TODO: specify AMO type
  input  logic               we_i,

  input  logic               misaligned_i,  //Misaligned access


  //Output
  output logic               exception_o,
                             misaligned_o,
                             cacheable_o
);

  //////////////////////////////////////////////////////////////////
  //
  // Functions
  //

  //convert transfer size in number of bytes in transfer
  function automatic int size2bytes;
    input biu_size_t size;

    case (size)
      BYTE   : size2bytes = 1;
      HWORD  : size2bytes = 2;
      WORD   : size2bytes = 4;
      DWORD  : size2bytes = 8;
      QWORD  : size2bytes = 16;
      default: begin
                   size2bytes = -1;
                   $error ("Illegal biu_size_t");
               end
    endcase
  endfunction: size2bytes


  //Lower and Upper bounds for NA4/NAPOT
  function int napot_boundary;
    input na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    bit true;

    //find 'n' boundary = 2^(n+2) bytes
    n = 2;
    if (!na4)
    begin
        true = 1'b1;
        for (int i=0; (i < $bits(pmaddr)) && true; i++)
          if (pmaddr[i]) n++;
          else           true = 1'b0;
	 
        n++;
    end

    return n;
  endfunction: napot_boundary


  function automatic [PLEN-1:0] napot_lb;
    input            na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    logic [PLEN-1:0] mask;

    //find 'n' boundary = 2^(n+2) bytes
    n = napot_boundary(na4, pmaddr);

    //create mask
    mask = {$bits(mask){1'b1}} << n;

    //lower bound address
    napot_lb = pmaddr;
    napot_lb <<= 2;
    napot_lb &= mask;
  endfunction: napot_lb


  function automatic [PLEN-1:0] napot_ub;
    input            na4; //special case na4
    input [XLEN-1:0] pmaddr;

    int n;
    logic [PLEN-1:0] mask,
                     range;

    //find 'n' boundary = 2^(n+2) bytes
    n = napot_boundary(na4, pmaddr);

    //create mask and increment
    mask = {$bits(mask){1'b1}} << n;
    range = 1 << n;

    //upper bound address
    napot_ub = pmaddr;
    napot_ub <<= 2;
    napot_ub &= mask;
    napot_ub += range;
  endfunction: napot_ub


  //Is ANY byte of 'access' in pma range?
  function automatic match_any;
    input [PLEN-1:0] access_lb, access_ub,
                     pma_lb   , pma_ub;

    /* Check if ANY byte of the access lies within the PMA range
     *   pma_lb <= range < pma_ub
     * 
     *   match_none = (access_lb >= pma_ub) OR (access_ub < pma_lb)  (1)
     *   match_any  = !match_none                                    (2)
     */
     match_any = (access_lb[PLEN-1:2] >= pma_ub[PLEN-1:2]) || (access_ub[PLEN-1:2] <  pma_lb[PLEN-1:2]) ? 1'b0 : 1'b1;
  endfunction: match_any


  //Are ALL bytes of 'access' in PMA range?
  function automatic match_all;
    input [PLEN-1:0] access_lb, access_ub,
                     pma_lb   , pma_ub;

    match_all = (access_lb[PLEN-1:2] >= pma_lb[PLEN-1:2]) && (access_ub[PLEN-1:2] < pma_ub[PLEN-1:2]) ? 1'b1 : 1'b0;
  endfunction: match_all


  //get highest priority (==lowest number) PMP that matches
  function automatic int highest_priority_match;
    input [PMA_CNT-1:0] m;

    int n;

    highest_priority_match = 0; //default value

    for (n=PMA_CNT-1; n >= 0; n--)
      if (m[n]) highest_priority_match = n;
  endfunction: highest_priority_match


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  genvar i;

  logic    [PLEN   -1:0] access_ub,
                         access_lb;
  logic    [PLEN   -1:0] pma_ub [PMA_CNT],
                         pma_lb [PMA_CNT];
  logic    [PMA_CNT-1:0] pma_match,
                         pma_match_all;
  int                    matched_pma_idx;
  pmacfg_t               pmacfg [PMA_CNT],
                         matched_pma;

  logic                  we;



  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /* PMA configurations
   */
generate
  for (i=0; i < PMA_CNT; i++)
  begin: set_pmacfg
      assign pmacfg[i].mem_type = pma_cfg_i[i].mem_type == MEM_TYPE_EMPTY ? MEM_TYPE_IO
                                                                          : pma_cfg_i[i].mem_type;
      assign pmacfg[i].amo_type = pma_cfg_i[i].mem_type == MEM_TYPE_EMPTY ? AMO_TYPE_NONE
                                                                          : pma_cfg_i[i].amo_type;
      assign pmacfg[i].r        = pma_cfg_i[i].mem_type == MEM_TYPE_EMPTY ? 1'b0
                                                                          : pma_cfg_i[i].r;
      assign pmacfg[i].w        = pma_cfg_i[i].mem_type == MEM_TYPE_EMPTY ? 1'b0
                                                                          : pma_cfg_i[i].w;
      assign pmacfg[i].x        = pma_cfg_i[i].mem_type == MEM_TYPE_EMPTY ? 1'b0
                                                                          : pma_cfg_i[i].x;
      assign pmacfg[i].c        = pma_cfg_i[i].mem_type == MEM_TYPE_MAIN  ? pma_cfg_i[i].c
                                                                          : 1'b0;
      assign pmacfg[i].cc       = pma_cfg_i[i].cc & pmacfg[i].c;
      assign pmacfg[i].ri       = pma_cfg_i[i].mem_type == MEM_TYPE_IO    ? pma_cfg_i[i].ri //idempotent read
                                                                          : 1'b1;
      assign pmacfg[i].wi       = pma_cfg_i[i].mem_type == MEM_TYPE_IO    ? pma_cfg_i[i].wi //idempotent write
                                                                          : 1'b1;
      assign pmacfg[i].m        = pma_cfg_i[i].m;
      assign pmacfg[i].a        = pma_cfg_i[i].a;
  end
endgenerate


  /* Address Range Matching
   */
  assign access_lb = adr_i;
  assign access_ub = adr_i + size2bytes(size_i) -1;

generate
  for (i=0; i < PMA_CNT; i++)
  begin: gen_pma_bounds
      //lower bounds
      always_comb
        unique case (pmacfg[i].a)
          TOR    : pma_lb[i] = (i==0) ? {PLEN{1'b0}} : pma_ub[i-1];
          NA4    : pma_lb[i] = napot_lb(1'b1, pma_adr_i[i]);
          NAPOT  : pma_lb[i] = napot_lb(1'b0, pma_adr_i[i]);
          default: pma_lb[i] = {$bits(pma_lb[i]){1'bx}};
        endcase

      //upper bounds
      always_comb
        unique case (pmacfg[i].a)
          TOR    : pma_ub[i] = pma_adr_i[i];
          NA4    : pma_ub[i] = napot_ub(1'b1, pma_adr_i[i]);
          NAPOT  : pma_ub[i] = napot_ub(1'b0, pma_adr_i[i]);
          default: pma_ub[i] = {$bits(pma_ub[i]){1'bx}};
        endcase

      //match
      assign pma_match    [i] = match_any(access_lb, access_ub, pma_lb[i], pma_ub[i]) & (pmacfg[i].a != OFF);
//      assign pma_match_all[i] = match_all(access_lb, access_ub, pma_lb[i], pma_ub[i]) & (pmacfg[i].a != OFF);

      always @(posedge clk_i)
        if (!stall_i) pma_match_all[i] <= match_all(access_lb, access_ub, pma_lb[i], pma_ub[i]) & (pmacfg[i].a != OFF);
  end
endgenerate

  assign matched_pma_idx = highest_priority_match(pma_match_all);
  assign matched_pma     = pmacfg[ matched_pma_idx ];


  //delay we; align with matched_pma
  always @(posedge clk_i)
    if (!stall_i) we <= we_i;


  /* Access/Misaligned Exception
   */
  assign exception_o = (~|pma_match_all                   |  // no memory range matched
                        ( instruction_i & ~matched_pma.x) |  // not executable
                        ( we            & ~matched_pma.w) |  // not writeable
                        (~we            & ~matched_pma.r) ); // not readable


  assign misaligned_o = misaligned_i & ~matched_pma.m;


  /* Access Types
   */
  assign cacheable_o = matched_pma.c; //implies MEM_TYPE_MAIN
endmodule

