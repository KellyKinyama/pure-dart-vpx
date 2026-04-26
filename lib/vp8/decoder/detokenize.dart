import 'dart:typed_data';
import '../common/blockd.dart';
import '../../vpx_dsp/bitreader.dart';

const int B_PRED = 4;
const int SPLITMV = 9;

const int TOKEN_BLOCK_Y1 = 0;
const int TOKEN_BLOCK_UV = 1;
const int TOKEN_BLOCK_Y2 = 2;

const int EOB_CONTEXT_NODE = 0;
const int ZERO_CONTEXT_NODE = 1;
const int ONE_CONTEXT_NODE = 2;
const int LOW_VAL_CONTEXT_NODE = 3;
const int TWO_CONTEXT_NODE = 4;
const int THREE_CONTEXT_NODE = 5;
const int HIGH_LOW_CONTEXT_NODE = 6;
const int CAT_ONE_CONTEXT_NODE = 7;
const int CAT_THREEFOUR_CONTEXT_NODE = 8;
const int CAT_THREE_CONTEXT_NODE = 9;
const int CAT_FIVE_CONTEXT_NODE = 10;

const int DCT_VAL_CATEGORY5 = 9;
const int DCT_VAL_CATEGORY6 = 10;

const int ENTROPY_NODES = 11;

final Uint32List context_clear = Uint32List(8);

void vp8_reset_mb_tokens_context(List<int> left, List<int> above, int mode) {
  for (int i = 0; i < 8; i++) { left[i] = 0; above[i] = 0; }

  if (mode != B_PRED && mode != SPLITMV) {
    left[8] = 0;
    above[8] = 0;
  }
}

int X(int n) => (n * 33);

final Int32List bands_x = Int32List.fromList([
  X(0), X(1), X(2), X(3), X(6), X(4), X(5), X(6),
  X(6), X(6), X(6), X(6), X(6), X(6), X(6), X(7)
]);

class ExtraBit {
  final int min_val;
  final int length;
  final Uint8List probs;
  ExtraBit(this.min_val, this.length, List<int> p) : probs = Uint8List.fromList(p);
}

