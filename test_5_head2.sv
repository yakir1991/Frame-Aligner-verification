task test_5_head2(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;
  // generate 5 transactions with HEAD_2 and random payload
  for (int i = 0; i < 5; i++) begin
    trans = new();
    // Force the header type to HEAD_2 and randomize payload only
    if (!trans.randomize() with {header_type == transaction::HEAD_2;}) begin
      $fatal("Randomization failed for HEAD_2 transaction");
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
