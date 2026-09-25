// Test sends three frames with randomly chosen valid headers

task test_3_random_valid_headers(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;
  // Generate 3 transactions with random valid headers (HEAD_1 or HEAD_2)
  for (int i = 0; i < 3; i++) begin
    trans = new();
    // Randomize the header type to be either HEAD_1 or HEAD_2
    if (!trans.randomize() with { header_type inside {transaction::HEAD_1, transaction::HEAD_2}; }) begin
      $fatal("Randomization failed for valid header transaction");
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