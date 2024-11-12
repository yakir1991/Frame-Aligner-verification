task test_illegal_headers_with_a_valid_header_in_the_middle_frame_10_clock(mailbox gen2drv, ref int total_transactions_sent);
  transaction trans;
    trans = new();
    // Force the header type to ILLEGAL and randomize payload only
    if (!trans.randomize() with {header_type == transaction::ILLEGAL;}) begin
      $fatal("Randomization failed for ILLEGAL transaction");
    end
    
    trans.payload = new[15]; // Manually set the payload bytes 
    trans.frame = new[17];  // Set size to total number of bytes 
    trans.frame[0] = 8'hDE;  // Custom LSB
    trans.frame[1] = 0;  // Custom MSB
    trans.frame[2] = 8'h01;
    trans.frame[3] = 8'h02;
    trans.frame[4] = 8'hAA; // HEAD_1 LSB inside payload
    trans.frame[5] = 8'hAF;  // HEAD_1 MSB inside payload
    trans.frame[6] = 8'h05;
    trans.frame[7] = 8'h06;
    trans.frame[8] = 8'hAA;  // HEAD_1 LSB inside payload
    trans.frame[9] = 8'hAF;  // HEAD_1 MSB inside payload
    trans.frame[10] = 8'h07;
    trans.frame[11] = 8'h08;
    trans.frame[12] = 8'h08;
    trans.frame[13] = 8'h08;
    trans.frame[14] = 8'h08;
    trans.frame[15] = 8'h08;
    trans.frame[16] = 8'h08;


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
endtask
