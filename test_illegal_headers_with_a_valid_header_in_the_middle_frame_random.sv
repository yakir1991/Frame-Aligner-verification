task test_illegal_headers_with_a_valid_header_in_the_middle_frame_random(mailbox gen2drv, ref int total_transactions_sent);
  // Define header values
  byte head1_lsb = 8'hAA;
  byte head1_msb = 8'hAF;
  byte head2_lsb = 8'h55;
  byte head2_msb = 8'hBA;
  
  // Array of possible headers
  byte possible_headers[4] = '{head1_lsb, head1_msb, head2_lsb, head2_msb};
  
  // Loop for multiple runs
  for(int run = 0; run < 3; run++) begin
    transaction trans;
    trans = new();
    
    // Force the header type to ILLEGAL
    if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
      $fatal("Randomization failed for ILLEGAL transaction");
    end
    
    // Set frame and payload size
    trans.frame = new[49];
    trans.payload = new[47]; // 49 - 2 = 47 bytes for payload
    
    // Set the illegal header
    trans.frame[0] = 8'hDE; // Custom LSB (Invalid Header)
    trans.frame[1] = 8'h00; // Custom MSB (Invalid Header)
    
    // Fill the entire payload with random header values
    for(int i = 0; i < 47; i++) begin
      trans.frame[2 + i] = possible_headers[$urandom_range(0,3)];
    end
    
    // Display the generated transaction
    $display("[ --Generator-- ] Generated Transaction %0d:", run+1);
    $display("  Header Type    : %s", 
            (trans.header_type == transaction::HEAD_1) ? "HEAD_1" :
            (trans.header_type == transaction::HEAD_2) ? "HEAD_2" :
            "ILLEGAL");
    $display("  Payload Size   : %0d bytes", trans.payload.size());
    $display("  Frame Size     : %0d bytes", trans.frame.size());
    $display("  Frame Data     : {");
    foreach (trans.frame[i]) $display("    Byte %0d: 0x%0h", i, trans.frame[i]);
    $display("  }");
    
    // Send the transaction to the driver
    gen2drv.put(trans);
    total_transactions_sent++;
  end
endtask
