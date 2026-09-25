//==============================================================================
// monitor_in -- observes the DUT inputs
//------------------------------------------------------------------------------
//  At every rising edge it samples (through the mon_cb clocking block, i.e.
//  the values stable just before the edge) the reset, the byte the DUT is
//  consuming on this edge and the driver's side-band stream index, and sends
//  them to the scoreboard.  Samples are numbered (cycle) so the scoreboard can
//  prove that the input and output monitors stay in lock-step.
//
//  The monitor is passive: it never drives anything, so it could be reused
//  on a system-level bench where another block drives rx_data.
//==============================================================================
class monitor_in;

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
      it.cycle      = cycle++;
      it.reset      = vif.mon_cb.reset;
      it.rx_data    = vif.mon_cb.rx_data;
      it.byte_idx   = vif.mon_cb.tb_byte_idx;
      it.byte_valid = vif.mon_cb.tb_byte_valid;
      fa_info(3, "MON_IN", it.in2string());
      mon2scb.put(it);
    end
  endtask

endclass
