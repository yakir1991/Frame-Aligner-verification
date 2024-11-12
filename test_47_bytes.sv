task test_47_bytes(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;

  // Frame of 49 bytes with a valid LSB at byte 47 and valid msb at byte 48
  trans = new();
  // Force the header type to ILLEGAL
  if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
    $fatal("Randomization failed for ILLEGAL transaction");
  end

  // Manually set the frame of size 47 bytes
  trans.payload = new[47]; // Manually set the payload bytes 
  trans.frame = new[49]; 
  // Fill the frame with arbitrary data
  for (int i = 0; i < 50; i++) begin
    trans.frame[i] = 8'h00; // or other values as needed
  end
  // Set a valid LSB at byte number 47 
  trans.frame[0] = 8'hAA; // or 8'h55
  trans.frame[1] = 8'hAA; // or 8'h55
  trans.frame[2] = 8'hAF; // or 8'hba
  trans.frame[47] = 8'hAA; // or 8'h55
  trans.frame[48] = 8'hAF; // or 8'hba

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
