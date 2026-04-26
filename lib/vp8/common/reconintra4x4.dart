import 'dart:typed_data';

void intra_prediction_down_copy(Uint8List recon, int recon_off, int stride) {
  int src_off = recon_off + 16 - stride;
  
  int r0 = recon[src_off];
  int r1 = recon[src_off + 1];
  int r2 = recon[src_off + 2];
  int r3 = recon[src_off + 3];

  int dst_off = src_off;
  for (int i = 0; i < 3; i++) {
    dst_off += stride << 2;
    recon[dst_off] = r0;
    recon[dst_off + 1] = r1;
    recon[dst_off + 2] = r2;
    recon[dst_off + 3] = r3;
  }
}