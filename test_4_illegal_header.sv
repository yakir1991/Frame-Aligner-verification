task test_4_illegal_header(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;
  // generate 4 transactions with ILLEGAL header and random payload
  for (int i = 0; i < 4; i++) begin
    trans = new();
    // Force the header type to ILLEGAL and randomize payload only
    if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
      $fatal("Randomization failed for ILLEGAL transaction");
    end
    // Display the generated transaction
    $display("[ --Generator-- ] Generated Transaction:");
    $display("  Header Type    : %s", 
            (trans.header_type == transaction::HEAD_1) ? "HEAD_1" :
            (trans.header_type == transaction::HEAD_2) ? "HEAD_2" :
            "ILLEGAL");
    $display("  Payload Size   : %0d bytes", trans.payload.size());
    $display("  Frame Size     : %0d bytes", trans.frame.size());
    $display("  Frame Data     : {");
    foreach (trans.frame[i]) $display("    Byte %0d: 0x%0h", i, trans.frame[i]);
    $display("  }");
    // Send the transaction to driver
    gen2drv.put(trans);
    total_transactions_sent++;
  end
endtask
