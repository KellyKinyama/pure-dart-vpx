import 'dart:typed_data';
import '../../vpx_dsp/bitreader.dart';

class BOOL_DECODER extends VpxReader {
  // RFC 6386 §7: Boolean entropy decoder. The libvpx C struct also carries
  // optional `vpx_decrypt_cb decrypt_cb`, `void *decrypt_state`,
  // `const unsigned char *buffer_end`, and `int clear_buffer`. They are
  // unused in this port. Reintroduce them only with concrete types:
  //   typedef VpxDecryptCb = void Function(
  //       VpxDecryptState state, Uint8List inBuf, int inOff,
  //       Uint8List outBuf, int outOff, int n);
  //   VpxDecryptState? decrypt_state; int buffer_end_off = 0; int clear_buffer = 0;
  // (where `VpxDecryptState` is an abstract marker class for the void* cookie.)

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

void vp8dx_start_decode(
  BOOL_DECODER bool_dec,
  Uint8List start_partition,
  int ptr,
  int sz,
) {
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
