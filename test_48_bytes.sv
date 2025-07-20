// Test has a 50-byte frame with header starting at byte 48

// The expectation is that frame_detect clears after 48 illegal bytes
// before recognizing the new header.
task test_48_bytes(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;

  // Frame of 50 bytes with a valid LSB at byte 48 and valid MSB at byte 49
  trans = new();
  // Force the header type to ILLEGAL
  if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
    $fatal("Randomization failed for ILLEGAL transaction");
  end

  // Manually set the frame of size 48 bytes of illegal data
  trans.payload = new[48];
  trans.frame = new[50];
  // Fill the frame with arbitrary illegal data
  for (int i = 0; i < trans.frame.size(); i++) begin
    trans.frame[i] = 8'h00; // illegal bytes
  end
  // Insert a valid header after 48 illegal bytes
  trans.frame[48] = 8'hAA; // valid LSB
  trans.frame[49] = 8'hAF; // valid MSB

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
