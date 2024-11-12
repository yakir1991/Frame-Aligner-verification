Frame Aligner verification 
Introduction
The Frame Aligner is a component in serial communication systems. Its role is to detect and synchronize incoming data frames by identifying specific header patterns. The aligner ensures that data is received correctly and enables proper processing of the information.

Behavior Description of the Aligner
Receives an 8-bit serial data stream and searches for specific header patterns.
After detecting a valid header, collects the frame's payload.
Provides a synchronization signal through the frame detection signal.
Enters synchronization mode after correctly identifying 3 frames.
Exits synchronization mode after counting 48 bytes without detecting a valid header.
Valid Frame: 16-bit header and 80-bit payload (10 bytes).
Possible Header Patterns:
- Header Type 1 (HEAD_1) LSB = 0xAA, MSB = 0xAF
- Header Type 2 (HEAD_2) LSB = 0x55, MSB = 0xBA

Assumptions
Data Rate: The data is received at a rate of one byte per clock.
Known Header Patterns: The only possible headers are AFAA or BA55.
Valid Frame Length: Consists of 12 bytes (2 bytes for the header and 10 bytes for the payload).
Data Continuity: No interruptions or data loss in the incoming stream
Invalid Frame: Comprises a random number of bytes (2 bytes for the header + a random number of payload bytes).
