class FrameAlignerModel:
    FR_IDLE = 0
    FR_HLSB = 1
    FR_HMSB = 2
    FR_DATA = 3

    def __init__(self):
        self.reset()

    def reset(self):
        self.current_state = self.FR_IDLE
        self.fr_byte_position = 0
        self.legal_frame_counter = 0
        self.na_byte_counter = 0
        self.frame_detect = 0
        self.header_lsb_samp = 0

    def step(self, byte, reset=False):
        if reset:
            self.reset()
            return self.fr_byte_position, self.frame_detect

        header_lsb_valid = byte in (0xAA, 0x55)
        expected_header_msb = 0
        if self.header_lsb_samp == 0xAA:
            expected_header_msb = 0xAF
        elif self.header_lsb_samp == 0x55:
            expected_header_msb = 0xBA
        header_msb_valid = (expected_header_msb == byte)

        fr_byte_position_rst = 0
        na_byte_count_inc = 0
        na_byte_count_rst = 0
        legal_frame_counter_rst = 0
        legal_frame_counter_inc = 0

        if self.current_state == self.FR_IDLE:
            if header_lsb_valid:
                fr_byte_position_rst = 1
                na_byte_count_inc = 1
                next_state = self.FR_HLSB
            else:
                legal_frame_counter_rst = 1
                fr_byte_position_rst = 1
                na_byte_count_inc = 1
                next_state = self.FR_IDLE
        elif self.current_state == self.FR_HLSB:
            if header_msb_valid:
                legal_frame_counter_inc = 1
                next_state = self.FR_HMSB
            else:
                legal_frame_counter_rst = 1
                na_byte_count_inc = 1
                next_state = self.FR_IDLE
        elif self.current_state == self.FR_HMSB:
            next_state = self.FR_DATA
        elif self.current_state == self.FR_DATA:
            if self.fr_byte_position == 10:
                na_byte_count_rst = 1
                next_state = self.FR_IDLE
            else:
                next_state = self.FR_DATA
        else:
            next_state = self.FR_IDLE

        # Sequential updates
        if fr_byte_position_rst:
            self.fr_byte_position = 0
        else:
            self.fr_byte_position = (self.fr_byte_position + 1) & 0xF

        if legal_frame_counter_rst:
            self.legal_frame_counter = 0
        elif legal_frame_counter_inc:
            self.legal_frame_counter = (self.legal_frame_counter + 1) & 0x3

        if na_byte_count_rst:
            self.na_byte_counter = 0
        elif na_byte_count_inc:
            self.na_byte_counter = (self.na_byte_counter + 1) & 0x3F

        if self.legal_frame_counter == 3:
            self.frame_detect = 1
        elif self.na_byte_counter == 47:
            self.frame_detect = 0

        if header_lsb_valid:
            self.header_lsb_samp = byte

        self.current_state = next_state
        return self.fr_byte_position, self.frame_detect


def create_frame(header_type, payload_len=10):
    payload = [0] * payload_len
    if header_type == 'HEAD_1':
        return [0xAA, 0xAF] + payload
    elif header_type == 'HEAD_2':
        return [0x55, 0xBA] + payload
    elif header_type == 'ILLEGAL':
        return [0x00, 0x00] + payload
    else:
        raise ValueError('Unknown header type')
