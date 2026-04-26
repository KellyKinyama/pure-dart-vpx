const int MV_PROB_CNT = 19;

void copyEntropyValues(dynamic header, dynamic otherHeader) {
  var probs = otherHeader.coeff_probs.data_32;
  var to = header.coeff_probs.data_32;
  //header.coeff_probs = otherHeader.coeff_probs.slice(0);
  //for (var i = 0; i < 264; i++)
  to.setAll(0, probs);

  //load mv probs
  probs = otherHeader.mv_probs;
  //header can probably be done faster
  //for (var i = 0; i < MV_PROB_CNT; i++)
  header.mv_probs[0].setAll(0, probs[0]);

  //for (var i = 0; i < MV_PROB_CNT; i++)
  header.mv_probs[1].setAll(0, probs[1]);

  //load y mode probs
  probs = otherHeader.y_mode_probs_32;
  header.y_mode_probs_32[0] = probs[0];

  //load uv mode probs
  probs = otherHeader.uv_mode_probs;
  //for (var i = 0; i < 3; i++)
  header.uv_mode_probs[0] = probs[0];
  header.uv_mode_probs[1] = probs[1];
  header.uv_mode_probs[2] = probs[2];

  header.prob_inter = otherHeader.prob_inter;
  header.prob_last = otherHeader.prob_inter;
  header.prob_gf = otherHeader.prob_inter;
}

void memset(List<int> ptr, int ptrOff, int value, int num) {
  var i = num;
  while (i-- > 0) {
    ptr[ptrOff + i] = value;
  }
}

void memset32(dynamic ptr, int ptrOff, int value, int num) {
  var ptrOff32 = ptrOff >> 2;
  var ptr32 = ptr.data_32;
  var value32 = value | (value << 8) | (value << 16) | (value << 24);

  var num32 = num >> 2;
  for (var i = 0; i < num32; i++) {
    ptr32[ptrOff32 + (i >> 2)] = value32;
  }
}

dynamic memcpy(dynamic dst, int dstOff, dynamic src, int srcOff, int num) {
  dst.setRange(dstOff, dstOff + num, src, srcOff);
  /*
     var i = num;
     while (i--) {
     dst[dst_off + i] = src[src_off + i];
     }
     */
  return dst;
}
