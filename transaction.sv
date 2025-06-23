//This class encapsulates the details and variability of frame
//transactions, facilitating comprehensive, randomized testing of 
//the Frame Aligner’s handling of various frame structures.

class transaction;

  // Define the header_type enum
  typedef enum bit [1:0] {HEAD_1, HEAD_2, ILLEGAL} header_type_t;

  // Declare the transaction fields
  logic [7:0] rx_data;  
  logic       frame_detect;
  logic [3:0] fr_byte_position;

  // Fields for payload and header type and frame
  rand logic [7:0] payload[];       // Dynamic array for payload data
  rand header_type_t header_type; // Enum for header type
  logic [7:0] frame[];  // Dynamic array for frame bytes

  // Constraints to control payload size based on header_type
  constraint payload_size_c {
    if (header_type == HEAD_1 || header_type == HEAD_2) {
      payload.size() == 10;
    } else if (header_type == ILLEGAL) {
      payload.size() inside {[0:47]};
    }
  }

    // Constraint: Distribution for header_type
  constraint header_type_dist_c {
    header_type dist {
      HEAD_1   := 40,  // 40% probability
      HEAD_2   := 40,  // 40% probability
      ILLEGAL  := 20   // 20% probability
    };
  }

// Post-randomize function to set up frame based on header_type and payload
  function void post_randomize();
    // Determine the total size: 2 header bytes + payload size
    frame = new[2 + payload.size()];
    
    // Set header bytes based on header_type
    case (header_type)
      HEAD_1: begin
        frame[0] = 8'hAA; // LSB
        frame[1] = 8'hAF; // MSB
      end
      HEAD_2: begin
        frame[0] = 8'h55; // LSB
        frame[1] = 8'hBA; // MSB
      end
      ILLEGAL: begin
        frame[0] = $urandom_range(8'h00, 8'hFF); // Random LSB
        frame[1] = $urandom_range(8'h00, 8'hFF); // Random MSB
      end
    endcase

    // Copy payload bytes into frame
    for (int i = 0; i < payload.size(); i++) begin
      frame[2 + i] = payload[i];
    end
  endfunction

  // Helper function to convert header_type enum to a readable string
  function string header_type_to_string(header_type_t t);
    case (t)
      HEAD_1:  header_type_to_string = "HEAD_1";
      HEAD_2:  header_type_to_string = "HEAD_2";
      default: header_type_to_string = "ILLEGAL";
    endcase
  endfunction

endclass
