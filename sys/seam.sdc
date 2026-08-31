#==========================================================================#
#  seam.sdc -- Emu68-A9 hybrid chip-seam clock-domain-crossing constraints  #
#--------------------------------------------------------------------------#
#  The seam has two genuine crossings:                                      #
#    AXI / h2f clock  (S_AXI_ACLK)  == *|h2f_user0_clk            100 MHz   #
#    Amiga chip clock (sync_clk = clk_sys)                        28.6 MHz  #
#         == *|pll|pll_inst|altera_pll_i|*[*].*|divclk                      #
#                                                                          #
#  sys/sys_top.sdc already declares those two in separate -exclusive clock  #
#  groups, so TimeQuest does not analyse setup/hold between them.  What it  #
#  does NOT provide, and what this file adds, is explicit CDC intent on the #
#  single-bit handshake toggles and a per-bus skew bound on the multi-bit   #
#  payload, so a toggle-qualified value cannot be latched torn.             #
#                                                                          #
#  Node paths are rooted at the core instance `emu`, and the seam nodes     #
#  exist only in a HYBRID_EMU build -- without it these collections are     #
#  empty and Quartus emits a benign "no such node" warning.  Patterns are   #
#  BRACED so the [*] bit-selects are literal, not Tcl substitution.         #
#==========================================================================#

# One launch-clock period, used as the skew bound on the toggle-qualified payload buses.
set AXI_PERIOD  10.0    ;# h2f 100 MHz      -> AXI-domain launch (AXI->SYNC payload)
set SYNC_PERIOD 35.0    ;# clk_sys 28.6 MHz -> chip-domain launch (SYNC->AXI readback)

#--------------------------------------------------------------------------#
# 1. seam_engine REQ/ACK toggle handshake  (the primary seam CDC)           #
#--------------------------------------------------------------------------#
# req_tgl / done_tgl are 1-bit Gray toggles resynchronised by a 2-FF chain
# (req_sync / done_sync).  A toggle is metastability-safe by construction, so
# the launch->first-FF path carries no setup/hold requirement: false-path it.
set_false_path -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|req_tgl}] \
               -to   [get_registers {emu|u_axi_seam_slave|u_seam_engine|req_sync[0]}]
set_false_path -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|done_tgl_sync}] \
               -to   [get_registers {emu|u_axi_seam_slave|u_seam_engine|done_sync[0]}]

#--------------------------------------------------------------------------#
# 2. seam_engine PAYLOAD buses (qualified by the toggles above)             #
#--------------------------------------------------------------------------#
# xa_addr / xa_wdata / xa_ctrl are written in the AXI domain before the trigger and are
# quasi-static across the transaction, so they are not setup/hold-critical -- but the per-bit
# routing skew must be bounded to one launch period or a torn value could be captured.
set_max_delay -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|live_addr[*] \
                                    emu|u_axi_seam_slave|u_seam_engine|live_wdata[*] \
                                    emu|u_axi_seam_slave|u_seam_engine|live_ctrl[*]}] \
              -to   [get_clocks {*|pll|pll_inst|altera_pll_i|*[*].*|divclk}] $AXI_PERIOD

# Read data returns SYNC->AXI, qualified by done_tgl. readdata_s is the low word; readdata_hi_s
# is the longword high word.
# ⚠ The bound must be ONE AXI period, NOT one SYNC period: the capture happens 2-3 AXI clocks
# after done_tgl toggles and that toggle edge is false-pathed, so a 25-35 ns data route would be
# legal under a SYNC-period bound and could arrive after the capture edge -- stale data on
# silicon, invisible in a delay-free simulation.
set_max_delay -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|readdata_sync[*] \
                                    emu|u_axi_seam_slave|u_seam_engine|readdata_hi_s[*]}] \
              -to   [get_clocks {*|h2f_user0_clk}] $AXI_PERIOD

#--------------------------------------------------------------------------#
# 3. axi_seam_slave cerr resync  (bridge sticky DTACK-timeout -> AXI)      #
#--------------------------------------------------------------------------#
# hyb_cerr is a slowly-changing sticky 1-bit flag 2-FF synchronised into the AXI
# clock (cerr_sync) and surfaced in REG_STATUS/REG_RESULT bit30.  False-path the
# launch->first-FF edge.
set_false_path -from [get_registers {emu|u_hybrid_bridge|cerr}] \
               -to   [get_registers {emu|u_axi_seam_slave|cerr_sync[0]}]

