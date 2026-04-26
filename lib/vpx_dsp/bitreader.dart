import 'dart:typed_data';

/// Equivalent to vpx_reader in libvpx
class VpxReader {
  int range = 0;
  int value = 0;
  Uint8List? input;
  int ptr = 0;
  int input_len = 0;
  int bit_count = 0;
}

/**
 * vp8dx_decode_bool
 * bool_get
 * @param {type} prob
 * @returns {Number}
 * vpx_read(vpx_reader *r, int prob) 
 */
int vpx_read(VpxReader r, int prob) {
  int split = 1 + (((r.range - 1) * prob) >> 8);
  int SPLIT = split << 8;
  int retval = 0;

  if (r.value >= SPLIT) {
    retval = 1;
    r.range -= split;
    r.value -= SPLIT;
  } else {
    retval = 0;
    r.range = split;
  }

  while (r.range < 128) {
    r.value <<= 1;
    r.range <<= 1;
    if (++r.bit_count == 8) {
      r.bit_count = 0;
      if (r.input_len > 0) {
        r.value |= r.input![r.ptr++];
        r.input_len--;
      }
    }
  }
  return retval;
}

int vpx_read_bit(VpxReader r) {
  return vpx_read(r, 128);
}

int vpx_read_literal(VpxReader r, int bits) {
  int z = 0;
  int bit = 0;

  for (bit = bits - 1; bit >= 0; bit--) {
    z |= (vpx_read_bit(r) << bit);
  }

  return z;
}