//The environment class integrates all verification components and manages the test flow,
// from setup to execution and completion. By controlling each phase and ensuring all 
//components work together seamlessly, it provides a structured framework for verifying the DUT’s
// functionality and correctness across varied scenarios. This class is the backbone of the verification environment,
// enabling comprehensive and automated testing of the DUT.

class environment;
  
  // Components
  generator    gen;
  driver       drv;
  monitor_in   mon_in;
  monitor_out  mon_out;
  scoreboard   scb;
  
  // Mailbox handles
  mailbox gen2drv;
  mailbox mon2scbin;
  mailbox mon2scbout;
  
  // Virtual interface
  virtual frame_inf vinf;
  
  // Constructor
  function new(virtual frame_inf vinf);
    this.vinf = vinf;
    
    // Creating the mailboxes
    gen2drv    = new();
    mon2scbin  = new();
    mon2scbout = new();
    
    // Creating components
    gen     = new(gen2drv);
    drv     = new(vinf, gen2drv);
    mon_in  = new(vinf, mon2scbin);
    mon_out = new(vinf, mon2scbout);
    scb     = new(mon2scbin, mon2scbout);
  endfunction
  
  // Test activity
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork 
      gen.main();
      drv.main();
      mon_in.main();
      mon_out.main();
      scb.main();
    join_any
  endtask
  
  task post_test();
    wait (gen.ended.triggered);
    wait (gen.repeat_count == drv.num_transactions); 
    // wait (gen.repeat_count == scb.num_transactions); // Optional
  endtask  
  
  // Run task
  task run;
    pre_test();
    test();
    post_test();
    #20;
    $display("==============================================");
    $display("Total Errors Detected by Scoreboard: %0d", scb.num_errors);
    $display("==============================================");
    $finish;
  endtask
  
endclass
