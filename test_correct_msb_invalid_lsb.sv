task test_correct_msb_invalid_lsb(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;

  // Data for the headers
  byte head1_lsb = 8'hAA;
  byte head1_msb = 8'hAF;
  byte head2_lsb = 8'h55;
  byte head2_msb = 8'hBA;

  // frame for HEAD_1 
  trans = new();
  // Force the header type to ILLEGAL
  if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
    $fatal("Randomization failed for ILLEGAL transaction");
  end

  // Manually set the frame of size 10 bytes
  trans.payload = new[10]; // Manually set the payload bytes 
  trans.frame = new[12]; 
  // Set a valid MSB  and a invalid LSB 
  trans.frame[0] = 8'hxA; 
  trans.frame[1] = head1_msb;

  // Display the generated transaction
  $display("[ --Generator-- ] Generated Transaction 1:");
  $display("  Header Type    : ILLEGAL");
  $display("  Frame Size     : %0d bytes", trans.frame.size());
  $display("  Frame Data     : {");
  foreach (trans.frame[i]) $display("    Byte %0d: 0x%0h", i, trans.frame[i]);
  $display("  }");

  // Send the transaction to driver
  gen2drv.put(trans);
  total_transactions_sent++;

    // frame for HEAD_2 
  trans = new();
  // Force the header type to ILLEGAL
  if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
    $fatal("Randomization failed for ILLEGAL transaction");
  end

  // Manually set the frame of size 10 bytes
  trans.payload = new[10]; // Manually set the payload bytes 
  trans.frame = new[12]; 
  // Set a valid MSB and a valid LSB 
  trans.frame[0] = 8'h05; 
  trans.frame[1] = head2_msb;


  // Display the generated transaction
  $display("[ --Generator-- ] Generated Transaction 1:");
  $display("  Header Type    : ILLEGAL");
  $display("  Frame Size     : %0d bytes", trans.frame.size());
  $display("  Frame Data     : {");
  foreach (trans.frame[i]) $display("    Byte %0d: 0x%0h", i, trans.frame[i]);
  $display("  }");

  // Send the transaction to driver
  gen2drv.put(trans);
  total_transactions_sent++;
endtask
