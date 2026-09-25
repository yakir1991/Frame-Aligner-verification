//this module serves as a checker to validate that the frame aligner correctly handles frame synchronization,
//header detection, and byte positioning according to the expected patterns and timing. It catches potential
//design issues in simulation by ensuring key conditions are met and helps confirm that the aligner behaves as specified.

module frame_assertions(
    input clk,
    input reset,
    input [7:0] rx_data,
    input [3:0] fr_byte_position,
    input frame_detect
);

    // Define a sequence for a valid header1: LSB followed by MSB
    sequence valid_header1;
        (rx_data == 8'haa) ##1
        (rx_data == 8'haf);
    endsequence

    // Define a sequence for a valid header2: LSB followed by MSB
    sequence valid_header2;
        (rx_data == 8'h55) ##1
        (rx_data == 8'hba);
    endsequence


    // Define sequence for a header followed by payload
    sequence header_and_payload;
        (valid_header1 or valid_header2) ##1
        (1'b1)[*10];
    endsequence

    sequence fr_byte_position_leq_2_56;
    (fr_byte_position <= 4'd2) [*56];
    endsequence


    // If three valid headers with payloads occur consecutively, then after one clock cycle, frame_detect must rise
    property check_frame_detect_after_3_headers;
        @(posedge clk)
        disable iff (reset)
        (header_and_payload ##0 header_and_payload ##0 header_and_payload) |=> ##1 $rose(frame_detect);
    endproperty

    // Check that fr_byte_position does not reset when it is greater than or equal to 2 and rx_data is 8'h55 or 8'hAA
    property fr_byte_position_not_reset_when_above_2;
        @(posedge clk)
        disable iff (reset)
        (fr_byte_position >= 4'd2 && (rx_data == 8'h55 || rx_data == 8'hAA)) |-> 
        ##1 fr_byte_position != 4'd0;
    endproperty

    //  Check that fr_byte_position resets to 0 one clock cycle after rx_data is a valid LSB header (8'hAA or 8'h55)
    property check_fr_byte_position_reset_on_header;
        @(posedge clk)
        disable iff (reset)
        ((rx_data == 8'haa) || (rx_data == 8'h55)) |=>
        ##1 (fr_byte_position == 4'd0);
    endproperty

    // Ensure fr_byte_position increments by 1 after each valid header sequence
    property check_byte_position_increment_after_header;
        @(posedge clk)
        disable iff (reset)
        ((valid_header1 or valid_header2)) |=> 
        (fr_byte_position == $past(fr_byte_position) + 1);
    endproperty

    // Ensure byte position resets after reaching 10
    property check_byte_position_reset;
        @(posedge clk)
        disable iff (reset)
        (fr_byte_position == 4'd11) |=> (fr_byte_position == 4'd0);
    endproperty

    //Ensure frame_detect resets to 0 after 56 clocks without valid headers when frame_detect rises to 1
    //(frame detect rises to 1 after 3 valid headers and 1 clock cycle so 9 clock till the end of frame + 47 clock without valid heder) 
    property check_frame_detect_reset;
        @(posedge clk)
        disable iff (reset)
        $rose(frame_detect) |-> fr_byte_position_leq_2_56 ##1 (frame_detect == 1'b0);
    endproperty

    // Cover property
    byte_position_reset_on_header : cover property (check_fr_byte_position_reset_on_header);
    byte_position_reset: cover property (check_byte_position_reset);
    byte_position_increment_after_header: cover property (check_byte_position_increment_after_header);
    cover_fr_byte_position_not_reset_when_above_2 : cover property (fr_byte_position_not_reset_when_above_2);
    

    // Assert property
    assert_fr_byte_position_not_reset_when_above_2 : assert property (fr_byte_position_not_reset_when_above_2)
        else $error("fr_byte_position reset to 0 when it should not");

    assert_check_frame_detect_reset : assert property (check_frame_detect_reset)
        else $error("frame_detect did not reset to 0 after 56 clocks without valid headers.");

    assert_check_frame_detect_after_3_headers : assert property (check_frame_detect_after_3_headers)
        else $error("frame_detect did not rise after three valid headers with payloads.");     
    

endmodule