final List<ExtraBit> extrabits = [
  ExtraBit(0, -1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // ZERO_TOKEN
  ExtraBit(1, 0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // ONE_TOKEN
  ExtraBit(2, 0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // TWO_TOKEN
  ExtraBit(3, 0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // THREE_TOKEN
  ExtraBit(4, 0, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // FOUR_TOKEN
  ExtraBit(5, 0, [159, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // DCT_VAL_CATEGORY1
  ExtraBit(7, 1, [145, 165, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // DCT_VAL_CATEGORY2
  ExtraBit(11, 2, [140, 148, 173, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // DCT_VAL_CATEGORY3
  ExtraBit(19, 3, [135, 140, 155, 176, 0, 0, 0, 0, 0, 0, 0, 0]), // DCT_VAL_CATEGORY4
  ExtraBit(35, 4, [130, 134, 141, 157, 180, 0, 0, 0, 0, 0, 0, 0]), // DCT_VAL_CATEGORY5
  ExtraBit(67, 10, [129, 130, 133, 140, 153, 177, 196, 230, 243, 254, 254, 0]), // DCT_VAL_CATEGORY6
  ExtraBit(0, -1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) // EOB TOKEN
];

final Uint32List zigzag = Uint32List.fromList([
  0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15
]);

const int BLOCK_LOOP = 0, DO_WHILE = 1, CHECK_0_ = 2, CAT_FIVE_CONTEXT_NODE_0_ = 3, CAT_THREEFOUR_CONTEXT_NODE_0_ = 4, CAT_THREE_CONTEXT_NODE_0_ = 5, HIGH_LOW_CONTEXT_NODE_0_ = 6, CAT_ONE_CONTEXT_NODE_0_ = 7, LOW_VAL_CONTEXT_NODE_0_ = 8, THREE_CONTEXT_NODE_0_ = 9, TWO_CONTEXT_NODE_0_ = 10, ONE_CONTEXT_NODE_0_ = 11, BLOCK_FINISHED = 12, END = 13;

int decode_mb_tokens(VpxReader boolReader, List<int> left, List<int> above, Int32List tokens, int tokens_off, int mode, Uint8List probs, List<Int16List> factor) {
  int i = 0, stopp = 0, type = 0;
  int c = 0, t = 0, v = 0;
  int val = 0, bits_count = 0;
  int eob_mask = 0;
  int b_tokens_off = 0;
  int type_probs_off = 0;
  int prob_off = 0;
  late Int16List dqf;
  int goto_state = BLOCK_LOOP;

  if (mode != B_PRED && mode != SPLITMV) {
    i = 24; stopp = 24; type = 1;
    b_tokens_off = tokens_off + 384;
    dqf = factor[TOKEN_BLOCK_Y2];
  } else {
    i = 0; stopp = 16; type = 3;
    b_tokens_off = tokens_off;
    dqf = factor[TOKEN_BLOCK_Y1];
  }

  type_probs_off = type * 264;

  while (goto_state != END) {
    if (goto_state == BLOCK_LOOP) {
      t = left[vp8_block2left[i]] + above[vp8_block2above[i]];
      c = (type == 0) ? 0 : 1; // Wait, JS was: c = (!type) + 0;
      c = (type == 0) ? 1 : 0;
      prob_off = type_probs_off + t * ENTROPY_NODES;
      goto_state = DO_WHILE;
    }
    
    if (goto_state == DO_WHILE) {
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + EOB_CONTEXT_NODE]) == 0) {
        goto_state = BLOCK_FINISHED;
      } else {
        goto_state = CHECK_0_;
      }
    }
    
    if (goto_state == CHECK_0_) {
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + ZERO_CONTEXT_NODE]) == 0) {
        if (c < 15) {
          c++;
          prob_off = type_probs_off + bands_x[c]; // wait, JS: prob_off = type_probs_off; prob_off += bands_x[c] | 0;
          goto_state = CHECK_0_;
        } else {
          goto_state = BLOCK_FINISHED;
        }
        continue;
      }
      
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + ONE_CONTEXT_NODE]) == 0) {
        goto_state = ONE_CONTEXT_NODE_0_;
      } else if (vpx_read(boolReader, probs[prob_off + bands_x[c] + LOW_VAL_CONTEXT_NODE]) == 0) {
        goto_state = LOW_VAL_CONTEXT_NODE_0_;
      } else if (vpx_read(boolReader, probs[prob_off + bands_x[c] + HIGH_LOW_CONTEXT_NODE]) == 0) {
        goto_state = HIGH_LOW_CONTEXT_NODE_0_;
      } else if (vpx_read(boolReader, probs[prob_off + bands_x[c] + CAT_THREEFOUR_CONTEXT_NODE]) == 0) {
        goto_state = CAT_THREEFOUR_CONTEXT_NODE_0_;
      } else if (vpx_read(boolReader, probs[prob_off + bands_x[c] + CAT_FIVE_CONTEXT_NODE]) == 0) {
        goto_state = CAT_FIVE_CONTEXT_NODE_0_;
      } else {
        val = extrabits[DCT_VAL_CATEGORY6].min_val;
        bits_count = extrabits[DCT_VAL_CATEGORY6].length;
        do {
          val += vpx_read(boolReader, extrabits[DCT_VAL_CATEGORY6].probs[bits_count]) << bits_count;
          bits_count--;
        } while (bits_count >= 0);
        
        // APPLY SIGN
        if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
        prob_off = type_probs_off + 22;
        if (c < 15) {
          tokens[b_tokens_off + zigzag[c]] = v;
          c++;
          goto_state = DO_WHILE;
        } else {
          tokens[b_tokens_off + zigzag[15]] = v;
          goto_state = BLOCK_FINISHED;
        }
      }
    }

    if (goto_state == CAT_FIVE_CONTEXT_NODE_0_) {
      val = extrabits[DCT_VAL_CATEGORY5].min_val;
      for (int b = 4; b >= 0; b--) val += vpx_read(boolReader, extrabits[DCT_VAL_CATEGORY5].probs[b]) << b;
      if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + 22;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == CAT_THREEFOUR_CONTEXT_NODE_0_) {
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + CAT_THREE_CONTEXT_NODE]) == 0) {
        goto_state = CAT_THREE_CONTEXT_NODE_0_;
      } else {
        val = extrabits[8].min_val; // CAT4
        for (int b = 3; b >= 0; b--) val += vpx_read(boolReader, extrabits[8].probs[b]) << b;
        if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
        prob_off = type_probs_off + 22;
        if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
      }
    }

    if (goto_state == CAT_THREE_CONTEXT_NODE_0_) {
      val = extrabits[7].min_val; // CAT3
      for (int b = 2; b >= 0; b--) val += vpx_read(boolReader, extrabits[7].probs[b]) << b;
      if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + 22;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == HIGH_LOW_CONTEXT_NODE_0_) {
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + CAT_ONE_CONTEXT_NODE]) == 0) {
        goto_state = CAT_ONE_CONTEXT_NODE_0_;
      } else {
        val = extrabits[6].min_val; // CAT2
        for (int b = 1; b >= 0; b--) val += vpx_read(boolReader, extrabits[6].probs[b]) << b;
        if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
        prob_off = type_probs_off + 22;
        if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
      }
    }

    if (goto_state == CAT_ONE_CONTEXT_NODE_0_) {
      val = extrabits[5].min_val; // CAT1
      val += vpx_read(boolReader, extrabits[5].probs[0]) << 0;
      if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + 22;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == LOW_VAL_CONTEXT_NODE_0_) {
      if (vpx_read(boolReader, probs[prob_off + bands_x[c] + TWO_CONTEXT_NODE]) == 0) {
        goto_state = TWO_CONTEXT_NODE_0_;
      } else if (vpx_read(boolReader, probs[prob_off + bands_x[c] + THREE_CONTEXT_NODE]) == 0) {
        goto_state = THREE_CONTEXT_NODE_0_;
      } else {
        val = 4;
        if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
        prob_off = type_probs_off + 22;
        if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
      }
    }

    if (goto_state == THREE_CONTEXT_NODE_0_) {
      val = 3;
      if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + 22;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == TWO_CONTEXT_NODE_0_) {
      val = 2;
      if (vpx_read_bit(boolReader) == 1) v = -val * dqf[(c != 0 ? 1 : 0)]; else v = val * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + 22;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == ONE_CONTEXT_NODE_0_) {
      if (vpx_read_bit(boolReader) == 1) v = -1 * dqf[(c != 0 ? 1 : 0)]; else v = 1 * dqf[(c != 0 ? 1 : 0)];
      prob_off = type_probs_off + ENTROPY_NODES;
      if (c < 15) { tokens[b_tokens_off + zigzag[c]] = v; c++; goto_state = DO_WHILE; } else { tokens[b_tokens_off + zigzag[15]] = v; goto_state = BLOCK_FINISHED; }
    }

    if (goto_state == BLOCK_FINISHED) {
      eob_mask = (eob_mask | ((c > ((type == 0) ? 0 : 1) ? 1 : 0) << i));
      t = (c != ((type == 0) ? 0 : 1)) ? 1 : 0;
      eob_mask = (eob_mask | (t << 31));
      left[vp8_block2left[i]] = above[vp8_block2above[i]] = t;
      b_tokens_off += 16;
      i++;
      if (i < stopp) {
        goto_state = BLOCK_LOOP;
        continue;
      }
      if (i == 25) {
        type = 0; i = 0; stopp = 16;
        type_probs_off = type << 8;
        b_tokens_off = tokens_off;
        dqf = factor[TOKEN_BLOCK_Y1];
        goto_state = BLOCK_LOOP;
        continue;
      }
      if (i == 16) {
        type = 2;
        type_probs_off = type * 264;
        stopp = 24;
        dqf = factor[TOKEN_BLOCK_UV];
        goto_state = BLOCK_LOOP;
        continue;
      }
      goto_state = END;
    }
  }
  return eob_mask;
}