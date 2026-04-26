import 'dart:typed_data';
import '../../vpx_dsp/bitreader.dart';

class BOOL_DECODER extends VpxReader {
  // These fields were undefined in the constructor but present in the original JS.
  // We'll define them as dynamic or specific types if we can infer them later.
  dynamic decrypt_cb;
  dynamic decrypt_state;
  dynamic buffer_end;
  bool clear_buffer = false;

  int get_uint(int bits) {
    return bool_get_uint(this, bits);
  }

  int get_int(int bits) {
    return bool_get_int(this, bits);
  }

  int maybe_get_int(int bits) {
    return bool_maybe_get_int(this, bits);
  }

  int read_bit() {
    return vpx_read_bit(this);
  }
}

void vp8dx_start_decode(BOOL_DECODER bool_dec, Uint8List start_partition, int ptr, int sz) {
  if (sz >= 2) {
    bool_dec.value = (start_partition[ptr] << 8) | start_partition[ptr + 1];
    bool_dec.input = start_partition;
    bool_dec.ptr = (ptr + 2);
    bool_dec.input_len = (sz - 2);
  } else {
    bool_dec.value = 0;
    bool_dec.input = null;
    bool_dec.input_len = 0;
  }

  bool_dec.range = 255;
  bool_dec.bit_count = 0;
}

int bool_get_uint(BOOL_DECODER bool_dec, int bits) {
  int z = 0;
  int bit = 0;

  for (bit = bits - 1; bit >= 0; bit--) {
    z |= (vpx_read_bit(bool_dec) << bit);
  }

  return z;
}

/**
 * bool_get_int
 * vp8_decode_value
 * @param {type} bits
 * @returns {BoolDecoder.get_int.z|Number}
 */
int bool_get_int(BOOL_DECODER bool_dec, int bits) {
  int z = 0;
  int bit = 0;

  for (bit = bits - 1; bit >= 0; bit--) {
    z |= (vpx_read_bit(bool_dec) << bit);
  }

  return vpx_read_bit(bool_dec) != 0 ? -z : z;
}

int bool_maybe_get_int(BOOL_DECODER bool_dec, int bits) {
  return vpx_read_bit(bool_dec) != 0 ? bool_dec.get_int(bits) : 0;
}

// Map the functions for internal use if needed, similar to JS
final bool_get_uint_alias = bool_get_uint;
final bool_get_int_alias = bool_get_int;
final bool_maybe_get_int_alias = bool_maybe_get_int;
