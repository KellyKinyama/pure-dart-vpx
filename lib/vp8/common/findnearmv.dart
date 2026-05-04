import 'mv.dart';
import '../decoder/onyxd_int.dart';
import 'blockd.dart';

const int DC_PRED = 0;
const int V_PRED = 1;
const int H_PRED = 2;
const int TM_PRED = 3;
const int B_PRED = 4;

const int B_DC_PRED = 0; /* average of above and left pixels */
const int B_TM_PRED = 1;
const int B_VE_PRED = 2; /* vertical prediction */
const int B_HE_PRED = 3; /* horizontal prediction */

// RFC 6386 §9.7 / §16.4: apply reference-frame sign bias to a candidate MV.
void mv_bias(
  MODE_INFO mb,
  List<int> sign_bias,
  int ref_frame,
  MotionVector mv,
) {
  if ((sign_bias[mb.mbmi.ref_frame] ^ sign_bias[ref_frame]) != 0) {
    mv.row = -mv.row;
    mv.col = -mv.col;
  }
}

int above_block_mode(
  List<MODE_INFO> cur_mb,
  int cur_mb_ptr,
  int b,
  int mi_stride,
) {
  if (b < 4) {
    cur_mb_ptr -= mi_stride;
    switch (cur_mb[cur_mb_ptr].mbmi.y_mode) {
      case B_PRED:
        return cur_mb[cur_mb_ptr].bmi!.modes[b + 12];
      case DC_PRED:
        return B_DC_PRED;
      case V_PRED:
        return B_VE_PRED;
      case H_PRED:
        return B_HE_PRED;
      case TM_PRED:
        return B_TM_PRED;
      default:
        return B_DC_PRED;
    }
  }

  return cur_mb[cur_mb_ptr].bmi!.modes[b - 4];
}

int left_block_mode(List<MODE_INFO> cur_mb, int cur_mb_ptr, int b) {
  if ((b & 3) == 0) {
    cur_mb_ptr -= 1;
    switch (cur_mb[cur_mb_ptr].mbmi.y_mode) {
      case DC_PRED:
        return B_DC_PRED;
      case V_PRED:
        return B_VE_PRED;
      case H_PRED:
        return B_HE_PRED;
      case TM_PRED:
        return B_TM_PRED;
      case B_PRED:
        return cur_mb[cur_mb_ptr].bmi!.modes[b + 3];
      default:
        return B_DC_PRED;
    }
  }

  return cur_mb[cur_mb_ptr].bmi!.modes[b - 1];
}