#--------------------------------------------------------------------------#
# 4. seam soft-reset resync  (stretched REG_OVL[1], AXI -> chip clk)       #
#--------------------------------------------------------------------------#
# The reset source is `srst_lvl`, the registered self-clearing stretcher output -- a clean
# 1-bit level, not the raw ovl[1] register -- 2-FF synchronised into clk_sys at three sinks:
# the bridge FSM, seam_engine's flush and the chipset-reset request. A held level: false-path all three.
set_false_path -from [get_registers {emu|u_axi_seam_slave|srst_lvl}] \
               -to   [get_registers {emu|u_hybrid_bridge|srst_sync[0] \
                                     emu|u_axi_seam_slave|u_seam_engine|srst_sync[0] \
                                     emu|u_axi_seam_slave|crst_sync[0]}]

#--------------------------------------------------------------------------#
# 5. seam_ipl IPL / reset_n resync  (Paula, chip clk -> AXI)         #
#--------------------------------------------------------------------------#
# irq_s[2:0] is a MULTI-BIT word (Paula moves several IPL bits per edge), not independent
# levels: a blanket false-path would allow unbounded per-bit skew and a torn value could
# outlive the RTL's two-sample stability filter. Bound the skew to one AXI period instead.
set_max_delay -from [get_registers {emu|u_axi_seam_slave|u_seam_ipl|ipl_src[*]}] \
              -to   [get_clocks {*|h2f_user0_clk}] $AXI_PERIOD

# rst_s is a genuine single-bit level (cannot tear): false-path as before.
set_false_path -from [get_registers {emu|u_axi_seam_slave|u_seam_ipl|rst_src}] \
               -to   [get_registers {emu|u_axi_seam_slave|u_seam_ipl|rst_m1}]

#--------------------------------------------------------------------------#
# 6. seam_cpuregs VBR / CACR resample  (AXI -> chip clk)               #
#--------------------------------------------------------------------------#
# vbr_reg[31:0] / cacr_reg[3:0] are written in the AXI domain and resampled into
# clk_sys (vbr_sreg / cacr_sreg).  These ARE multi-bit buses read as a unit by the
# fabric, so bound the skew (one AXI launch period) rather than false-path them.
#
# The fitter sweeps this chain: seam_vbr/seam_cacr are connected to nothing, so the constraint
# matched no registers and only produced a warning at every compile. Restore it from history if
# a consumer ever returns.

#==========================================================================#
#  POST-FIT CHECK -- REQUIRED, NOT OPTIONAL                                 #
#--------------------------------------------------------------------------#
#  sys/sys_top.sdc puts the AXI clock and the Amiga clock in SEPARATE        #
#  -EXCLUSIVE groups, and in TimeQuest a group cut OUTRANKS set_max_delay:   #
#  every bound above can be silently nulled while this file still looks      #
#  correct.  After a fit, run `report_sdc` and `report_timing -setup` on the #
#  readdata_sync -> h2f_user0_clk paths.  If they report as cut rather than  #
#  analysed, the max_delay is inert -- which is why the set_net_delay        #
#  fallbacks below are enabled: a routing-delay constraint is NOT overridden #
#  by a clock-group cut, so those are the bounds that actually hold.         #
#==========================================================================#
set_net_delay -max $AXI_PERIOD  -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|live_addr[*] emu|u_axi_seam_slave|u_seam_engine|live_wdata[*] emu|u_axi_seam_slave|u_seam_engine|live_ctrl[*]}] -to [get_registers {emu|u_hybrid_bridge|*}]
# xa_ctrl[4] (the longword bit) also feeds seam_engine's OWN sync-domain FSM -- a crossing the
# max_delay section cannot reach, since the exclusive clock groups cut it. Bound it as a net.
set_net_delay -max $AXI_PERIOD  -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|live_ctrl[*]}] -to [get_registers {emu|u_axi_seam_slave|u_seam_engine|sstate* emu|u_axi_seam_slave|u_seam_engine|word_sel* emu|u_axi_seam_slave|u_seam_engine|readdata_hi_s[*] emu|u_axi_seam_slave|u_seam_engine|hreq*}]
set_net_delay -max $AXI_PERIOD  -from [get_registers {emu|u_axi_seam_slave|u_seam_engine|readdata_sync[*] emu|u_axi_seam_slave|u_seam_engine|readdata_hi_s[*]}] -to [get_registers {emu|u_axi_seam_slave|u_seam_engine|rdata_axi[*] emu|u_axi_seam_slave|u_seam_engine|rdata_hi_axi[*]}]
set_net_delay -max $AXI_PERIOD  -from [get_registers {emu|u_axi_seam_slave|u_seam_ipl|ipl_src[*]}] -to [get_registers {emu|u_axi_seam_slave|u_seam_ipl|ipl_m1[*]}]
#                                                                            #
#  (readdata is bounded at $AXI_PERIOD everywhere, matching sections 2 and 5.)
#==========================================================================#
