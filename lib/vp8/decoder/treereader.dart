import '../../vpx_dsp/bitreader.dart';

int vp8_treed_read(VpxReader r, List<int> t, List<int> p, [int p_off = 0]) {
  int i = 0;
  while (true) {
    int bit = vpx_read(r, p[p_off + (i >> 1)]);
    i = t[i + bit];
    if (i <= 0) break;
  }
  return (-i);
}