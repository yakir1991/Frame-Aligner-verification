//==============================================================================
// monitor_out -- observes the DUT outputs
//------------------------------------------------------------------------------
//  At every rising edge it samples fr_byte_position and frame_detect through
//  the mon_cb clocking block.  Because the outputs are registered, the value
//  sampled at edge k is the DUT's response to the byte consumed at edge k-1;
//  the scoreboard takes care of that one-cycle alignment explicitly.
//
//  Values are kept 4-state so that X/Z on an output reaches the scoreboard.
//==============================================================================
class monitor_out;

  virtual frame_inf   vif;
  std::mailbox #(mon_item) mon2scb;
  longint unsigned    cycle;

  function new(virtual frame_inf vif, std::mailbox #(mon_item) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    forever begin
      mon_item it = new();
      @(vif.mon_cb);
      it.cycle            = cycle++;
      it.fr_byte_position = vif.mon_cb.fr_byte_position;
      it.frame_detect     = vif.mon_cb.frame_detect;
      fa_info(3, "MON_OUT", it.out2string());
      mon2scb.put(it);
    end
  endtask

endclass
